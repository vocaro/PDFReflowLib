#!/usr/bin/env python3
"""Enforce a fresh-process memory ceiling for indexing the pinned FAA structure tree."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

from pdfreflow_tools import swift_sources
from pdfreflow_tools.corpus import ROOT, cached_source, find_case, manifest_cases, verify_source

PROBE = 'inspect-structure.swift'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--maximum-rss-mib', type=int, default=192)
    args = parser.parse_args()
    if args.maximum_rss_mib < 1:
        parser.error('RSS ceiling must be positive')
    case = find_case(manifest_cases(ROOT), 'faa-phak-8083-25c')
    source = verify_source(cached_source(case, ROOT), case, 'FAA')
    environment = dict(os.environ)
    environment.setdefault('DEVELOPER_DIR', subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    with tempfile.TemporaryDirectory(prefix='pdfreflow-structure-') as directory:
        binary = Path(directory) / 'inspect-structure'
        subprocess.run(['swiftc', '-O', '-swift-version', '6', *swift_sources.sources(PROBE), '-o', str(binary)],
            cwd=ROOT, env=environment, check=True, capture_output=True, text=True)
        result = subprocess.run(['/usr/bin/time', '-l', str(binary), str(source)],
            env=environment, capture_output=True, text=True, check=True)
    match = re.search(r'^\s*(\d+)\s+maximum resident set size\s*$', result.stderr, re.MULTILINE)
    if match is None:
        raise ValueError('Missing fresh-process peak RSS measurement')
    peak = int(match[1])
    print(result.stdout.strip())
    print(f'Structure index peak RSS: {peak} bytes; ceiling: {args.maximum_rss_mib} MiB')
    if peak > args.maximum_rss_mib * 1024 * 1024:
        raise ValueError('Structure index exceeds peak RSS ceiling')
    print('PASS isolated structure-index memory gate (macOS; not an iOS device budget)')


if __name__ == '__main__':
    main()
