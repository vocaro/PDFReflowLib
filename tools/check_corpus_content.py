#!/usr/bin/env python3
"""Check reviewed positive content contracts separately from EPUB/resource validation.

No conversion or downloads. Uses a complete evaluator output and the pinned corpus manifest.
Phrase checks are page-specific, apart from spine-boundary continuity, which is checked over
the written spine; whitespace and inline styling do not affect matching.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import xml.etree.ElementTree as ET
import zipfile

from pdfreflow_tools import epub
from pdfreflow_tools.corpus import ROOT, find_case, manifest_cases, regression_contracts
from pdfreflow_tools.epub import DEFAULT_MAX_ENTRIES, DEFAULT_MAX_UNCOMPRESSED_BYTES, inspection_limit

HTML = epub.XHTML
HEADINGS = {HTML + 'h' + str(n) for n in range(1, 7)}
BLOCKS = HEADINGS | {HTML + tag for tag in ('p', 'pre', 'figure', 'li')}

# Every kind of check `assess` counts, and where its expectations sit in a contract. `sequence`
# keys hold one expectation per check; `presence` keys are one check when the key is present.
# `assess` compares its own running total against this table, so a new kind of check that is not
# recorded here fails the corpus lane rather than quietly making the documented counts wrong
# (#156; tools/update_doc_counts.py reads the table and nothing else).
CONTRACT_CHECK_TYPES = {'spineContinuity': 'sequence'}
PAGE_CHECK_TYPES = {
    'text': 'sequence', 'orderedText': 'sequence', 'absentText': 'sequence',
    'headings': 'sequence', 'paragraphs': 'sequence', 'continuedParagraphs': 'sequence',
    'scripts': 'sequence', 'imageRegions': 'sequence',
    'minimumImages': 'presence', 'warningCodesAnyOf': 'presence', 'absentWarningCodes': 'presence',
}


def count_checks(contracts):
    """How many checks the reviewed contracts hold, by kind, without running a conversion."""
    by_type = dict.fromkeys(list(CONTRACT_CHECK_TYPES) + list(PAGE_CHECK_TYPES), 0)
    pages = 0
    for contract in contracts:
        for name, kind in CONTRACT_CHECK_TYPES.items():
            by_type[name] += len(contract.get(name, ()))
        for item in contract.get('pages', ()):
            pages += 1
            for name, kind in PAGE_CHECK_TYPES.items():
                by_type[name] += len(item.get(name, ())) if kind == 'sequence' else int(name in item)
    return {'checks': sum(by_type.values()), 'pages': pages,
            'documents': sum(1 for contract in contracts if contract.get('pages')),
            'byType': by_type}


def cli_inspection_limit(value):
    try:
        return inspection_limit(int(value), 'inspection limit')
    except ValueError as error:
        raise argparse.ArgumentTypeError(str(error)) from error


def normalized(text):
    return ' '.join(text.split())


def read_spine(path, *, max_entries=DEFAULT_MAX_ENTRIES,
               max_uncompressed_bytes=DEFAULT_MAX_UNCOMPRESSED_BYTES):
    """Read spine content with explicit ZIP entry-count and total expanded-byte ceilings.

    Returns the pages, the source-page markers in written order, and one record per spine
    document (its archive name, its text and the source pages it carries), so that a contract
    can assert what crosses a spine-document boundary as well as what sits on a source page.

    These admission limits are not process-memory budgets. Images are not expanded;
    chapter XML and accumulated page text still consume memory after admission.
    """
    pages, markers, documents = {}, [], []
    current = None
    heading_id = 0
    paragraph_id = 0
    with epub.open_archive(path, max_entries=max_entries, max_uncompressed_bytes=max_uncompressed_bytes) as archive:
        names = set(archive.namelist())
        for name in epub.read_package(archive).spine:
            chapter = PurePosixPath(name)
            tree = ET.fromstring(archive.read(name))
            # A document carries the page still open when it starts, then every page it opens.
            document = {'name': name, 'text': '', 'pages': [] if current is None else [current]}
            documents.append(document)

            def append(text, script=None, heading=None, paragraph=None):
                if not text:
                    return
                document['text'] += text
                if current is not None:
                    page = pages[current]
                    start = len(page['text'])
                    page['text'] += text
                    if heading is not None:
                        page['headings'][heading] = page['headings'].get(heading, '') + text
                    if paragraph is not None:
                        page['paragraphs'][paragraph] = page['paragraphs'].get(paragraph, '') + text
                    if script:
                        spans = page['scripts']
                        if spans and spans[-1]['tag'] == script and spans[-1]['end'] == start:
                            spans[-1]['end'] += len(text)
                        else:
                            spans.append({'tag': script, 'start': start, 'end': start + len(text)})

            def walk(element, script=None, heading=None, paragraph=None):
                nonlocal current, heading_id, paragraph_id
                page = epub.page_boundary(element)
                if page is not None:
                    if page in pages:
                        raise ValueError('Duplicate page boundary')
                    current = page
                    markers.append(current)
                    document['pages'].append(current)
                    pages[current] = {'text': '', 'images': [], 'scripts': [], 'headings': {}, 'paragraphs': {}}
                if element.tag == HTML + 'img' and current is not None:
                    asset = str(chapter.parent / element.attrib['src'])
                    if asset not in names:
                        raise ValueError('Missing image asset: ' + asset)
                    pages[current]['images'].append(asset)
                # Generic converter captions must not satisfy source-text expectations.
                if element.tag == HTML + 'figcaption':
                    return
                if element.tag in (HTML + 'sup', HTML + 'sub'):
                    script = element.tag[len(HTML):]
                if element.tag in HEADINGS:
                    heading_id += 1
                    heading = heading_id
                if element.tag == HTML + 'p':
                    paragraph_id += 1
                    paragraph = paragraph_id
                append(element.text, script, heading, paragraph)
                for child in element:
                    walk(child, script, heading, paragraph)
                    append(child.tail, script, heading, paragraph)
                if element.tag in BLOCKS:
                    append(' ')

            walk(tree.find(HTML + 'body'))
    for page in pages.values():
        raw = page['text']
        page['scripts'] = [{'tag': span['tag'], 'text': normalized(raw[span['start']:span['end']]),
                            'before': normalized(raw[max(0, span['start'] - 128):span['start']]),
                            'after': normalized(raw[span['end']:span['end'] + 128])}
                           for span in page['scripts']]
        page['text'] = normalized(raw)
        page['headings'] = [normalized(text) for text in page['headings'].values()]
        # Paragraph IDs are document-wide, so one <p> crossing a page marker has the same ID on both pages.
        page['paragraphIDs'] = {paragraph: normalized(text) for paragraph, text in page['paragraphs'].items()}
        page['paragraphs'] = [normalized(text) for text in page['paragraphs'].values()]
    for document in documents:
        document['text'] = normalized(document['text'])
    return pages, markers, documents


def read_pages(path, **limits):
    """The pages and their markers alone, for callers that do not inspect spine documents."""
    pages, markers, _ = read_spine(path, **limits)
    return pages, markers


def reference_image(case, contract, number, expectation, reference_root=ROOT):
    """Validate a region expectation and return its reference PNG bytes."""
    import image_regions  # Imported on use: numpy and Pillow are only needed for image-region checks.
    if (not isinstance(expectation, dict) or not set(expectation) <= {'reference', 'minimumCorrelation'}
            or not isinstance(expectation.get('reference'), str)):
        raise ValueError('Image region requires a reference path and optional minimumCorrelation')
    minimum = expectation.get('minimumCorrelation', image_regions.DEFAULT_MINIMUM_CORRELATION)
    if type(minimum) not in (int, float) or not 0.5 <= minimum <= 1:
        raise ValueError('Image region minimumCorrelation must be between 0.5 and 1')
    relative = PurePosixPath(expectation['reference'])
    if (relative.suffix != '.png' or relative.parts[:3] != ('corpus', 'references', case['id'])
            or len(relative.parts) != 4 or '..' in relative.parts):
        raise ValueError('Image region reference must be corpus/references/<case>/<name>.png')
    path = Path(reference_root) / relative
    sidecar = json.loads(path.with_suffix('.json').read_text())
    if sidecar.get('sourceSHA256') != contract['sourceSHA256'] or sidecar.get('page') != number:
        raise ValueError(f'Image region reference {relative} was rendered from another source or page')
    if (sidecar.get('renderDPI'), sidecar.get('referenceDPI')) != (image_regions.RENDER_DPI, image_regions.REFERENCE_DPI):
        raise ValueError(f'Image region reference {relative} uses another resolution')
    return path.read_bytes(), minimum


def ordered_in(text, phrases):
    """Whether every phrase occurs in text, each after the previous one."""
    cursor = 0
    for phrase in phrases:
        index = text.find(phrase, cursor)
        if index < 0:
            return False
        cursor = index + len(phrase)
    return True


def spine_continuity(case, contract, documents):
    """Check that reviewed text continuing past a spine-document boundary arrives intact.

    Each expectation names phrases the source sets on either side of a join. They must occur
    once in the whole book (nothing duplicated) and in order, either inside one spine document
    or with the earlier ones in one document and the later ones in the very next; the documents
    at both ends must carry the reviewed source pages. `contiguous` additionally forbids any
    word between the last phrase and the first one after it, so nothing may be dropped or
    inserted at the join.

    Where the packer ends a document is not a reviewed property: it follows from the serialized
    byte target, so any change to the block stream moves it, and a contract that demanded a
    boundary at a named place would fail for a book whose text is perfectly intact. What is
    reviewed is the text, so a join the packer keeps inside one document passes. The returned
    `crossed` count says how many of the expectations did straddle a boundary, so a lane that
    has stopped exercising one is visible rather than silently green.
    """
    checks, crossed, errors = 0, 0, []
    book = ' '.join(document['text'] for document in documents)
    for entry in contract.get('spineContinuity', []):
        if (not isinstance(entry, dict) or not {'sourcePages', 'beforeBoundary', 'afterBoundary'} <= set(entry)
                or not set(entry) <= {'sourcePages', 'beforeBoundary', 'afterBoundary', 'contiguous'}
                or type(entry.get('contiguous', False)) is not bool):
            raise ValueError('Spine continuity requires source pages and phrases on both sides of one boundary')
        numbers = entry['sourcePages']
        if (not isinstance(numbers, list) or not numbers
                or any(type(number) is not int or not 1 <= number <= case['pages'] for number in numbers)
                or numbers != sorted(numbers)):
            raise ValueError('Spine continuity needs ordered in-range source pages')
        sides = []
        for key in ('beforeBoundary', 'afterBoundary'):
            phrases = entry[key]
            if (not isinstance(phrases, list) or not phrases
                    or any(not isinstance(phrase, str) or not normalized(phrase) for phrase in phrases)):
                raise ValueError('Spine continuity needs nonempty phrases on both sides')
            sides.append([normalized(phrase) for phrase in phrases])
        before, after = sides
        checks += 1
        repeated = [phrase for phrase in before + after if book.count(phrase) != 1]
        if repeated:
            errors.append(f'Spine boundary: text missing or duplicated elsewhere in the book {repeated!r}')
            continue
        pair = next(((i, i) for i in range(len(documents))
                     if ordered_in(documents[i]['text'], before + after)), None)
        if pair is None:
            pair = next(((i, i + 1) for i in range(len(documents) - 1)
                         if ordered_in(documents[i]['text'], before)
                         and ordered_in(documents[i + 1]['text'], after)), None)
        if pair is None:
            errors.append('Spine boundary: reviewed text does not run in order within one document '
                          f'or across one boundary {entry!r}')
            continue
        first, second = pair
        crossed += first != second
        if numbers[0] not in documents[first]['pages'] or numbers[-1] not in documents[second]['pages']:
            errors.append(f'Spine boundary: documents holding the join do not carry source pages {numbers}')
        if entry.get('contiguous'):
            joined = documents[first]['text'] if first == second \
                else documents[first]['text'] + ' ' + documents[second]['text']
            start = joined.index(before[-1]) + len(before[-1])
            between = joined[start:joined.index(after[0], start)]
            if any(character.isalnum() for character in between):
                errors.append(f'Spine boundary: text inserted or dropped at the join {between[:96]!r}')
    return checks, crossed, errors


def assess(case, contract, result, report, pages, markers, *, documents=(),
           image_data=None, reference_root=ROOT):
    """Assess a contract. image_data(asset) returns converted image bytes for imageRegions checks."""
    errors = []
    if (contract['sourceSHA256'] != case['sha256'] or any(
            result.get('case', {}).get(k) != case[k] for k in ('id', 'sha256', 'bytes', 'pages'))):
        errors.append('Source identity differs from the reviewed contract')
    # A ceiling host memory pressure left unmeasured says nothing about this document's content
    # ([decision 0009](../doc/decisions/0009-an-unmeasured-ceiling-is-not-a-failure.md)), so the
    # contract is assessed on its own terms; every other gate still has to have passed.
    unmeasured_memory = (result.get('memoryGate', {}).get('status') == 'notMeasured'
                         and result.get('gatesPassedApartFromMemory') is True)
    if result.get('conversionExitCode') != 0 or not (result.get('runPassed') is True or unmeasured_memory):
        errors.append('Conversion/resource/progress evaluation did not pass')
    if report.get('pageCount') != case['pages'] or markers != list(range(1, case['pages'] + 1)):
        errors.append('Missing, duplicated or reordered source pages')
    if any('\ufffc' in page['text'] for page in pages.values()):
        errors.append('Object placeholder in semantic text')
    expected = contract['pages']
    numbers = [item['page'] for item in expected]
    if (not expected or len(numbers) != len(set(numbers))
            or any(type(p) is not int or not 1 <= p <= case['pages'] for p in numbers)):
        raise ValueError('Contract needs distinct in-range review pages')
    checks, crossedBoundaries, continuity = spine_continuity(case, contract, documents)
    errors += continuity
    for item in expected:
        number = item['page']
        page = pages.get(number, {'text': '', 'images': []})
        if not any(key in item for key in ('text', 'orderedText', 'minimumImages', 'warningCodesAnyOf', 'absentWarningCodes', 'scripts', 'absentText', 'headings', 'paragraphs', 'continuedParagraphs', 'imageRegions')):
            raise ValueError('Review page has no expectations')
        for phrase in item.get('text', []):
            if not normalized(phrase):
                raise ValueError('Empty phrase')
            checks += 1
            if normalized(phrase) not in page['text']:
                errors.append(f'Page {number}: missing text {phrase!r}')
        for phrase in item.get('absentText', []):
            if not isinstance(phrase, str) or not normalized(phrase):
                raise ValueError('Empty or invalid forbidden phrase')
            checks += 1
            if normalized(phrase) in page['text']:
                errors.append(f'Page {number}: unwanted text {phrase!r}')
        for phrase in item.get('headings', []):
            if not isinstance(phrase, str) or not normalized(phrase):
                raise ValueError('Empty or invalid heading phrase')
            checks += 1
            if not any(normalized(phrase) in heading for heading in page.get('headings', [])):
                errors.append(f'Page {number}: missing heading {phrase!r}')
        for phrase in item.get('paragraphs', []):
            if not isinstance(phrase, str) or not normalized(phrase):
                raise ValueError('Empty or invalid paragraph phrase')
            checks += 1
            if not any(normalized(phrase) in paragraph for paragraph in page.get('paragraphs', [])):
                errors.append(f'Page {number}: missing paragraph {phrase!r}')
        following = pages.get(number + 1, {})
        for continuation in item.get('continuedParagraphs', []):
            if (not isinstance(continuation, dict) or set(continuation) != {'end', 'next'}
                    or any(not isinstance(continuation[k], str) or not normalized(continuation[k]) for k in ('end', 'next'))):
                raise ValueError('Paragraph continuation requires nonempty end and next phrases')
            checks += 1
            end, after = normalized(continuation['end']), normalized(continuation['next'])
            # The same paragraph element must end this page with one phrase and continue the next page with the other.
            if not any(end in text and paragraph in following.get('paragraphIDs', {})
                       and after in following['paragraphIDs'][paragraph]
                       for paragraph, text in page.get('paragraphIDs', {}).items()):
                errors.append(f'Page {number}: paragraph does not continue onto page {number + 1} {continuation!r}')
        cursor = 0
        for phrase in item.get('orderedText', []):
            if not normalized(phrase):
                raise ValueError('Empty ordered phrase')
            checks += 1
            index = page['text'].find(normalized(phrase), cursor)
            if index < 0:
                errors.append(f'Page {number}: missing or reordered text {phrase!r}')
            else:
                cursor = index + len(normalized(phrase))
        for script in item.get('scripts', []):
            if (script.get('tag') not in ('sup', 'sub')
                    or any(not isinstance(script.get(k), str) or not 1 <= len(normalized(script[k])) <= 96
                           for k in ('text', 'before', 'after'))):
                raise ValueError('Script check requires sup/sub and nonempty bounded text/context')
            checks += 1
            if not any(span['tag'] == script['tag'] and span['text'] == normalized(script['text'])
                       and span['before'].endswith(normalized(script['before']))
                       and span['after'].startswith(normalized(script['after']))
                       for span in page.get('scripts', [])):
                errors.append(f'Page {number}: missing script or incorrect context {script!r}')
        for expectation in item.get('imageRegions', []):
            reference, minimum = reference_image(case, contract, number, expectation, reference_root)
            checks += 1
            if image_data is None:
                errors.append(f'Page {number}: converted images unavailable for {expectation["reference"]}')
                continue
            import image_regions
            score = image_regions.region_score(reference, [image_data(asset) for asset in page['images']])
            if score < minimum:
                errors.append(f'Page {number}: no image shows {expectation["reference"]} '
                              f'(best correlation {score:.3f} < {minimum})')
        if 'minimumImages' in item:
            minimum = item['minimumImages']
            if type(minimum) is not int or minimum < 1:
                raise ValueError('Image minimum must be positive')
            checks += 1
            if len(page['images']) < minimum:
                errors.append(f'Page {number}: missing preserved images')
        if 'warningCodesAnyOf' in item:
            codes = item['warningCodesAnyOf']
            if not codes:
                raise ValueError('Empty warning expectation')
            checks += 1
            if not any(w.get('page') == number and w.get('code') in codes for w in report.get('warnings', [])):
                errors.append(f'Page {number}: missing quality warning')
        if 'absentWarningCodes' in item:
            codes = item['absentWarningCodes']
            if not codes:
                raise ValueError('Empty absent-warning expectation')
            checks += 1
            unexpected = sorted({w.get('code') for w in report.get('warnings', [])
                                 if w.get('page') == number and w.get('code') in codes})
            if unexpected:
                errors.append(f'Page {number}: unexpected quality warning ' + ', '.join(unexpected))
    if checks == 0:
        raise ValueError('Contract has no content checks')
    if checks != count_checks([contract])['checks']:
        raise ValueError('Contract check count disagrees with CONTRACT_CHECK_TYPES/PAGE_CHECK_TYPES; '
                         'a kind of check was added without recording it (#156)')
    return {'case': case['id'], 'passed': not errors, 'reviewPages': numbers,
            'contentChecks': checks, 'spineBoundariesCrossed': crossedBoundaries, 'errors': errors,
            'scope': 'Reviewed text/order/script-context/image-presence, spine-boundary continuity and source-region image checks; not full-book fidelity or image legibility qualification.'}


def check_evaluation(case, contract, directory, *, max_entries=DEFAULT_MAX_ENTRIES,
                     max_uncompressed_bytes=DEFAULT_MAX_UNCOMPRESSED_BYTES):
    result = json.loads((directory / 'result.json').read_text())
    report = json.loads((directory / 'conversion-report.json').read_text())
    path = directory / (case['id'] + '.epub')
    pages, markers, documents = read_spine(path, max_entries=max_entries,
                                           max_uncompressed_bytes=max_uncompressed_bytes)
    with zipfile.ZipFile(path) as archive:
        return assess(case, contract, result, report, pages, markers,
                      documents=documents, image_data=archive.read)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', required=True)
    parser.add_argument('--evaluation', type=Path, required=True)
    parser.add_argument('--max-entries', type=cli_inspection_limit, default=DEFAULT_MAX_ENTRIES,
                        help=f'maximum ZIP entries (default: {DEFAULT_MAX_ENTRIES})')
    parser.add_argument('--max-uncompressed-bytes', type=cli_inspection_limit,
                        default=DEFAULT_MAX_UNCOMPRESSED_BYTES,
                        help=f'maximum total expanded ZIP bytes (default: {DEFAULT_MAX_UNCOMPRESSED_BYTES})')
    args = parser.parse_args()
    case = find_case(manifest_cases(ROOT), args.case)
    contract = find_case(regression_contracts(ROOT)['cases'], args.case)
    if case is None or contract is None:
        parser.error('case has no reviewed content contract')
    try:
        assessment = check_evaluation(case, contract, args.evaluation,
                                      max_entries=args.max_entries,
                                      max_uncompressed_bytes=args.max_uncompressed_bytes)
    except (OSError, ValueError, KeyError, TypeError, AttributeError, ET.ParseError, zipfile.BadZipFile) as error:
        assessment = {'case': args.case, 'passed': False, 'errors': [str(error)]}
    print(json.dumps(assessment, indent=2))
    return 0 if assessment['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
