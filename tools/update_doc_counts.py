#!/usr/bin/env python3
"""Regenerate the counts in README.md and doc/regression-testing.md.

Counts live only between markers, so ordinary changes never hand-edit them:

    <!-- counts:NAME -->generated text<!-- counts:end -->

An inline region stays on its line. A region whose markers sit on their own lines holds a
generated paragraph wrapped at 100 columns. Contract counts come from the checker's own
CHECK_TYPES table (tools/check_corpus_content.py). The Swift count is the number of `@Test`
declarations, which is what `swift test` reports ("Test run with N tests"): a parameterised test is
one test there. The Python count is what `unittest discover` in scripts/check-all.sh runs.

usage: update_doc_counts.py [--check] [--swift-list]
  --check       write nothing; print a diff and exit 1 when a region is stale
  --swift-list  also require the static Swift count to equal `swift test list --skip-build`
                (needs the debug test build, as scripts/check-all.sh leaves it)
"""
import argparse
import difflib
import json
from pathlib import Path
import re
import subprocess
import sys
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_corpus_content import count_checks  # noqa: E402

DOCS = ('README.md', 'doc/regression-testing.md')
WIDTH = 100
KEEP = '\x00'
REGION = re.compile(r'<!-- counts:(?P<name>[a-z-]+) -->(?P<body>.*?)<!-- counts:end -->', re.S)


def short_title(title):
    """A document title up to its first subtitle, edition or series separator."""
    return re.split(r':|,| \(', title, maxsplit=1)[0].strip()


def join_series(items):
    items = list(items)
    return items[0] if len(items) == 1 else ', '.join(items[:-1]) + ' and ' + items[-1]


def contract_counts(root=ROOT):
    contracts = json.loads((root / 'corpus/regressions.json').read_text())['cases']
    manifest = {doc['id']: doc for doc in json.loads((root / 'corpus/manifest.json').read_text())['documents']}
    counts = count_checks(contracts)
    counts['titles'] = [short_title(manifest[c['id']]['title']) for c in contracts if c.get('pages')]
    return counts


SWIFT_NOISE = re.compile(r'/\*.*?\*/|//[^\n]*|"""(?:.|\n)*?"""|"(?:\\.|[^"\\\n])*"', re.S)


def swift_test_count(root=ROOT):
    """`@Test` attributes outside comments and string literals under Tests/."""
    return sum(len(re.findall(r'(?<![\w.])@Test\b', SWIFT_NOISE.sub('', path.read_text())))
               for path in sorted((root / 'Tests').rglob('*.swift')))


def listed_swift_test_count(root=ROOT):
    output = subprocess.run(['swift', 'test', 'list', '--skip-build'], cwd=root, check=True,
                            capture_output=True, text=True).stdout
    return sum(1 for line in output.splitlines() if line.strip())


def python_test_count(root=ROOT):
    """What `python3 -m unittest discover -s tools -p 'test_*.py'` runs ("Ran N tests")."""
    tools = str(root / 'tools')
    return unittest.TestLoader().discover(tools, pattern='test_*.py', top_level_dir=tools).countTestCases()


def plural(count, noun):
    return f'{count} {noun}' if count == 1 else f'{count} {noun}s'


def region_texts(contracts, swift_tests, python_tests):
    # A no-break placeholder keeps each count on the line of its type when the paragraph wraps.
    by_type = [f'{count}{KEEP}{name}' for name, count in contracts['byType'].items() if count]
    coverage = (
        f'[corpus/regressions.json](../corpus/regressions.json) has {contracts["checks"]} targeted checks '
        f'on {contracts["pages"]} reviewed pages across {contracts["documents"]} documents: '
        f'{join_series("*" + title + "*" for title in contracts["titles"])}. '
        f'They comprise {join_series(by_type)} checks, counted as `tools/check_corpus_content.py` '
        f'counts them.')
    return {
        'documents': str(contracts['documents']),
        'contract-summary': f'{contracts["checks"]} checks on {contracts["pages"]} pages of '
                            f'{contracts["documents"]} documents',
        'table-cell-checks': str(contracts['byType']['table-cell']),
        'coverage': coverage,
        'swift-tests': plural(swift_tests, 'Swift test'),
        'python-tests': plural(python_tests, 'Python test'),
    }


def rewrite(text, texts):
    """Replace every region body; unknown region names are an error."""
    def body(match):
        name = match['name']
        if name not in texts:
            raise KeyError(f'unknown counts region {name!r}')
        if match['body'].startswith('\n'):
            generated = '\n' + textwrap.fill(texts[name], WIDTH, break_on_hyphens=False,
                                             break_long_words=False).replace(KEEP, ' ') + '\n'
        else:
            generated = texts[name].replace(KEEP, ' ')
        return f'<!-- counts:{name} -->{generated}<!-- counts:end -->'
    return REGION.sub(body, text)


def update(root, texts, check):
    """Return the unified diffs of stale documents, writing them unless check is set."""
    diffs = []
    for relative in DOCS:
        path = root / relative
        old = path.read_text()
        new = rewrite(old, texts)
        if new != old:
            diffs.append(''.join(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                                      relative, relative)))
            if not check:
                path.write_text(new)
    return diffs


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--swift-list', action='store_true')
    args = parser.parse_args(argv)
    swift_tests = swift_test_count()
    if args.swift_list:
        listed = listed_swift_test_count()
        if listed != swift_tests:
            print(f'`swift test list` has {listed} tests but tools/update_doc_counts.py counts '
                  f'{swift_tests} @Test declarations; fix swift_test_count.', file=sys.stderr)
            return 1
    texts = region_texts(contract_counts(), swift_tests, python_test_count())
    diffs = update(ROOT, texts, args.check)
    for diff in diffs:
        sys.stdout.write(diff)
    sys.stdout.flush()
    if args.check and diffs:
        print('Documentation counts are stale. Run python3 tools/update_doc_counts.py and commit the result.',
              file=sys.stderr)
        return 1
    if not args.check:
        print(f'Updated {len(diffs)} document(s).' if diffs else 'Documentation counts are current.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
