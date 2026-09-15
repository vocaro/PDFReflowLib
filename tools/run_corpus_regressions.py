#!/usr/bin/env python3
"""Run complete, cached PDFs sequentially through resource, EPUB and content gates.

No automatic downloads or silent fixture skips. By default runs every reviewed corpus contract.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from check_corpus_content import ROOT, check_evaluation


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--converter', type=Path, required=True)
    parser.add_argument('--epubcheck', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--case', action='append', dest='selected')
    args = parser.parse_args()
    manifest = json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']
    definitions = json.loads((ROOT / 'corpus/regressions.json').read_text())
    contracts = {c['id']: c for c in definitions['cases']}
    selected = args.selected if args.selected is not None else list(contracts)
    if not selected or len(selected) != len(set(selected)) or any(name not in contracts for name in selected):
        parser.error('choose distinct cases with reviewed regression contracts')
    cases = {c['id']: c for c in manifest}
    missing = [str(ROOT / 'corpus/cache' / cases[name]['filename']) for name in selected
               if not (ROOT / 'corpus/cache' / cases[name]['filename']).is_file()]
    if missing:
        parser.error('Missing cached PDFs; fetch explicitly with tools/fetch_corpus.py or supply verified originals: ' + ', '.join(missing))
    converter = args.converter.resolve(strict=True)
    epubcheck = args.epubcheck.resolve(strict=True)
    args.output.mkdir(parents=True, exist_ok=False)
    results = []
    for name in selected:
        print('CHECK ' + name, flush=True)
        directory = args.output / name
        with (args.output / (name + '.log')).open('w') as log:
            run = subprocess.run([sys.executable, str(ROOT / 'tools/evaluate-real-document.py'),
                '--case', name, '--pdf', str(ROOT / 'corpus/cache' / cases[name]['filename']),
                '--converter', str(converter), '--output', str(directory), '--epubcheck', str(epubcheck)],
                stdout=log, stderr=subprocess.STDOUT)
        if run.returncode:
            assessment = {'case': name, 'passed': False, 'errors': ['Conversion/resource/EPUB gate failed; see case log']}
        else:
            try:
                assessment = check_evaluation(cases[name], contracts[name], directory)
            except Exception as error:
                assessment = {'case': name, 'passed': False, 'errors': [str(error)]}
        results.append(assessment)
        if directory.exists():
            (directory / 'content-assessment.json').write_text(json.dumps(assessment, indent=2) + '\n')
        print(('PASS ' if assessment['passed'] else 'FAIL ') + name, flush=True)
    excluded = definitions['excludedFullConversions']
    summary = {'passed': all(r['passed'] for r in results), 'results': results,
               'notRun': [name for name in contracts if name not in selected],
               'knownUnsupportedFullConversions': excluded}
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    for item in excluded:
        print('NOT COVERED ' + item['id'] + ': ' + item['reason'], flush=True)
    for name in summary['notRun']:
        print('NOT RUN ' + name + ' (case filter)', flush=True)
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
