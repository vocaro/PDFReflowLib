#!/usr/bin/env python3
"""Strict capability-compatible comparison of two complete corpus evaluations.

Refuse missing/mismatched provenance, including two different converter binaries unless
--allow-different-converters states that a before/after build comparison is intended (a
shared build path rebuilt between runs is the likely origin of #68's report). Report parsed
page, OCR/report and encoded image differences; an unchanged EPUB ZIP hash is not required
(identifiers/timestamps vary). For repeat runs of one binary see check_reproducibility.py.
This detects drift, not correctness. Existing content/EPUB/resource gates still apply.

Vision OCR text is not a function of the binary alone (#94): each compile of Vision's models can
transcribe differently, and a process inherits the programs cached under its name. Changed pages
that are OCR pages in both runs are listed as changedOCRPages, with an ocrCaveat unless both
receipts record identical compiled programs; each run's cache mode, name and fingerprint are
reported. The caveat does not change `passed`. Wording differences do not remove text, so OCR pages
where one run has under 80% of the other's words (and at least 25 fewer) are listed under
ocrTextVolume with an ocrTextLoss note naming the run with less text (#116).

Generated identifiers are not content (#92): book-wide paragraph and list-item ordinals,
element ids, spine file names and image asset names all shift when an earlier page gains or
loses a block, a spine boundary moves or an image is added. Each page is compared with those
normalized (ordinals become cross-page continuity, ids lose their numbers, links resolve to
their target's page, id and text, images are named by their bytes), so only pages whose text,
blocks, markup, images, link targets or warnings changed are reported. Pages that differ only
in generated identifiers, and image assets renamed without a byte change, are summarized.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import re

from check_corpus_content import read_pages, resolve_link
from check_reproducibility import Package, ocr_pages
from conversion_provenance import digest, is_digest, probe_errors

NUMBER = re.compile(r'\d+')
SCHEME = re.compile(r'^[A-Za-z][A-Za-z0-9+.-]*:')
PAGE_ID = re.compile(r'page-[1-9]\d*')
TAG = re.compile(r'<[^<>]+>')
GENERATED_ATTRIBUTE = re.compile(r'(?<=\s)(id|href|src)="([^"]*)"')


def vision_caches(left, right, changed_pages):
    """Flag OCR-page changes that Vision model compilation alone can explain (#94).

    Each compile of Vision's document models can produce a program that transcribes differently,
    and a process inherits its name's cached programs. Changed pages that are OCR pages in both
    runs are listed; the caveat is attached unless both receipts record identical compiled
    programs. Identical programs make such a change genuine; differing programs make it
    unattributable here (output-equivalent compiles also differ in bytes).
    """
    caches = {}
    for label, receipt in [('baseline', left), ('candidate', right)]:
        cache = receipt.get('visionModelCache') if isinstance(receipt.get('visionModelCache'), dict) else {}
        after = cache.get('after') if isinstance(cache.get('after'), dict) else {}
        caches[label] = {'mode': cache.get('mode'), 'executableName': after.get('executableName'),
                         'programsSHA256': after.get('programsSHA256')}
    programs = [caches[label]['programsSHA256'] for label in caches]
    same = None if not all(is_digest(p) for p in programs) else programs[0] == programs[1]
    both = ocr_pages(left['conversionReport']) & ocr_pages(right['conversionReport'])
    changed = [page for page in changed_pages if page in both]
    result = {'visionModelCaches': caches, 'sameVisionPrograms': same, 'changedOCRPages': changed}
    if changed and same is not True:
        result['ocrCaveat'] = (f'OCR pages {changed} changed and the two runs\' compiled Vision programs '
                               + ('differ' if same is False else 'were not recorded')
                               + '; Vision model compilation alone can change OCR text (#94), so these pages '
                                 'do not show a converter change by themselves')
    return result


OCR_LOSS_SHARE = 0.8
OCR_LOSS_WORDS = 25


def ocr_text_volume(left, right, left_report, right_report):
    """Words on pages recognized in both runs, and pages where one run has far fewer (#116).

    A compile of Vision's models can drop whole paragraphs, not only reword them, and the
    converter's own coverage check cannot catch every loss. Wording differences between compiles
    change few words, so a page is listed when one run has less than 80% of the other's words and
    at least 25 fewer. The run with less text on a listed page is the one to distrust.
    """
    both = sorted(ocr_pages(left_report) & ocr_pages(right_report))
    words = {}
    for label, run in [('baseline', left), ('candidate', right)]:
        words[label] = {page: len((run.pages.get(page) or {}).get('text', '').split()) for page in both}
    fewer = {'baseline': [], 'candidate': []}
    for page in both:
        a, b = words['baseline'][page], words['candidate'][page]
        low, high = min(a, b), max(a, b)
        if high - low >= OCR_LOSS_WORDS and low < high * OCR_LOSS_SHARE:
            fewer['baseline' if a < b else 'candidate'].append(page)
    result = {'ocrTextVolume': {'pages': len(both),
                                'baselineWords': sum(words['baseline'].values()),
                                'candidateWords': sum(words['candidate'].values()),
                                'pagesWithFewerWords': fewer}}
    if fewer['baseline'] or fewer['candidate']:
        result['ocrTextLoss'] = '; '.join(
            f'the {label} has under {round(OCR_LOSS_SHARE * 100)}% of the other run\'s words on OCR pages {pages}'
            for label, pages in fewer.items() if pages) + (
            '. Recognition that drops lines or paragraphs is a text loss, not a wording difference; '
            'check that run\'s compiled Vision programs and page images (#116)')
    return result


def compatible_receipts(left, right, allow_different_converters=False):
    errors = []
    if not isinstance(left, dict) or not isinstance(right, dict):
        return ['evaluation receipt must be an object']
    if not isinstance(left.get('case'), dict) or not isinstance(right.get('case'), dict):
        return ['source receipt missing or malformed']
    for name in ('system', 'systemBuild', 'machine', 'options'):
        if not left.get(name) or not right.get(name):
            errors.append(f'missing {name}; recapture both runs with capability evidence')
        elif left[name] != right[name]:
            errors.append(f'{name} differs')
    for name in ('id', 'sha256', 'pages'):
        if not left.get('case', {}).get(name) or not right.get('case', {}).get(name):
            errors.append(f'missing source {name}')
        elif left['case'][name] != right['case'][name]:
            errors.append(f'source {name} differs')
    for label, receipt in [('baseline', left), ('candidate', right)]:
        if receipt.get('provenanceSchemaVersion') != 1:
            errors.append(f'{label} unsupported or missing provenance schema')
        if receipt.get('runPassed') is not True:
            errors.append(f'{label} evaluation did not pass')
        for field in ('converterSHA256', 'outputSHA256'):
            if not is_digest(receipt.get(field)):
                errors.append(f'{label} {field} missing or invalid')
        if not isinstance(receipt.get('conversionReport'), dict):
            errors.append(f'{label} conversion report missing')
        errors.extend(f'{label} {error}' for error in probe_errors(receipt))
    if (not allow_different_converters and is_digest(left.get('converterSHA256'))
            and is_digest(right.get('converterSHA256')) and left['converterSHA256'] != right['converterSHA256']):
        errors.append(f'converterSHA256 differs (baseline {left["converterSHA256"][:12]}..., candidate '
                      f'{right["converterSHA256"][:12]}...): these runs used two different binaries; '
                      'pass --allow-different-converters to compare two builds deliberately')
    for name in ('probeSHA256', 'packedPixelSHA256', 'metalDevice', 'colorSpaceName',
                 'colorSpaceICC_SHA256', 'width', 'height', 'bitsPerPixel', 'rasterDPI', 'system', 'ocr'):
        lp, rp = left.get('environmentProbe'), right.get('environmentProbe')
        lp = lp if isinstance(lp, dict) else {}
        rp = rp if isinstance(rp, dict) else {}
        if not lp.get(name) or not rp.get(name):
            errors.append(f'missing capability probe {name}')
        elif lp[name] != rp[name]:
            errors.append(f'capability probe {name} differs')
    return errors


def artifact_errors(directory, receipt):
    """Bind inspected artifacts to the successful evaluation and probe invocation."""
    errors = []
    case_id = receipt['case']['id']
    if not isinstance(case_id, str) or not case_id or Path(case_id).name != case_id:
        return ['invalid case identifier']
    for filename, expected in (
            (case_id + '.epub', receipt['outputSHA256']),
            ('environment-probe.json', receipt['environmentProbeCapture']['resultSHA256'])):
        if digest(directory / filename) != expected:
            errors.append(f'{filename} identity differs from receipt')
    if json.loads((directory / 'environment-probe.json').read_text()) != receipt['environmentProbe']:
        errors.append('capability probe differs from receipt')
    report = json.loads((directory / 'conversion-report.json').read_text())
    report = {k: v for k, v in report.items() if k != 'outputURL'}
    if report != {k: v for k, v in receipt['conversionReport'].items() if k != 'outputURL'}:
        errors.append('conversion report differs from receipt')
    return errors


def mask(identifier):
    """A generated identifier without its numbers (`heading-8-2`, `note-c3-4` -> `heading-#-#`, `note-c#-#`)."""
    return NUMBER.sub('#', identifier)


def link_target(anchors, file, href):
    """What an href reaches, by content: the target's page, masked id and text."""
    if href is None:
        return None
    if SCHEME.match(href):
        return {'external': href}
    key = resolve_link(file, href)
    fragment = key.partition('#')[2]
    anchor = anchors.get(key)
    if anchor is None:
        return {'unresolved': mask(fragment)}
    return {'page': anchor['page'], 'id': mask(fragment), 'text': anchor['text']}


def continuity(pages, order, field):
    """Replace book-wide block ordinals with whether each block continues across a page marker."""
    result = {}
    for index, page in enumerate(order):
        before = pages[order[index - 1]][field] if index else {}
        after = pages[order[index + 1]][field] if index + 1 < len(order) else {}
        result[page] = [[text, key in before, key in after] for key, text in pages[page][field].items()]
    return result


def normalized_markup(markup, package):
    """Page markup with generated ids masked, images named by bytes and internal links by target page."""
    def attribute(match):
        name, value = match.group(1), match.group(2)
        if name == 'id':
            return f'id="{mask(value)}"'
        if name == 'src':
            # Spine documents sit beside the images directory; Package keys entries by full name.
            asset = str(PurePosixPath('EPUB') / value)
            return (f'src="sha256:{package.hashes[asset]}"' if asset in package.hashes
                    else f'src="missing:{mask(value)}"')
        if value.startswith('#'):  # Package.local_links has already dropped same-book file names.
            fragment = value[1:]
            page = int(fragment[5:]) if PAGE_ID.fullmatch(fragment) else package.id_pages.get(fragment)
            return f'href="#{mask(fragment)}@{page}"'
        return match.group(0)
    return TAG.sub(lambda tag: GENERATED_ATTRIBUTE.sub(attribute, tag.group(0)), markup)


def natural(name):
    return [int(part) if part.isdigit() else part for part in re.split(r'(\d+)', name)]


class Evaluation:
    """One EPUB's pages as parsed (raw) and with generated identifiers normalized."""

    def __init__(self, epub, report):
        self.raw, self.markers = read_pages(epub)  # Bounded ZIP admission checks come first.
        self.package = Package(epub)
        anchors = {key: anchor for page in self.raw.values() for key, anchor in page['anchors'].items()}
        paragraphs = continuity(self.raw, self.markers, 'paragraphIDs')
        items = continuity(self.raw, self.markers, 'listItemIDs')
        self.warnings = {}
        for warning in report.get('warnings') or []:
            if isinstance(warning, dict) and type(warning.get('page')) is int:
                self.warnings.setdefault(warning['page'], []).append(
                    {k: v for k, v in warning.items() if k != 'page'})
        self.pages = {}
        for number in self.raw.keys() | self.package.segments.keys() | self.warnings.keys():
            page = dict(self.raw.get(number) or {})
            if page:
                page['paragraphIDs'] = paragraphs[number]
                page['listItemIDs'] = items[number]
                page['images'] = [self.package.hashes.get(name) for name in page['images']]
                if 'pageReferences' in page:
                    page['pageReferences'] = [self.package.hashes.get(name) for name in page['pageReferences']]
                page['anchors'] = [{'id': mask(key.partition('#')[2]), 'text': anchor['text'],
                                    'backlink': link_target(anchors, anchor['file'], anchor['backlink'])}
                                   for key, anchor in page['anchors'].items()]
                page['noterefs'] = [{'text': ref['text'], 'before': ref['before'], 'id': mask(ref['id'] or ''),
                                     'target': link_target(anchors, ref['file'], ref['href'])}
                                    for ref in page['noterefs']]
            page['markup'] = normalized_markup(self.package.segments.get(number, ''), self.package)
            page['warnings'] = self.warnings.get(number, [])
            self.pages[number] = page

    def raw_page(self, number):
        return dict(self.raw.get(number) or {}, markup=self.package.segments.get(number, ''),
                    warnings=self.warnings.get(number, []))

    def images(self):
        """(sha256, name) per image asset: first-reference reading order, then unreferenced by name."""
        referenced = list(dict.fromkeys(name for number in self.markers for name in self.raw[number]['images']))
        rest = sorted((name for name in self.package.names if name.startswith('EPUB/images/')
                       and not name.endswith('/') and name not in referenced), key=natural)
        return [(self.package.hashes[name], name) for name in referenced + rest]

    def navigation(self):
        """(skeleton, raw entries, entries with masked targets); targets keep their resolved page."""
        skeleton, entries = self.package.navigation(set())
        return skeleton, entries, [dict(entry, target=mask(entry['target'])) for entry in entries]


def compare_images(left, right):
    """Match assets by bytes: unmatched assets are changes; matched assets with other names are renames."""
    by_hash = ({}, {})
    for side, evaluation in enumerate((left, right)):
        for sha, name in evaluation.images():
            by_hash[side].setdefault(sha, []).append(name)
    changed, renames = set(), []
    for sha in by_hash[0].keys() | by_hash[1].keys():
        before, after = by_hash[0].get(sha, []), by_hash[1].get(sha, [])
        renames += [[a, b] for a, b in zip(before, after) if a != b]
        shared = min(len(before), len(after))
        changed.update(before[shared:] + after[shared:])
    return sorted(changed, key=natural), sorted(renames, key=lambda pair: natural(pair[0]))


def compare_pages(left, right):
    """(changed pages, their differing normalized fields, id-only shifted pages with raw fields)."""
    changed, fields, shifts = [], {}, {}
    for number in sorted(left.pages.keys() | right.pages.keys()):
        a, b = left.pages.get(number, {}), right.pages.get(number, {})
        if a != b:
            changed.append(number)
            fields[str(number)] = sorted(k for k in a.keys() | b.keys() if a.get(k) != b.get(k))
            continue
        raw = left.raw_page(number), right.raw_page(number)
        shifted = sorted(k for k in raw[0].keys() | raw[1].keys() if raw[0].get(k) != raw[1].get(k))
        if shifted:
            shifts[number] = shifted
    return changed, fields, shifts


def compare(baseline, candidate, allow_different_converters=False, detail=False):
    left = json.loads((baseline / 'result.json').read_text())
    right = json.loads((candidate / 'result.json').read_text())
    errors = compatible_receipts(left, right, allow_different_converters)
    result = {'passed': False, 'provenanceErrors': errors}
    if errors:
        return result
    for label, directory, receipt in [('baseline', baseline, left), ('candidate', candidate, right)]:
        try:
            errors.extend(f'{label} {error}' for error in artifact_errors(directory, receipt))
        except (OSError, ValueError, TypeError, KeyError) as error:
            errors.append(f'{label} artifact verification failed: {error}')
    if errors:
        return result
    runs = [Evaluation(directory / (receipt['case']['id'] + '.epub'), receipt['conversionReport'])
            for directory, receipt in [(baseline, left), (candidate, right)]]
    changed_pages, changed_fields, shifts = compare_pages(*runs)
    changed_images, renames = compare_images(*runs)
    (left_skeleton, left_raw_nav, left_nav), (right_skeleton, right_raw_nav, right_nav) = (
        run.navigation() for run in runs)
    navigation_changed = left_skeleton != right_skeleton or left_nav != right_nav
    navigation_pages = sorted({entry['page'] for entry in left_nav + right_nav
                               if (entry in left_nav) != (entry in right_nav)}, key=str)
    reports = [{k: v for k, v in receipt['conversionReport'].items() if k != 'outputURL'}
               for receipt in (left, right)]
    report_fields = sorted(k for k in reports[0].keys() | reports[1].keys()
                           if k not in reports[0] or k not in reports[1] or reports[0][k] != reports[1][k])
    field_counts = {}
    for shifted in shifts.values():
        for field in shifted:
            field_counts[field] = field_counts.get(field, 0) + 1
    id_shifts = {'pageCount': len(shifts), 'fields': dict(sorted(field_counts.items())),
                 'navigationEntries': (sum(a != b for a, b in zip(left_raw_nav, right_raw_nav))
                                       if not navigation_changed else None)}
    image_renames = {'count': len(renames)}
    if detail:
        id_shifts['pages'] = {str(page): fields for page, fields in shifts.items()}
        image_renames['pairs'] = renames
    markers_equal = runs[0].markers == runs[1].markers
    result.update({
        'case': left['case']['id'],
        'executionContexts': {'baseline': left.get('executionContext'), 'candidate': right.get('executionContext')},
        'baselineConverterSHA256': left['converterSHA256'],
        'candidateConverterSHA256': right['converterSHA256'],
        'sameConverter': left['converterSHA256'] == right['converterSHA256'],
        **vision_caches(left, right, changed_pages),
        **ocr_text_volume(*runs, left['conversionReport'], right['conversionReport']),
        'changedPages': changed_pages, 'changedPageFields': changed_fields,
        'changedImages': changed_images,
        'navigationChanged': navigation_changed, 'changedNavigationPages': navigation_pages,
        'pageMarkersEqual': markers_equal, 'changedReportFields': report_fields,
        'idOnlyShifts': id_shifts, 'imageRenames': image_renames,
        'scope': ('Per page: text, block records, element markup, image bytes, link targets and warnings, with '
                  'generated identifiers (block ordinals, element ids, spine file names, image asset names) '
                  'normalized; page markers; image assets by bytes; navigation entries; conversion report. '
                  'Not CSS, package metadata, decoded image equivalence or a fidelity qualification.'),
        'passed': not (changed_pages or changed_images or report_fields or navigation_changed) and markers_equal,
    })
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--allow-different-converters', action='store_true',
                        help='compare evaluations made by two different converter binaries (before/after a change)')
    parser.add_argument('--detail', action='store_true',
                        help='list each id-only shifted page with its raw differing fields, and each image rename')
    args = parser.parse_args()
    try:
        result = compare(args.baseline, args.candidate, args.allow_different_converters, args.detail)
    except Exception as error:
        result = {'passed': False, 'inspectionError': str(error)}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
