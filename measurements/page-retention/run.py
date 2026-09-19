"""Measure page-retention strategies on complete corpus books.

For each case this runs the retained baseline converter (built from the pre-change commit)
and the candidate converter under every retention strategy through the standard
real-document evaluator. Each candidate output must be byte-identical to the baseline
output apart from the package identifier and timestamp. Peak RSS, sampled physical
footprint, CPU/wall time and peak evaluation-directory disk use are recorded per run.
Output EPUBs are deleted after comparison unless --keep-epubs is given; receipts remain.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import epub_identity as identity  # noqa: E402

STRATEGIES = ['resident', 'spill', 'reextract']
ENVIRONMENT_VARIABLE = 'PDFREFLOW_PAGE_RETENTION'
# Explicit policies keep both binaries on the same options regardless of library defaults.
COMMON_FLAGS = ['--reference-images', 'automatic']
CASE_FLAGS = {
    'gpo-warren-1964': ['--reference-images', 'never'],
    'noaa-nca5-2023': ['--maximum-output-bytes', '4294967296', '--maximum-epub-bytes', '4294967296'],
}
DEFAULT_CASES = ['faa-phak-8083-25c', 'wallace-algebra-2010', 'gpo-911-2004', 'fed-explained-2021',
                 'dga-2025-2030', 'gpo-our-flag-2003', 'cia-blue-book-14-1955', 'cdc-zombie-pandemic-2011',
                 'gpo-warren-1964', 'noaa-nca5-2023']


def digest(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_launcher(path, binary, flags):
    quoted = ' '.join(f"'{flag}'" for flag in flags)
    path.write_text(f'#!/bin/sh\nexec \'{binary}\' "$@" {quoted}\n')
    path.chmod(0o755)


class DiskSampler:
    """Peak size of one run's directory while its conversion runs, sampled once per second.

    The converter stages images and spilled pages beside the destination, so this
    includes transient workspace bytes as well as the final archive.
    """

    def __init__(self, directory):
        self.directory = directory
        self.peak = 0
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def _size(self):
        try:
            result = subprocess.run(['du', '-sk', str(self.directory)], capture_output=True, text=True)
            return int(result.stdout.split()[0]) * 1024
        except (OSError, ValueError, IndexError):
            return 0

    def _run(self):
        while not self._stop.is_set():
            self.peak = max(self.peak, self._size())
            self._stop.wait(1.0)

    def __enter__(self):
        self._thread.start()
        return self

    def __exit__(self, *exc):
        self._stop.set()
        self._thread.join()
        self.peak = max(self.peak, self._size())


def evaluate(case, pdf, launcher, output, environment, epubcheck, timeout):
    command = [sys.executable, str(ROOT / 'tools/evaluate-real-document.py'), '--case', case, '--pdf', str(pdf),
               '--converter', str(launcher), '--output', str(output), '--timeout', str(timeout),
               '--max-peak-rss-mib', '1000000']
    if epubcheck:
        command += ['--epubcheck', str(epubcheck)]
    env = dict(os.environ)
    env.pop(ENVIRONMENT_VARIABLE, None)
    env.update(environment)
    started = time.monotonic()
    with DiskSampler(output) as disk:
        run = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
    result_path = output / 'result.json'
    result = json.loads(result_path.read_text()) if result_path.exists() else {}
    epub = next(iter(output.glob('*.epub')), None)
    return {
        'evaluatorExitCode': run.returncode,
        'evaluatorSeconds': time.monotonic() - started,
        'conversionExitCode': result.get('conversionExitCode'),
        'conversionSeconds': result.get('conversionSeconds'),
        'converterCPUSeconds': result.get('converterCPUSeconds'),
        'converterPeakRSSBytes': result.get('converterPeakRSSBytes'),
        'sampledPeakPhysicalFootprintBytes': result.get('sampledPeakPhysicalFootprintBytes'),
        'progressCheck': result.get('progressCheck', {}).get('passed'),
        'epubcheckExitCode': result.get('epubcheckExitCode'),
        'peakEvaluationDirectoryBytes': disk.peak,
        'epubBytes': epub.stat().st_size if epub else None,
        'epub': epub,
        'stderrTail': run.stderr[-2000:],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True, type=Path, help='pre-change release CLI')
    parser.add_argument('--candidate', required=True, type=Path, help='release CLI with retention strategies')
    parser.add_argument('--output', required=True, type=Path, help='new directory')
    parser.add_argument('--case', action='append', dest='cases')
    parser.add_argument('--epubcheck', type=Path, help='run EPUBCheck on each baseline output')
    parser.add_argument('--keep-epubs', action='store_true')
    parser.add_argument('--timeout', type=float, default=3600)
    parser.add_argument('--strategy', action='append', dest='strategies', choices=STRATEGIES)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output directory must be new')
    args.output.mkdir(parents=True)
    manifest = {document['id']: document
                for document in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
    cases = args.cases or DEFAULT_CASES
    strategies = args.strategies or STRATEGIES
    results = {
        'baselineSHA256': digest(args.baseline), 'candidateSHA256': digest(args.candidate),
        'system': platform.platform(), 'machine': platform.machine(),
        'commonFlags': COMMON_FLAGS, 'caseFlags': CASE_FLAGS, 'cases': {},
    }
    summary_path = args.output / 'results.json'
    overall = True
    for case in cases:
        document = manifest[case]
        pdf = ROOT / 'corpus/cache' / document['filename']
        if not pdf.exists():
            print(f'{case}: missing source {pdf}', file=sys.stderr)
            overall = False
            continue
        flags = COMMON_FLAGS + CASE_FLAGS.get(case, [])
        case_dir = args.output / case
        case_dir.mkdir()
        runs = {}
        baseline_launcher = case_dir / 'launch-baseline.sh'
        write_launcher(baseline_launcher, args.baseline.resolve(), flags)
        print(f'{case}: baseline', flush=True)
        baseline = evaluate(case, pdf, baseline_launcher, case_dir / 'baseline', {}, args.epubcheck, args.timeout)
        baseline_epub = baseline.pop('epub')
        baseline_report = case_dir / 'baseline' / 'conversion-report.json'
        runs['baseline'] = baseline
        for strategy in strategies:
            launcher = case_dir / f'launch-{strategy}.sh'
            write_launcher(launcher, args.candidate.resolve(), flags)
            print(f'{case}: {strategy}', flush=True)
            run = evaluate(case, pdf, launcher, case_dir / strategy, {ENVIRONMENT_VARIABLE: strategy}, None, args.timeout)
            epub = run.pop('epub')
            if baseline_epub and epub:
                differences = identity.compare_epubs(baseline_epub, epub)
                differences += identity.compare_reports(baseline_report, case_dir / strategy / 'conversion-report.json')
            else:
                differences = ['no EPUB to compare']
            run['identityDifferences'] = differences
            run['identical'] = not differences
            overall = overall and run['identical'] and run['conversionExitCode'] == 0
            runs[strategy] = run
            if epub and not args.keep_epubs:
                epub.unlink()
            for staging in (case_dir / strategy).glob('.pdfreflow-*'):
                shutil.rmtree(staging, ignore_errors=True)
            results['cases'][case] = {'flags': flags, 'sourceSHA256': document.get('sha256'), 'runs': runs}
            summary_path.write_text(json.dumps(results, indent=1, sort_keys=True))
        overall = overall and baseline['conversionExitCode'] == 0
        if baseline_epub and not args.keep_epubs:
            baseline_epub.unlink()
        results['cases'][case] = {'flags': flags, 'sourceSHA256': document.get('sha256'), 'runs': runs}
        summary_path.write_text(json.dumps(results, indent=1, sort_keys=True))
    results['allIdenticalAndSuccessful'] = overall
    summary_path.write_text(json.dumps(results, indent=1, sort_keys=True))
    print('all identical and successful' if overall else 'FAILURES recorded', flush=True)
    return 0 if overall else 1


if __name__ == '__main__':
    sys.exit(main())
