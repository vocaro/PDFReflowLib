#!/usr/bin/env python3
"""Run complete, cached PDFs through resource, EPUB and content gates.

No automatic downloads or silent fixture skips. By default runs every reviewed corpus contract,
one at a time; `--jobs N` runs N cases at once, each converter in its own process, starting the
largest sources first. The summary lists results in selection order either way.

Exits 1 when a case failed and 3 when the only cases that did not pass had their memory ceiling
left unmeasured by host memory pressure. Neither is a pass, but they are different findings.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import sys
import threading

from check_corpus_content import check_evaluation
from evaluate_real_document import UNMEASURED_MEMORY_EXIT
from pdfreflow_tools.corpus import ROOT, cached_source, manifest_cases, regression_contracts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--converter', type=Path, required=True)
    parser.add_argument('--epubcheck', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--case', action='append', dest='selected')
    parser.add_argument('--execution-context', help='caller-declared launch context recorded in each evaluation')
    parser.add_argument('--environment-probe', type=Path, help='compiled raster/Vision capability probe')
    parser.add_argument('--jobs', type=int, default=1, help='cases evaluated at once (default 1)')
    parser.add_argument('--memory-attempts', type=int, help='conversions each case may spend on a peak RSS the host did not spoil')
    parser.add_argument('--settle-seconds', type=float, help='seconds each case waits for host memory pressure to return to normal before converting')
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('jobs must be positive')
    definitions = regression_contracts(ROOT)
    contracts = {c['id']: c for c in definitions['cases']}
    selected = args.selected if args.selected is not None else list(contracts)
    if not selected or len(selected) != len(set(selected)) or any(name not in contracts for name in selected):
        parser.error('choose distinct cases with reviewed regression contracts')
    cases = {c['id']: c for c in manifest_cases(ROOT)}
    sources = {name: cached_source(cases[name], ROOT) for name in selected}
    missing = [str(source) for source in sources.values() if not source.is_file()]
    if missing:
        parser.error('Missing cached PDFs; fetch explicitly with tools/fetch_corpus.py or supply verified originals: ' + ', '.join(missing))
    converter = args.converter.resolve(strict=True)
    epubcheck = args.epubcheck.resolve(strict=True)
    probe = args.environment_probe.resolve(strict=True) if args.environment_probe else None
    args.output.mkdir(parents=True, exist_ok=False)
    printing = threading.Lock()

    def report(line):
        with printing:
            print(line, flush=True)

    def evaluate(name):
        report('CHECK ' + name)
        directory = args.output / name
        with (args.output / (name + '.log')).open('w') as log:
            run = subprocess.run([sys.executable, str(ROOT / 'tools/evaluate_real_document.py'),
                '--case', name, '--pdf', str(sources[name]),
                '--converter', str(converter), '--output', str(directory), '--epubcheck', str(epubcheck),
                '--concurrent-evaluations', str(min(args.jobs, len(selected)))]
                + (['--execution-context', args.execution_context] if args.execution_context else [])
                + (['--environment-probe', str(probe)] if probe else [])
                + (['--memory-attempts', str(args.memory_attempts)] if args.memory_attempts is not None else [])
                + (['--settle-seconds', str(args.settle_seconds)] if args.settle_seconds is not None else []),
                stdout=log, stderr=subprocess.STDOUT)
        unmeasured = run.returncode == UNMEASURED_MEMORY_EXIT
        if run.returncode and not unmeasured:
            assessment = {'case': name, 'passed': False, 'errors': ['Conversion/resource/EPUB gate failed; see case log']}
        else:
            try:
                assessment = check_evaluation(cases[name], contracts[name], directory)
            except Exception as error:
                assessment = {'case': name, 'passed': False, 'errors': [str(error)]}
        if unmeasured:
            # Conversion, structure, EPUBCheck, progress and the content contract all passed, and
            # host memory pressure left the ceiling unmeasurable. Not a pass, and not this
            # library failing either, so it is reported as its own outcome.
            assessment['memoryUnmeasured'] = True
            outcome = 'UNMEASURED ' if assessment['passed'] else 'FAIL '
            assessment['passed'] = False
            assessment.setdefault('errors', []).append(
                'Memory ceiling not measured: host memory pressure rose above normal during every attempt')
        else:
            outcome = 'PASS ' if assessment['passed'] else 'FAIL '
        if directory.exists():
            (directory / 'content-assessment.json').write_text(json.dumps(assessment, indent=2) + '\n')
        report(outcome + name)
        return assessment

    if args.jobs == 1:
        results = [evaluate(name) for name in selected]
    else:
        # Source size is a rough proxy for conversion time; starting the largest first keeps the
        # longest case from being the last one scheduled.
        schedule = sorted(selected, key=lambda name: -sources[name].stat().st_size)
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            assessments = dict(zip(schedule, pool.map(evaluate, schedule)))
        results = [assessments[name] for name in selected]
    excluded = definitions['excludedFullConversions']
    unmeasured = [r['case'] for r in results if r.get('memoryUnmeasured')]
    summary = {'passed': all(r['passed'] for r in results), 'results': results,
               'memoryUnmeasured': unmeasured,
               'notRun': [name for name in contracts if name not in selected],
               'knownUnsupportedFullConversions': excluded}
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    for item in excluded:
        print('NOT COVERED ' + item['id'] + ': ' + item['reason'], flush=True)
    for name in summary['notRun']:
        print('NOT RUN ' + name + ' (case filter)', flush=True)
    for name in unmeasured:
        print('MEMORY NOT MEASURED ' + name + ': host memory pressure above normal throughout; '
              'peak RSS neither passed nor failed the ceiling. Re-run on an unloaded host.', flush=True)
    if summary['passed']:
        return 0
    failed = [r for r in results if not r['passed'] and not r.get('memoryUnmeasured')]
    return 1 if failed else UNMEASURED_MEMORY_EXIT


if __name__ == '__main__':
    raise SystemExit(main())
