#!/usr/bin/env python3
"""Strict capability-compatible comparison of two complete corpus evaluations.

Refuse missing/mismatched provenance. Report parsed page, OCR/report and encoded image
differences; an unchanged EPUB ZIP hash is not required (identifiers/timestamps vary).
This detects drift, not correctness. Existing content/EPUB/resource gates still apply.
"""
import argparse
import hashlib
import json
from pathlib import Path
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


def compare(baseline, candidate):
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
    paths = [directory / (receipt['case']['id'] + '.epub')
             for directory, receipt in [(baseline, left), (candidate, right)]]
    lp, lm = read_pages(paths[0])
    rp, rm = read_pages(paths[1])
    li, ri = (image_hashes(path) for path in paths)
    changed_pages = sorted(page for page in lp.keys() | rp.keys() if lp.get(page) != rp.get(page))
    changed_images = sorted(name for name in li.keys() | ri.keys() if li.get(name) != ri.get(name))
    reports = [{k: v for k, v in receipt['conversionReport'].items() if k != 'outputURL'}
               for receipt in (left, right)]
    report_fields = sorted(k for k in reports[0].keys() | reports[1].keys()
                           if k not in reports[0] or k not in reports[1] or reports[0][k] != reports[1][k])
    result.update({
        'case': left['case']['id'],
        'executionContexts': {'baseline': left.get('executionContext'), 'candidate': right.get('executionContext')},
        'baselineConverterSHA256': left['converterSHA256'],
        'candidateConverterSHA256': right['converterSHA256'],
        'changedPages': changed_pages, 'changedImages': changed_images,
        'pageMarkersEqual': lm == rm, 'changedReportFields': report_fields,
        'scope': 'Exact normalized page records, page markers, encoded image bytes and conversion report; not all EPUB semantics or a fidelity qualification.',
        'passed': not (changed_pages or changed_images or report_fields) and lm == rm,
    })
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--candidate', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    try:
        result = compare(args.baseline, args.candidate)
    except Exception as error:
        result = {'passed': False, 'inspectionError': str(error)}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
