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
BLOCKS = HEADINGS | {HTML + tag for tag in ('p', 'pre', 'figure', 'li', 'table', 'caption', 'tr', 'th', 'td')}
DEFAULT_MAX_ENTRIES = 10_000
DEFAULT_MAX_UNCOMPRESSED_BYTES = 512 * 1024 * 1024
# Every expectation key `assess` counts, as (documented name, keys, counted once per page). List
# keys count one check per entry. The order is the order the docs list them in; `assess` verifies
# its own count against this table, and tools/update_doc_counts.py reports from it.
CHECK_TYPES = (
    ('ordered-text', ('orderedText',), False),
    ('text', ('text',), False),
    ('paragraph', ('paragraphs',), False),
    ('absent-text', ('absentText',), False),
    ('heading', ('headings',), False),
    ('absent-heading', ('absentHeadings',), False),
    ('list-item', ('listItems',), False),
    ('preformatted-lines', ('preformattedLines',), False),
    ('script', ('scripts',), False),
    ('absent-script', ('absentScripts',), False),
    ('footnote', ('notes',), False),
    ('note-link', ('noteLinks',), False),
    ('paragraph-continuation', ('continuedParagraphs',), False),
    ('list-item-continuation', ('continuedListItems',), False),
    ('paragraph-separation', ('separateParagraphs',), False),
    ('distinct-paragraph', ('distinctParagraphs',), False),
    ('image-presence', ('minimumImages', 'maximumImages'), True),
    ('page-reference', ('pageReference',), True),
    ('warning', ('warningCodesAnyOf',), True),
    ('absent-warning', ('absentWarningCodes',), True),
    ('source-region', ('imageRegions',), False),
    ('glyph-structure', ('glyphRegions',), False),
    ('image-appearance', ('imageAppearance',), False),
    ('table-cell', ('tableCells',), False),
)
EXPECTATION_KEYS = tuple(key for _, keys, _ in CHECK_TYPES for key in keys)


def count_page_checks(item):
    """Checks one review page contributes, by documented check type (zero types included)."""
    return {name: sum((1 if key in item else 0) if once else len(item.get(key, [])) for key in keys)
            for name, keys, once in CHECK_TYPES}


def count_checks(contracts):
    """Totals over regressions.json cases, counted as `assess` counts them."""
    by_type = dict.fromkeys((name for name, _, _ in CHECK_TYPES), 0)
    pages = documents = 0
    for contract in contracts:
        items = contract.get('pages', [])
        documents += bool(items)
        pages += len(items)
        for item in items:
            for name, count in count_page_checks(item).items():
                by_type[name] += count
    return {'checks': sum(by_type.values()), 'pages': pages, 'documents': documents, 'byType': by_type}


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
    item_id = 0
    note_id = 0
    # Elements with ids, keyed 'EPUB/file#id', accumulate their text across page markers so a
    # note continued onto the next page is still one link target.
    open_anchors = []
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

            def append(text, script=None, heading=None, paragraph=None, note=None, item=None):
                if current is not None and text:
                    page = pages[current]
                    start = len(page['text'])
                    page['text'] += text
                    for anchor in open_anchors:
                        anchor['text'] += text
                    if heading is not None:
                        page['headings'][heading] = page['headings'].get(heading, '') + text
                    if paragraph is not None:
                        page['paragraphs'][paragraph] = page['paragraphs'].get(paragraph, '') + text
                    if note is not None:
                        page['notes'][note] = page['notes'].get(note, '') + text
                    if item is not None:
                        page['listItems'][item] = page['listItems'].get(item, '') + text
                    if script:
                        spans = page['scripts']
                        if spans and spans[-1]['tag'] == script and spans[-1]['end'] == start:
                            spans[-1]['end'] += len(text)
                        else:
                            spans.append({'tag': script, 'start': start, 'end': start + len(text)})

            def walk(element, script=None, heading=None, paragraph=None, note=None, item=None):
                nonlocal current, heading_id, paragraph_id, note_id, item_id
                pagebreak = 'pagebreak' in element.get(EPUB + 'type', '').split()
                if pagebreak:
                    marker_id = element.get('id', '')
                    if not re.fullmatch(r'page-[1-9]\d*', marker_id):
                        raise ValueError('Invalid page boundary')
                    current = int(marker_id[5:])
                    if current in pages:
                        raise ValueError('Duplicate page boundary')
                    markers.append(current)
                    pages[current] = {'text': '', 'images': [], 'scripts': [], 'headings': {}, 'paragraphs': {}, 'listItems': {}, 'notes': {}, 'tables': [],
                                      'noterefs': [], 'anchors': {}}
                if element.tag == HTML + 'img' and current is not None:
                    asset = str(chapter.parent / element.attrib['src'])
                    if asset not in names:
                        raise ValueError('Missing image asset: ' + asset)
                    pages[current]['images'].append(asset)
                    # The converter's supplementary source-page image, which contains every region.
                    if element.get('alt') == f'Original page {current}':
                        pages[current].setdefault('pageReferences', []).append(asset)
                if element.tag == HTML + 'table' and current is not None:
                    import table_cells
                    pages[current]['tables'].append(table_cells.grid_from_table(element))
                # Generic converter captions must not satisfy source-text expectations.
                if element.tag == HTML + 'figcaption':
                    return
                anchor = reference = None
                if element.get('id') and current is not None and not pagebreak:
                    anchor = {'page': current, 'file': str(chapter), 'text': '', 'backlink': None}
                    pages[current]['anchors'][f'{chapter}#{element.get("id")}'] = anchor
                    open_anchors.append(anchor)
                if element.tag == HTML + 'a' and element.get('role') == 'doc-noteref' and current is not None:
                    reference = {'start': len(pages[current]['text']), 'href': element.get('href', ''),
                                 'id': element.get('id'), 'file': str(chapter)}
                    pages[current]['noterefs'].append(reference)
                if element.tag == HTML + 'a' and element.get('role') == 'doc-backlink' and open_anchors:
                    open_anchors[-1]['backlink'] = element.get('href', '')
                if element.tag in (HTML + 'sup', HTML + 'sub'):
                    script = element.tag[len(HTML):]
                if element.tag in HEADINGS:
                    heading_id += 1
                    heading = heading_id
                if element.tag == HTML + 'p':
                    paragraph_id += 1
                    paragraph = paragraph_id
                if element.tag == HTML + 'pre':
                    item_id += 1
                    item = item_id
                # A page-bottom footnote block; its inner paragraph is also an ordinary paragraph.
                if element.get('role') == 'doc-footnote':
                    note_id += 1
                    note = note_id
                append(element.text, script, heading, paragraph, note, item)
                for child in element:
                    walk(child, script, heading, paragraph, note, item)
                    append(child.tail, script, heading, paragraph, note, item)
                if reference is not None:
                    reference['end'] = len(pages[current]['text'])
                if anchor is not None:
                    open_anchors.pop()
                if element.tag in BLOCKS:
                    append(' ')

            walk(tree.find(HTML + 'body'))
    for page in pages.values():
        raw = page['text']
        page['scripts'] = [{'tag': span['tag'], 'text': normalized(raw[span['start']:span['end']]),
                            'before': normalized(raw[max(0, span['start'] - 128):span['start']]),
                            'after': normalized(raw[span['end']:span['end'] + 128])}
                           for span in page['scripts']]
        page['noterefs'] = [{'text': normalized(raw[ref['start']:ref['end']]),
                             'before': normalized(raw[max(0, ref['start'] - 128):ref['start']]),
                             'href': ref['href'], 'id': ref['id'], 'file': ref['file']}
                            for ref in page['noterefs'] if 'end' in ref]
        for anchor in page['anchors'].values():
            anchor['text'] = normalized(anchor['text'])
        page['text'] = normalized(raw)
        page['headings'] = [normalized(text) for text in page['headings'].values()]
        # Paragraph IDs are document-wide, so one <p> crossing a page marker has the same ID on both pages.
        page['paragraphIDs'] = {paragraph: normalized(text) for paragraph, text in page['paragraphs'].items()}
        # A <pre> list item carries its own identity, so a wrapped item continued across a page
        # marker is one block there too (#50).
        page['listItemIDs'] = {item: normalized(text) for item, text in page['listItems'].items()}
        # A <pre> block's own line breaks, which normalization would erase: a coded report's
        # change groups are separate lines of one block (#96).
        page['preformattedLines'] = [[normalized(line) for line in text.split('\n') if normalized(line)]
                                     for text in page['listItems'].values()]
        page['listItems'] = [normalized(text) for text in page['listItems'].values()]
        page['paragraphs'] = [normalized(text) for text in page['paragraphs'].values()]
        page['notes'] = [normalized(text) for text in page['notes'].values()]
    return pages, markers


def resolve_link(file, href):
    """The 'EPUB/file#fragment' key an href reaches from the spine file it appears in."""
    from urllib.parse import urlsplit
    link = urlsplit(href)
    target = str(PurePosixPath(file).parent / link.path) if link.path else file
    return f'{target}#{link.fragment}'


def bounded(expectation, key, default, low, high):
    value = expectation.get(key, default)
    if value is not None and (type(value) not in (int, float) or not low <= value <= high):
        raise ValueError(f'{key} must be between {low} and {high}')
    return value


def load_reference(case, contract, number, expectation, reference_root, kinds, keys):
    """Validate a reference expectation's path, identity and kind; return (PNG bytes, sidecar)."""
    import image_regions  # Imported on use: numpy and Pillow are only needed for image checks.
    if (not isinstance(expectation, dict) or not set(expectation) <= keys | {'reference'}
            or not isinstance(expectation.get('reference'), str)):
        raise ValueError(f'Reference expectation allows only reference and {sorted(keys)}')
    relative = PurePosixPath(expectation['reference'])
    if (relative.suffix != '.png' or relative.parts[:3] != ('corpus', 'references', case['id'])
            or len(relative.parts) != 4 or '..' in relative.parts):
        raise ValueError('Reference must be corpus/references/<case>/<name>.png')
    path = Path(reference_root) / relative
    sidecar = json.loads(path.with_suffix('.json').read_text())
    if sidecar.get('sourceSHA256') != contract['sourceSHA256'] or sidecar.get('page') != number:
        raise ValueError(f'Reference {relative} was rendered from another source or page')
    kind = sidecar.get('kind', 'region')
    if kind not in kinds:
        raise ValueError(f'Reference {relative} is a {kind} reference; this check needs {sorted(kinds)}')
    expected_dpi = image_regions.RENDER_DPI if kind == 'glyph' else image_regions.REFERENCE_DPI
    if (sidecar.get('renderDPI'), sidecar.get('referenceDPI')) != (image_regions.RENDER_DPI, expected_dpi):
        raise ValueError(f'Reference {relative} uses another resolution')
    return path.read_bytes(), sidecar


def reference_image(case, contract, number, expectation, reference_root=ROOT):
    """Validate a region expectation and return its reference PNG bytes and threshold."""
    import image_regions
    data, _ = load_reference(case, contract, number, expectation, reference_root, {'region'},
                             {'minimumCorrelation', 'excludePageReference'})
    if type(expectation.get('excludePageReference', False)) is not bool:
        raise ValueError('excludePageReference must be a boolean')
    return data, bounded(expectation, 'minimumCorrelation', image_regions.DEFAULT_MINIMUM_CORRELATION, 0.5, 1)


def glyph_reference(case, contract, number, expectation, reference_root=ROOT):
    """Validate a glyph expectation; return (PNG bytes, thresholds) for glyph_structure."""
    import glyph_structure
    data, _ = load_reference(case, contract, number, expectation, reference_root, {'glyph'},
                             {'minimumCoverage', 'maximumExtraInk', 'minimumSharpness'})
    thresholds = {
        'minimum_coverage': bounded(expectation, 'minimumCoverage', glyph_structure.DEFAULT_MINIMUM_COVERAGE, 0.2, 1),
        'maximum_extra_ink': bounded(expectation, 'maximumExtraInk', glyph_structure.DEFAULT_MAXIMUM_EXTRA_INK, 0, 0.5),
        'minimum_sharpness': bounded(expectation, 'minimumSharpness', None, 0.2, 1),
    }
    return data, thresholds


def appearance_reference(case, contract, number, expectation, reference_root=ROOT):
    """Validate an appearance expectation; return (PNG bytes, region points, thresholds)."""
    import image_appearance
    data, sidecar = load_reference(case, contract, number, expectation, reference_root, {'region', 'color'},
                                   {'minimumScale', 'minimumContrast', 'minimumColorAgreement'})
    if sidecar.get('kind', 'region') != 'color' and 'minimumColorAgreement' in expectation:
        raise ValueError('minimumColorAgreement needs a color reference')
    region = sidecar.get('regionPoints')
    if (not isinstance(region, list) or len(region) != 4 or any(type(v) not in (int, float) for v in region)
            or not (region[0] < region[2] and region[1] < region[3])):
        raise ValueError('Reference sidecar lacks valid regionPoints')
    thresholds = {
        'minimum_scale': bounded(expectation, 'minimumScale', image_appearance.DEFAULT_MINIMUM_SCALE, 0.5, 2),
        'minimum_contrast': bounded(expectation, 'minimumContrast', image_appearance.DEFAULT_MINIMUM_CONTRAST, 0.1, 1),
        'minimum_color_agreement': bounded(expectation, 'minimumColorAgreement',
                                           image_appearance.DEFAULT_MINIMUM_COLOR_AGREEMENT, 0.5, 1),
    }
    return data, region, thresholds


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
    anchors = {}
    for other in pages.values():
        anchors.update(other.get('anchors', {}))
    for item in expected:
        number = item['page']
        page = pages.get(number, {'text': '', 'images': []})
        if not any(key in item for key in EXPECTATION_KEYS):
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
        # A line the page still carries, but which must not be in the navigation: a margin
        # folio is text, not a heading (#62).
        for phrase in item.get('absentHeadings', []):
            if not isinstance(phrase, str) or not normalized(phrase):
                raise ValueError('Empty or invalid forbidden heading phrase')
            checks += 1
            if any(normalized(phrase) == heading for heading in page.get('headings', [])):
                errors.append(f'Page {number}: unwanted heading {phrase!r}')
        for phrase in item.get('paragraphs', []):
            if not isinstance(phrase, str) or not normalized(phrase):
                raise ValueError('Empty or invalid paragraph phrase')
            checks += 1
            if not any(normalized(phrase) in paragraph for paragraph in page.get('paragraphs', [])):
                errors.append(f'Page {number}: missing paragraph {phrase!r}')
        for phrase in item.get('listItems', []):
            if not isinstance(phrase, str) or not normalized(phrase):
                raise ValueError('Empty or invalid list item phrase')
            checks += 1
            # One <pre> block must hold the whole phrase, so a marker line and the lines wrapped
            # under its hanging indent are one item (#50, #64).
            if not any(normalized(phrase) in block for block in page.get('listItems', [])):
                errors.append(f'Page {number}: missing list item {phrase!r}')
        for lines in item.get('preformattedLines', []):
            if (not isinstance(lines, list) or len(lines) < 2
                    or any(not isinstance(line, str) or not normalized(line) for line in lines)):
                raise ValueError('Preformatted lines require at least two nonempty lines')
            checks += 1
            # One <pre> block holds every named line, each as a whole line of its own and in this
            # order, so the block's lines neither merge nor split into separate elements (#96).
            wanted = [normalized(line) for line in lines]

            def holds(block):
                position = 0
                for line in block:
                    if position < len(wanted) and line == wanted[position]:
                        position += 1
                return position == len(wanted)
            if not any(holds(block) for block in page.get('preformattedLines', [])):
                errors.append(f'Page {number}: no preformatted block with the lines {lines!r}')
        for phrase in item.get('notes', []):
            if not isinstance(phrase, str) or not normalized(phrase):
                raise ValueError('Empty or invalid footnote phrase')
            checks += 1
            # The phrase must sit inside one page-bottom footnote block, not in body prose.
            if not any(normalized(phrase) in note for note in page.get('notes', [])):
                errors.append(f'Page {number}: missing footnote {phrase!r}')
        # Two passages that open separate paragraphs on this page. `paragraphs` matches a phrase
        # inside any paragraph, so it cannot see a section lead-in swallowed by the paragraph
        # above it (#60); this names both passages and requires no paragraph to carry both.
        for separation in item.get('distinctParagraphs', []):
            if (not isinstance(separation, dict) or set(separation) != {'first', 'second'}
                    or any(not isinstance(separation[k], str) or not normalized(separation[k])
                           for k in ('first', 'second'))):
                raise ValueError('Paragraph distinction requires nonempty first and second phrases')
            checks += 1
            first, second = (normalized(separation[k]) for k in ('first', 'second'))
            texts = page.get('paragraphIDs', {}).values()
            if not any(first in text for text in texts):
                errors.append(f'Page {number}: missing paragraph {first!r} for distinction check')
            elif not any(second in text for text in texts):
                errors.append(f'Page {number}: missing paragraph {second!r} for distinction check')
            elif any(first in text and second in text for text in texts):
                errors.append(f'Page {number}: one paragraph carries both {separation!r}')
        for link in item.get('noteLinks', []):
            if (not isinstance(link, dict) or not {'marker', 'before', 'note'} <= set(link)
                    or not set(link) <= {'marker', 'before', 'note', 'notePage'}
                    or any(not isinstance(link[k], str) or not 1 <= len(normalized(link[k])) <= 96 for k in ('marker', 'before', 'note'))
                    or ('notePage' in link and (type(link['notePage']) is not int or link['notePage'] < 1))):
                raise ValueError('Note link requires marker, before and note phrases, optionally notePage')
            checks += 1
            marker, before, phrase = (normalized(link[k]) for k in ('marker', 'before', 'note'))
            # The marker on this page must be a note reference; its href, and the note's return
            # link, are followed through the actual files so a wrong target cannot pass.
            references = [ref for ref in page.get('noterefs', []) if ref['text'] == marker and ref['before'].endswith(before)]
            if not references:
                errors.append(f'Page {number}: missing linked marker {link!r}')
                continue
            target = resolve_link(references[0]['file'], references[0]['href'])
            note = anchors.get(target)
            if note is None:
                errors.append(f'Page {number}: marker links to a missing note {link!r}')
            elif phrase not in note['text']:
                errors.append(f'Page {number}: marker links to the wrong note {link!r}')
            elif 'notePage' in link and note['page'] != link['notePage']:
                errors.append(f'Page {number}: note is on page {note["page"]}, not {link["notePage"]} {link!r}')
            elif not note.get('backlink') or not any(
                    ref['id'] and f'{ref["file"]}#{ref["id"]}' == resolve_link(note['file'], note['backlink'])
                    and resolve_link(ref['file'], ref['href']) == target for ref in page.get('noterefs', [])):
                errors.append(f'Page {number}: note lacks a return link to its reference on this page {link!r}')
        following = pages.get(number + 1, {})
        for continuation in item.get('continuedParagraphs', []):
            if (not isinstance(continuation, dict) or set(continuation) - {'nextPage'} != {'end', 'next'}
                    or any(not isinstance(continuation[k], str) or not normalized(continuation[k]) for k in ('end', 'next'))
                    or ('nextPage' in continuation and (type(continuation['nextPage']) is not int
                                                        or continuation['nextPage'] <= number + 1))):
                raise ValueError('Paragraph continuation requires nonempty end and next phrases'
                                 ' and a later nextPage when one is given')
            checks += 1
            end, after = normalized(continuation['end']), normalized(continuation['next'])
            # `nextPage` names a later page when the pages between hold only figures (#118): they must
            # exist and carry no text at all, so the paragraph cannot skip text of theirs.
            target = continuation.get('nextPage', number + 1)
            later = pages.get(target, {})
            skipped = range(number + 1, target)
            # The same paragraph element must end this page with one phrase and continue the next page with the other.
            if (any(skipped_page not in pages or normalized(pages[skipped_page]['text']) for skipped_page in skipped)
                    or not any(end in text and paragraph in later.get('paragraphIDs', {})
                               and after in later['paragraphIDs'][paragraph]
                               for paragraph, text in page.get('paragraphIDs', {}).items())):
                errors.append(f'Page {number}: paragraph does not continue onto page {target} {continuation!r}')
        for continuation in item.get('continuedListItems', []):
            if (not isinstance(continuation, dict) or set(continuation) != {'end', 'next'}
                    or any(not isinstance(continuation[k], str) or not normalized(continuation[k]) for k in ('end', 'next'))):
                raise ValueError('List item continuation requires nonempty end and next phrases')
            checks += 1
            end, after = normalized(continuation['end']), normalized(continuation['next'])
            # One <pre> list item must end this page with the first phrase and carry the second
            # on the next, so a marker's wrapped text is not split at the page boundary (#50).
            if not any(end in text and block in following.get('listItemIDs', {})
                       and after in following['listItemIDs'][block]
                       for block, text in page.get('listItemIDs', {}).items()):
                errors.append(f'Page {number}: list item does not continue onto page {number + 1} {continuation!r}')
        for separation in item.get('separateParagraphs', []):
            if (not isinstance(separation, dict) or set(separation) != {'end', 'next'}
                    or any(not isinstance(separation[k], str) or not normalized(separation[k]) for k in ('end', 'next'))):
                raise ValueError('Paragraph separation requires nonempty end and next phrases')
            checks += 1
            end, after = normalized(separation['end']), normalized(separation['next'])
            # Both phrases must exist as paragraph text, and no paragraph element may carry the first
            # phrase on this page and the second on the next (a folio must not absorb continuation text).
            if not any(end in text for text in page.get('paragraphIDs', {}).values()):
                errors.append(f'Page {number}: missing paragraph {end!r} for separation check')
            elif not any(after in text for text in following.get('paragraphIDs', {}).values()):
                errors.append(f'Page {number + 1}: missing paragraph {after!r} for separation check')
            elif any(end in text and paragraph in following.get('paragraphIDs', {})
                     and after in following['paragraphIDs'][paragraph]
                     for paragraph, text in page.get('paragraphIDs', {}).items()):
                errors.append(f'Page {number}: paragraph wrongly continues onto page {number + 1} {separation!r}')
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
        # A script that must not be written: its tag and text, and the context around it where given
        # (a bullet raised as `<sup>`, a period lowered as `<sub>`, #144).
        for script in item.get('absentScripts', []):
            if (script.get('tag') not in ('sup', 'sub') or not isinstance(script.get('text'), str)
                    or not 1 <= len(normalized(script['text'])) <= 96
                    or any(key not in ('tag', 'text', 'before', 'after') for key in script)
                    or any(not isinstance(script[k], str) or not 1 <= len(normalized(script[k])) <= 96
                           for k in ('before', 'after') if k in script)):
                raise ValueError('Absent script check requires sup/sub, nonempty bounded text and optional context')
            checks += 1
            if any(span['tag'] == script['tag'] and span['text'] == normalized(script['text'])
                   and span['before'].endswith(normalized(script.get('before', '')))
                   and span['after'].startswith(normalized(script.get('after', '')))
                   for span in page.get('scripts', [])):
                errors.append(f'Page {number}: unexpected script {script!r}')
        for expectation in item.get('imageRegions', []):
            reference, minimum = reference_image(case, contract, number, expectation, reference_root)
            checks += 1
            if image_data is None:
                errors.append(f'Page {number}: converted images unavailable for {expectation["reference"]}')
                continue
            import image_regions
            # A region crop must show the reference itself: the source-page image beside reflowed
            # text contains every region, so it satisfies nothing when excluded (#37).
            excluded = page.get('pageReferences', []) if expectation.get('excludePageReference') else []
            score = image_regions.region_score(reference, [image_data(asset) for asset in page['images']
                                                           if asset not in excluded])
            if score < minimum:
                errors.append(f'Page {number}: no image shows {expectation["reference"]} '
                              f'(best correlation {score:.3f} < {minimum})')
        for expectation in item.get('glyphRegions', []):
            reference, thresholds = glyph_reference(case, contract, number, expectation, reference_root)
            checks += 1
            if image_data is None:
                errors.append(f'Page {number}: converted images unavailable for {expectation["reference"]}')
                continue
            import glyph_structure
            passed, metrics = glyph_structure.structure_score(reference, [image_data(asset) for asset in page['images']], **thresholds)
            if not passed:
                errors.append(f'Page {number}: no image shows every stroke of {expectation["reference"]} '
                              f'(coverage {metrics["coverage"]:.3f}, extra ink {metrics["extraInk"]:.3f}, '
                              f'sharpness {metrics["sharpness"]:.3f}, weakest {metrics.get("weakestComponent")})')
        for expectation in item.get('imageAppearance', []):
            reference, region, thresholds = appearance_reference(case, contract, number, expectation, reference_root)
            checks += 1
            if image_data is None:
                errors.append(f'Page {number}: converted images unavailable for {expectation["reference"]}')
                continue
            import image_appearance
            passed, metrics = image_appearance.appearance_score(reference, region, [image_data(asset) for asset in page['images']], **thresholds)
            if not passed:
                errors.append(f'Page {number}: no image keeps the appearance of {expectation["reference"]} '
                              f'(scale {metrics["scale"]:.3f}, contrast {metrics["contrast"]:.3f}, '
                              f'color agreement {metrics.get("colorAgreement", "n/a")})')
        for expectation in item.get('tableCells', []):
            import table_cells
            table_cells.validate(expectation)
            checks += 1
            for error in table_cells.check_page(expectation, page.get('tables', [])):
                errors.append(f'Page {number}: table cells: {error}')
        if 'minimumImages' in item:
            minimum = item['minimumImages']
            if type(minimum) is not int or minimum < 1:
                raise ValueError('Image minimum must be positive')
            checks += 1
            if len(page['images']) < minimum:
                errors.append(f'Page {number}: missing preserved images')
        if 'maximumImages' in item:
            # Decoration that must not become an image (a running-header rule, #66).
            maximum = item['maximumImages']
            if type(maximum) is not int or maximum < 0:
                raise ValueError('Image maximum must be a non-negative integer')
            checks += 1
            if len(page['images']) > maximum:
                errors.append(f'Page {number}: {len(page["images"])} images, at most {maximum} expected')
        if 'pageReference' in item:
            # Whether the converter's `Original page N` source-page image accompanies the page:
            # true where visible content needs it, false where nothing on the page does (#151).
            wanted = item['pageReference']
            if type(wanted) is not bool:
                raise ValueError('Page reference expectation must be true or false')
            checks += 1
            if bool(page.get('pageReferences')) != wanted:
                errors.append(f'Page {number}: ' + ('missing' if wanted else 'unexpected') + ' source-page reference image')
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
    if checks != sum(sum(count_page_checks(item).values()) for item in expected):
        raise ValueError('CHECK_TYPES no longer matches the checks assess counts')
    return {'case': case['id'], 'passed': not errors, 'reviewPages': numbers,
            'contentChecks': checks, 'errors': errors,
            'scope': 'Reviewed text/order/script-context/image-presence, source-region, glyph-structure, appearance and table-cell checks; not full-book fidelity qualification.'}


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
