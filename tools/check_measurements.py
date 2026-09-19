#!/usr/bin/env python3
"""Measurements are records, not captures.

`measurements/` holds the record of each experiment and the small summaries a record quotes.
Raw captures (logs, archives, renders, converted books) and bulk additions do not belong in the
tree: they are never read by a gate, and the repository is cloned whole by every package client.
Live tooling a gate runs lives under `tools/`. This gate fails when a change adds a raw capture or
more than `MAXIMUM_ADDED_BYTES` under `measurements/` relative to the base branch, counting
committed, staged, unstaged and untracked additions.
"""
import argparse
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
RAW_SUFFIXES = {'.gz', '.tgz', '.zip', '.tar', '.png', '.jpg', '.jpeg', '.log', '.epub', '.pdf', '.plist'}
MAXIMUM_ADDED_BYTES = 2 * 1024 * 1024


def violations(added, maximum_bytes=MAXIMUM_ADDED_BYTES):
    """`added` is [(path, bytes)] of files added under measurements/; returns human-readable failures."""
    problems = []
    for path, _ in added:
        if Path(path).suffix.lower() in RAW_SUFFIXES:
            problems.append(f'raw capture added: {path} (keep the record and a small summary; captures stay out of the tree)')
    total = sum(size for _, size in added)
    if total > maximum_bytes:
        problems.append(f'{total} bytes added under measurements/ exceed the {maximum_bytes}-byte budget')
    return problems


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def default_base():
    for candidate in ('origin/main', 'main'):
        if subprocess.run(['git', 'rev-parse', '--verify', '--quiet', candidate], cwd=ROOT, capture_output=True).returncode == 0:
            return candidate
    return 'HEAD'


def added_files(base):
    names = set()
    merge_base = git('merge-base', base, 'HEAD').strip()
    names.update(git('diff', '--name-only', '--diff-filter=A', merge_base, 'HEAD', '--', 'measurements').split())
    names.update(git('diff', '--name-only', '--diff-filter=A', merge_base, '--', 'measurements').split())
    names.update(git('ls-files', '--others', '--exclude-standard', 'measurements').split())
    return sorted((name, (ROOT / name).stat().st_size) for name in names if (ROOT / name).is_file())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--base', help='branch or commit the additions are measured against (default: origin/main, then main)')
    parser.add_argument('--maximum-added-bytes', type=int, default=MAXIMUM_ADDED_BYTES)
    args = parser.parse_args()
    base = args.base or default_base()
    added = added_files(base)
    problems = violations(added, args.maximum_added_bytes)
    for problem in problems:
        print('FAIL ' + problem)
    print(f'{"FAIL" if problems else "PASS"} measurements policy: {len(added)} file(s), '
          f'{sum(size for _, size in added)} bytes added under measurements/ since {base}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
