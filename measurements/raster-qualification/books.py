#!/usr/bin/env python3
"""Convert complete corpus books at several raster resolutions through the release evaluator.

Each (case, setting) pair is a fresh sequential `tools/evaluate-real-document.py` run with the
compiled capability probe, EPUBCheck and the case's existing memory ceiling, followed by the
reviewed content contract (`tools/check_corpus_content.py`). The explicit `--raster-dpi=180`
run is compared strictly against the library-default run with `tools/compare_conversion_runs.py`;
runs at other resolutions are summarized by `tools/raster_book_comparison.py`. Nothing here
changes library defaults; failed gates are recorded, never retried or hidden.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CASES = ['cdc-zombie-pandemic-2011', 'fed-explained-2021', 'cia-blue-book-14-1955', 'wallace-algebra-2010']


def run(command, log_path, timeout):
    started = time.monotonic()
    with log_path.open('w') as log:
        completed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
    return {'command': [str(part) for part in command], 'exitCode': completed.returncode,
            'elapsedSeconds': round(time.monotonic() - started, 3), 'log': log_path.name}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='new directory')
    parser.add_argument('--converter', type=Path, required=True)
    parser.add_argument('--environment-probe', type=Path, required=True)
    parser.add_argument('--epubcheck', type=Path, default=Path('/opt/homebrew/bin/epubcheck'))
    parser.add_argument('--execution-context', default='host-terminal')
    parser.add_argument('--case', action='append', dest='cases')
    parser.add_argument('--dpi', action='append', type=int, dest='dpis')
    parser.add_argument('--timeout', type=float, default=3600)
    args = parser.parse_args()
    cases = {c['id']: c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
    selected = args.cases or DEFAULT_CASES
    dpis = args.dpis or [120, 180, 240]
    args.output.mkdir(parents=True, exist_ok=False)
    python = sys.executable
    summary = {'converter': str(args.converter.resolve()), 'probe': str(args.environment_probe.resolve()), 'runs': []}
    for case_id in selected:
        case = cases[case_id]
        pdf = ROOT / 'corpus/cache' / case['filename']
        settings = [('defaults', [])] + [(f'dpi-{dpi}', [f'--converter-option=--raster-dpi={dpi}']) for dpi in dpis]
        for label, options in settings:
            directory = args.output / case_id / label
            directory.parent.mkdir(parents=True, exist_ok=True)
            record = {'case': case_id, 'setting': label, 'directory': str(directory)}
            record['evaluation'] = run([python, ROOT / 'tools/evaluate-real-document.py', '--case', case_id,
                                        '--pdf', pdf, '--converter', args.converter, '--output', directory,
                                        '--epubcheck', args.epubcheck, '--environment-probe', args.environment_probe,
                                        '--execution-context', args.execution_context, '--timeout', str(args.timeout),
                                        *options], args.output / f'{case_id}-{label}-evaluate.log', args.timeout + 600)
            if (directory / 'result.json').exists():
                record['content'] = run([python, ROOT / 'tools/check_corpus_content.py', '--case', case_id,
                                         '--evaluation', directory], args.output / f'{case_id}-{label}-content.log', 1800)
            summary['runs'].append(record)
            print(f'{case_id} {label}: evaluate exit {record["evaluation"]["exitCode"]} '
                  f'in {record["evaluation"]["elapsedSeconds"]}s; content exit '
                  f'{record.get("content", {}).get("exitCode")}', flush=True)
            (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        if 180 in dpis:
            comparison = args.output / f'{case_id}-defaults-vs-dpi-180.json'
            record = {'case': case_id, 'setting': 'strict-comparison defaults vs dpi-180',
                      'comparison': run([python, ROOT / 'tools/compare_conversion_runs.py',
                                         '--baseline', args.output / case_id / 'defaults',
                                         '--candidate', args.output / case_id / 'dpi-180', '--output', comparison],
                                        args.output / f'{case_id}-strict-comparison.log', 600)}
            summary['runs'].append(record)
            print(f'{case_id} strict defaults vs dpi-180: exit {record["comparison"]["exitCode"]}', flush=True)
            (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print('DONE', flush=True)


if __name__ == '__main__':
    main()
