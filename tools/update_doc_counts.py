#!/usr/bin/env python3
"""Generate the suite counts in README.md and doc/regression-testing.md (#156).

Counts of tests, corpus conversions and reviewed pages were hand-typed prose. Nearly every
change had to retype them, so parallel branches conflicted on the same lines and the numbers
drifted; `main` carries two commits (`28d3879`, `44e5e8d`) written only to correct them. Here
they live between markers and nowhere else:

    <!-- counts:NAME -->generated text<!-- counts:end -->

A region whose markers sit on one line is rewritten in place. A region whose opening marker ends
its line holds a generated paragraph wrapped at 100 columns. Nothing outside a region is touched,
so prose and counts no longer share a line and a prose edit no longer collides with a count.

A merge conflict inside a generated region is resolved by rerunning this tool. A conflict whose
two sides differ only inside region bodies is regenerated from the sources, whichever side git
left first; a conflict that also touches prose is left alone and reported, because only a person
knows which prose is wanted.

The counts are taken from the suites themselves, never from the current text: the contract counts
from `CONTRACT_CHECK_TYPES`/`PAGE_CHECK_TYPES` in `tools/check_corpus_content.py`, which `assess`
checks its own running total against; the corpus documents from `corpus/manifest.json` and
`corpus/regressions.json`; the Python tests from the same `unittest` discovery `scripts/check-all.sh`
runs; the Swift tests from the `@Test` declarations under `Tests/`, which `--swift-list` requires
to equal what `swift test list` reports.

usage: update_doc_counts.py [--check] [--swift-list]
  --check       write nothing; print a diff and exit 1 when a region is stale
  --swift-list  also require the static Swift count to equal `swift test list --skip-build`
                (needs the debug test build that `swift test` leaves behind)
"""
import argparse
import difflib
import re
import subprocess
import sys
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_corpus_content import count_checks  # noqa: E402
from pdfreflow_tools.corpus import ROOT, manifest_cases, regression_contracts  # noqa: E402

DOCS = ('README.md', 'doc/regression-testing.md')
WIDTH = 100
KEEP = '\x00'  # A placeholder space that textwrap will not break a line on.
REGION = re.compile(r'<!-- counts:(?P<name>[a-z-]+) -->(?P<body>.*?)<!-- counts:end -->', re.S)
CONFLICT = re.compile(r'^<<<<<<< [^\n]*\n(?P<ours>.*?)^=======\n(?P<theirs>.*?)^>>>>>>> [^\n]*\n',
                      re.S | re.M)
SWIFT_NOISE = re.compile(r'/\*.*?\*/|//[^\n]*|"""(?:.|\n)*?"""|"(?:\\.|[^"\\\n])*"', re.S)


def swift_test_count(root=ROOT):
    """`@Test` attributes under Tests/, outside comments and string literals.

    This is what `swift test` counts: a parameterized test is one test to it, as it is here.
    """
    return sum(len(re.findall(r'(?<![\w.])@Test\b', SWIFT_NOISE.sub('', path.read_text())))
               for path in sorted((Path(root) / 'Tests').rglob('*.swift')))


def listed_swift_test_count(root=ROOT):
    output = subprocess.run(['swift', 'test', 'list', '--skip-build'], cwd=root, check=True,
                            capture_output=True, text=True).stdout
    return sum(1 for line in output.splitlines() if line.strip())


def python_test_count(root=ROOT):
    """What `python3 -m unittest discover -s tools -p 'test_*.py'` runs, by running its discovery."""
    tools = str(Path(root) / 'tools')
    return unittest.TestLoader().discover(tools, pattern='test_*.py', top_level_dir=tools).countTestCases()


def plural(count, noun):
    return f'{count} {noun}' if count == 1 else f'{count} {noun}s'


def join_series(items):
    items = list(items)
    return items[0] if len(items) == 1 else ', '.join(items[:-1]) + ' and ' + items[-1]


def region_texts(root=ROOT):
    contracts = regression_contracts(root)
    counts = count_checks(contracts['cases'])
    # The no-break placeholder keeps each count on the same line as the kind of check it counts.
    breakdown = [f'{count}{KEEP}`{name}`' for name, count in counts['byType'].items() if count]
    return {
        'registered-documents': plural(len(manifest_cases(root)), 'real document'),
        'corpus-documents': str(len(contracts['cases'])),
        'contract-coverage':f'{counts["checks"]} checks on {counts["pages"]} reviewed pages across '
                             f'{counts["documents"]} documents',
        'contract-breakdown': f'Those {counts["checks"]} checks are {join_series(breakdown)}, counted '
                              f'as `tools/check_corpus_content.py` counts them.',
        'swift-tests': plural(swift_test_count(root), 'Swift Testing test'),
        'python-tests': plural(python_test_count(root), 'Python test'),
    }


def blanked(text):
    """The text with every region's generated body replaced by one placeholder."""
    return REGION.sub(lambda match: f'<!-- counts:{match["name"]} -->\x01<!-- counts:end -->', text)


def resolve_conflicts(text):
    """Collapse merge conflicts confined to generated regions; return (text, unresolved count).

    Two sides that are the same once their region bodies are blanked differ only in generated
    text, so there is nothing for a person to decide: whichever side is kept is about to be
    overwritten from the sources. Anything else — including a count region on a line whose prose
    the two sides also changed — is left in place and counted, because only a person knows which
    prose is wanted, and a gate that guesses is worse than one that stops.
    """
    unresolved = 0

    def resolve(match):
        nonlocal unresolved
        ours, theirs = match['ours'], match['theirs']
        if REGION.search(ours) and blanked(ours) == blanked(theirs):
            return ours
        unresolved += 1
        return match.group(0)

    return CONFLICT.sub(resolve, text), unresolved


def rewrite(text, texts):
    """Replace every region body. An unknown region name is an error, not a silent skip."""
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
    """(unified diffs of the stale documents, documents left with a prose conflict); writes unless check."""
    diffs, conflicted = [], []
    for relative in DOCS:
        path = Path(root) / relative
        old = path.read_text()
        resolved, unresolved = resolve_conflicts(old)
        if unresolved:
            conflicted.append(relative)
        new = rewrite(resolved, texts)
        if new != old:
            diffs.append(''.join(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                                      relative, relative)))
            if not check:
                path.write_text(new)
    return diffs, conflicted


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--swift-list', action='store_true')
    args = parser.parse_args(argv)
    if args.swift_list:
        listed, static = listed_swift_test_count(), swift_test_count()
        if listed != static:
            print(f'`swift test list` reports {listed} tests but tools/update_doc_counts.py counts '
                  f'{static} @Test declarations; fix swift_test_count.', file=sys.stderr)
            return 1
    diffs, conflicted = update(ROOT, region_texts(), args.check)
    for diff in diffs:
        sys.stdout.write(diff)
    sys.stdout.flush()
    if conflicted:
        print('Unresolved merge conflict outside a generated region in ' + ', '.join(conflicted)
              + '; resolve the prose by hand, then run this tool again.', file=sys.stderr)
        return 1
    if args.check and diffs:
        print('Documentation counts are stale. Run python3 tools/update_doc_counts.py and commit '
              'the result.', file=sys.stderr)
        return 1
    if not args.check:
        print(f'Updated {len(diffs)} document(s).' if diffs else 'Documentation counts are current.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
