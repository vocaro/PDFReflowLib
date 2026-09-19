#!/usr/bin/env python3
"""Check reviewed positive content contracts separately from EPUB/resource validation.

No conversion or downloads. Uses a complete evaluator output and the pinned corpus manifest.
Phrase checks are page-specific; whitespace and inline styling do not affect matching.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HTML = '{http://www.w3.org/1999/xhtml}'
OPF = '{http://www.idpf.org/2007/opf}'
EPUB = '{http://www.idpf.org/2007/ops}'
HEADINGS = {HTML + 'h' + str(n) for n in range(1, 7)}
BLOCKS = HEADINGS | {HTML + tag for tag in ('p', 'pre', 'figure', 'li')}
DEFAULT_MAX_ENTRIES = 10_000
DEFAULT_MAX_UNCOMPRESSED_BYTES = 512 * 1024 * 1024


def inspection_limit(value, name):
    if type(value) is not int or not 1 <= value <= sys.maxsize:
        raise ValueError(f'{name} must be an integer from 1 to {sys.maxsize}')
    return value


def cli_inspection_limit(value):
    try:
        return inspection_limit(int(value), 'inspection limit')
    except ValueError as error:
        raise argparse.ArgumentTypeError(str(error)) from error


def normalized(text):
    return ' '.join(text.split())


def read_pages(path, *, max_entries=DEFAULT_MAX_ENTRIES,
               max_uncompressed_bytes=DEFAULT_MAX_UNCOMPRESSED_BYTES):
    """Read spine content with explicit ZIP entry-count and total expanded-byte ceilings.

    These admission limits are not process-memory budgets. Images are not expanded;
    chapter XML and accumulated page text still consume memory after admission.
    """
    inspection_limit(max_entries, 'max_entries')
    inspection_limit(max_uncompressed_bytes, 'max_uncompressed_bytes')
    pages, markers = {}, []
    current = None
    heading_id = 0
    paragraph_id = 0
    with zipfile.ZipFile(path) as archive:
        if (len(archive.infolist()) > max_entries
                or sum(e.file_size for e in archive.infolist()) > max_uncompressed_bytes):
            raise ValueError('EPUB exceeds inspection bounds')
        names = set(archive.namelist())
        if len(names) != len(archive.infolist()):
            raise ValueError('Duplicate archive entries')
        package = ET.fromstring(archive.read('EPUB/package.opf'))
        manifest = {e.get('id'): e.get('href') for e in package.find(OPF + 'manifest')}
        for reference in package.find(OPF + 'spine'):
            chapter = PurePosixPath('EPUB') / manifest[reference.get('idref')]
            tree = ET.fromstring(archive.read(str(chapter)))

            def append(text, script=None, heading=None, paragraph=None):
                if current is not None and text:
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
                if 'pagebreak' in element.get(EPUB + 'type', '').split():
                    anchor = element.get('id', '')
                    if not re.fullmatch(r'page-[1-9]\d*', anchor):
                        raise ValueError('Invalid page boundary')
                    current = int(anchor[5:])
                    if current in pages:
                        raise ValueError('Duplicate page boundary')
                    markers.append(current)
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


def assess(case, contract, result, report, pages, markers, image_data=None, reference_root=ROOT):
    """Assess a contract. image_data(asset) returns converted image bytes for imageRegions checks."""
    errors = []
    if (contract['sourceSHA256'] != case['sha256'] or any(
            result.get('case', {}).get(k) != case[k] for k in ('id', 'sha256', 'bytes', 'pages'))):
        errors.append('Source identity differs from the reviewed contract')
    if result.get('runPassed') is not True or result.get('conversionExitCode') != 0:
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
    checks = 0
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
    return {'case': case['id'], 'passed': not errors, 'reviewPages': numbers,
            'contentChecks': checks, 'errors': errors,
            'scope': 'Reviewed text/order/script-context/image-presence and source-region image checks; not full-book fidelity or image legibility qualification.'}


def check_evaluation(case, contract, directory, *, max_entries=DEFAULT_MAX_ENTRIES,
                     max_uncompressed_bytes=DEFAULT_MAX_UNCOMPRESSED_BYTES):
    result = json.loads((directory / 'result.json').read_text())
    report = json.loads((directory / 'conversion-report.json').read_text())
    path = directory / (case['id'] + '.epub')
    pages, markers = read_pages(path, max_entries=max_entries, max_uncompressed_bytes=max_uncompressed_bytes)
    with zipfile.ZipFile(path) as archive:
        return assess(case, contract, result, report, pages, markers, image_data=archive.read)


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
    cases = json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']
    contracts = json.loads((ROOT / 'corpus/regressions.json').read_text())['cases']
    case = next((c for c in cases if c['id'] == args.case), None)
    contract = next((c for c in contracts if c['id'] == args.case), None)
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
