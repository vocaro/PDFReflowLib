#!/usr/bin/env python3
"""Strict capability-compatible comparison of two complete corpus evaluations.

Refuse missing/mismatched provenance. Report parsed page, OCR/report and encoded image
differences; an unchanged EPUB ZIP hash is not required (identifiers/timestamps vary).
This detects drift, not correctness. Existing content/EPUB/resource gates still apply.

Generated identifiers are not content (#92). Two of them leak into a parsed page record and
shift whenever an earlier page gains or loses something: `read_pages` keys each page's
paragraphs by a book-wide ordinal, and the writer names image assets `images/image-N.ext` in
book-wide first-use order. Comparing those verbatim made every page after a one-paragraph edit
differ, so the tool reported 15 changed pages for a change to one and agents wrote per-change
scripts to find the real difference. Each page is therefore compared with both normalized:
paragraph ordinals become `paragraphSpans`, which says only whether each paragraph continues
onto the previous or next page, so a split or join at a page break is still a change; and a
page's images are compared by their SHA-256, so a moved, swapped or re-encoded image still
changes its page while a pure renumbering does not. Image assets are matched book-wide by
bytes: unmatched bytes are `changedImages`, and byte-identical assets that only changed name
are summarized in `imageRenames`. Pages that agree once normalized but differ in raw
identifiers are summarized in `idOnlyShifts`; both summaries are informational and neither
fails a run. `--detail` lists them.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

from check_corpus_content import read_pages
from conversion_provenance import is_digest, probe_errors
from pdfreflow_tools.corpus import digest


def compatible_receipts(left, right):
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


def image_hashes(epub):
    # read_pages performs the existing bounded ZIP admission checks first.
    with zipfile.ZipFile(epub) as archive:
        return {name: hashlib.sha256(archive.read(name)).hexdigest()
                for name in archive.namelist() if name.startswith('EPUB/images/') and not name.endswith('/')}


def natural(name):
    """Sort key that orders `image-9.png` before `image-10.png`."""
    return [int(part) if part.isdigit() else part for part in re.split(r'(\d+)', name)]


def paragraph_spans(pages, order):
    """Book-wide paragraph ordinals as cross-page continuity, per page and in the page's own order.

    A paragraph that straddles a page marker carries one ordinal on both pages, so asking
    whether this page's ordinal also appears on the previous or next one says what the ordinal
    was worth — that the block is split across the break — without the number, which shifts for
    every later page as soon as any earlier page gains or loses a paragraph.
    """
    spans = {}
    for index, page in enumerate(order):
        before = pages[order[index - 1]]['paragraphIDs'] if index else {}
        after = pages[order[index + 1]]['paragraphIDs'] if index + 1 < len(order) else {}
        spans[page] = [[key in before, key in after] for key in pages[page]['paragraphIDs']]
    return spans


class Evaluation:
    """One EPUB's pages as parsed, and with its generated identifiers normalized."""

    def __init__(self, epub):
        self.raw, self.markers = read_pages(epub)
        self.assets = image_hashes(epub)
        spans = paragraph_spans(self.raw, self.markers)
        self.pages = {}
        for number, page in self.raw.items():
            record = {key: value for key, value in page.items() if key != 'paragraphIDs'}
            record['paragraphSpans'] = spans[number]
            # A page's images by content, so book-wide renumbering is not a per-page difference.
            record['images'] = [self.assets.get(name) for name in page['images']]
            self.pages[number] = record

    def images(self):
        """(sha256, name) per image asset: first-reference reading order, then unreferenced by name."""
        referenced = list(dict.fromkeys(name for number in self.markers for name in self.raw[number]['images']))
        rest = sorted((name for name in self.assets if name not in referenced), key=natural)
        return [(self.assets[name], name) for name in referenced + rest]


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
    """(changed pages, their differing normalized fields, pages that differ only in raw identifiers)."""
    changed, fields, shifts = [], {}, {}
    for number in sorted(left.pages.keys() | right.pages.keys()):
        a, b = left.pages.get(number, {}), right.pages.get(number, {})
        if a != b:
            changed.append(number)
            fields[str(number)] = sorted(key for key in a.keys() | b.keys() if a.get(key) != b.get(key))
            continue
        raw = left.raw.get(number, {}), right.raw.get(number, {})
        shifted = sorted(key for key in raw[0].keys() | raw[1].keys() if raw[0].get(key) != raw[1].get(key))
        if shifted:
            shifts[number] = shifted
    return changed, fields, shifts


def compare(baseline, candidate, detail=False):
    left = json.loads((baseline / 'result.json').read_text())
    right = json.loads((candidate / 'result.json').read_text())
    errors = compatible_receipts(left, right)
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
    runs = [Evaluation(directory / (receipt['case']['id'] + '.epub'))
            for directory, receipt in [(baseline, left), (candidate, right)]]
    changed_pages, changed_fields, shifts = compare_pages(*runs)
    changed_images, renames = compare_images(*runs)
    markers_equal = runs[0].markers == runs[1].markers
    reports = [{k: v for k, v in receipt['conversionReport'].items() if k != 'outputURL'}
               for receipt in (left, right)]
    report_fields = sorted(k for k in reports[0].keys() | reports[1].keys()
                           if k not in reports[0] or k not in reports[1] or reports[0][k] != reports[1][k])
    field_counts = {}
    for shifted in shifts.values():
        for field in shifted:
            field_counts[field] = field_counts.get(field, 0) + 1
    id_shifts = {'pageCount': len(shifts), 'fields': dict(sorted(field_counts.items()))}
    image_renames = {'count': len(renames)}
    if detail:
        id_shifts['pages'] = {str(page): fields for page, fields in sorted(shifts.items())}
        image_renames['pairs'] = renames
    result.update({
        'case': left['case']['id'],
        'executionContexts': {'baseline': left.get('executionContext'), 'candidate': right.get('executionContext')},
        'baselineConverterSHA256': left['converterSHA256'],
        'candidateConverterSHA256': right['converterSHA256'],
        'changedPages': changed_pages, 'changedPageFields': changed_fields,
        'changedImages': changed_images,
        'pageMarkersEqual': markers_equal, 'changedReportFields': report_fields,
        'idOnlyShifts': id_shifts, 'imageRenames': image_renames,
        'scope': ('Per page: text, paragraphs and their page-break continuity, headings, scripted spans and '
                  'image bytes, with generated identifiers (paragraph ordinals, image asset names) normalized; '
                  'page markers; image assets by bytes; conversion report. Not CSS, package metadata, decoded '
                  'image equivalence or a fidelity qualification.'),
        'passed': not (changed_pages or changed_images or report_fields) and markers_equal,
    })
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--detail', action='store_true',
                        help='list each page that shifted only in generated ids, and each image rename')
    args = parser.parse_args()
    try:
        result = compare(args.baseline, args.candidate, args.detail)
    except Exception as error:
        result = {'passed': False, 'inspectionError': str(error)}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
