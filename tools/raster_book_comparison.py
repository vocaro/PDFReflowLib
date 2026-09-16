#!/usr/bin/env python3
"""Summarize complete-book evaluations that differ only in raster options.

`compare_conversion_runs.py` deliberately refuses receipts whose converter options differ, so
runs at different resolutions cannot use the strict comparator. This tool reads each
evaluation's receipt, conversion report and EPUB, and reports per run: gate results, peak RSS and
sampled footprint, elapsed time, output and image bytes, reflowed/recognized page counts,
warnings by code, OCR pages, and (with the case's reviewed content contract) content errors split
into reference-image checks, which assume the default 180 DPI raster, and all other checks. Against
the first run it lists the pages whose normalized text or image count changed and whether the
page markers agree. It detects drift between resolutions; it does not judge which output is
correct and is not a fidelity qualification.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import zipfile

from check_corpus_content import ROOT, check_evaluation, read_pages

REFERENCE_MARKER = 'references/'


def classify_errors(errors):
    """Split content-contract errors into reference-image checks and everything else."""
    reference = [error for error in errors if REFERENCE_MARKER in error]
    return {'referenceImageErrors': reference,
            'otherErrors': [error for error in errors if REFERENCE_MARKER not in error]}


def run_summary(directory, case=None, contract=None):
    """(summary, pages, markers) for one evaluation directory."""
    directory = Path(directory)
    receipt = json.loads((directory / 'result.json').read_text())
    report = json.loads((directory / 'conversion-report.json').read_text())
    epub = directory / (receipt['case']['id'] + '.epub')
    pages, markers = read_pages(epub)
    with zipfile.ZipFile(epub) as archive:
        images = {info.filename: info.file_size for info in archive.infolist()
                  if info.filename.startswith('EPUB/images/') and not info.filename.endswith('/')}
    warnings = report.get('warnings', [])
    summary = {
        'directory': str(directory), 'options': receipt.get('options'), 'runPassed': receipt.get('runPassed'),
        'converterSHA256': receipt.get('converterSHA256'), 'conversionExitCode': receipt.get('conversionExitCode'),
        'memoryGate': receipt.get('memoryGate'), 'epubcheckExitCode': receipt.get('epubcheckExitCode'),
        'structuralCheck': receipt.get('structuralCheck'), 'progressPassed': receipt.get('progressCheck', {}).get('passed'),
        'capabilityPassed': receipt.get('environmentProbeCheck', {}).get('passed'),
        'converterPeakRSSBytes': receipt.get('converterPeakRSSBytes'),
        'sampledPeakPhysicalFootprintBytes': receipt.get('sampledPeakPhysicalFootprintBytes'),
        'conversionSeconds': receipt.get('conversionSeconds'), 'outputBytes': receipt.get('outputBytes'),
        'imageCount': len(images), 'imageBytes': sum(images.values()),
        'pageCount': report.get('pageCount'), 'reflowedPageCount': report.get('reflowedPageCount'),
        'recognizedPageCount': report.get('recognizedPageCount'), 'reportedImageCount': report.get('imageCount'),
        'warningsByCode': dict(sorted(Counter(w.get('code') for w in warnings).items())),
        'ocrPages': sorted({w['page'] for w in warnings if w.get('code') == 'ocrUsed' and 'page' in w}),
    }
    if case is not None and contract is not None:
        assessment = check_evaluation(case, contract, directory)
        summary['content'] = {'passed': assessment['passed'], 'checks': assessment.get('checks'),
                              **classify_errors(assessment.get('errors', []))}
    return summary, pages, markers


def compare(runs, case=None, contract=None):
    """runs: [(label, directory), ...]; the first is the baseline for drift."""
    results = []
    baseline = None
    for label, directory in runs:
        summary, pages, markers = run_summary(directory, case, contract)
        summary['label'] = label
        if baseline is None:
            baseline = (pages, markers)
            summary['drift'] = None
        else:
            base_pages, base_markers = baseline
            numbers = sorted(base_pages.keys() | pages.keys())
            summary['drift'] = {
                'changedTextPages': [n for n in numbers if base_pages.get(n, {}).get('text') != pages.get(n, {}).get('text')],
                'changedImageCountPages': [n for n in numbers if len(base_pages.get(n, {}).get('images', []))
                                           != len(pages.get(n, {}).get('images', []))],
                'pageMarkersEqual': base_markers == markers,
            }
        results.append(summary)
    return {'baseline': runs[0][0], 'runs': results,
            'scope': 'Gate results, resources, counts, warnings and text/image-count drift between raster settings; '
                     'not a fidelity qualification or a judgement of which output is correct.'}


def markdown(result):
    lines = ['| Run | Options | Passed | Peak RSS MiB | Footprint MiB | Seconds | EPUB MiB | Images | Image MiB | Reflowed | OCR pages | Content (ref/other errors) | Changed text pages |',
             '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |']
    for run in result['runs']:
        content = run.get('content')
        content_cell = ('n/a' if content is None else
                        f"{'pass' if content['passed'] else 'fail'} ({len(content['referenceImageErrors'])}/{len(content['otherErrors'])})")
        drift = run.get('drift')
        drift_cell = 'baseline' if drift is None else (str(len(drift['changedTextPages'])) + ('' if drift['pageMarkersEqual'] else ', markers differ'))
        mib = lambda value: f'{value / 1048576:.1f}' if isinstance(value, (int, float)) else 'n/a'
        lines.append(f"| {run['label']} | {run['options']} | {run['runPassed']} | {mib(run['converterPeakRSSBytes'])} | "
                     f"{mib(run['sampledPeakPhysicalFootprintBytes'])} | {run['conversionSeconds']:.1f} | {mib(run['outputBytes'])} | "
                     f"{run['imageCount']} | {mib(run['imageBytes'])} | {run['reflowedPageCount']} | {run['recognizedPageCount']} | "
                     f"{content_cell} | {drift_cell} |")
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='append', required=True, metavar='LABEL=DIRECTORY',
                        help='evaluation directory; the first is the drift baseline; repeatable')
    parser.add_argument('--case', help='corpus case id whose reviewed content contract should be assessed')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    runs = []
    for item in args.run:
        label, separator, directory = item.partition('=')
        if not label or not separator or not directory:
            parser.error('runs must look like LABEL=DIRECTORY')
        runs.append((label, Path(directory)))
    case = contract = None
    if args.case:
        cases = json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']
        contracts = json.loads((ROOT / 'corpus/regressions.json').read_text())['cases']
        case = next((c for c in cases if c['id'] == args.case), None)
        contract = next((c for c in contracts if c['id'] == args.case), None)
        if case is None or contract is None:
            parser.error('case has no reviewed content contract')
    result = compare(runs, case, contract)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(markdown(result))


if __name__ == '__main__':
    main()
