"""Rule-exact corpus survey for #69 (split and tight list markers) and #70 (line-ending slashes).

Usage: survey-markers.py split|tight|slash <directory> [case ...]

<directory> holds one lines-<case>.jsonl per document, written by dump-lines.swift
(`NativeTextReader.lines` with style, as the pipeline extracts). The survey runs before
furniture, image, table and note handling, so its counts are an upper bound on what
reconstruction sees; the page comparisons in page-comparison/ are what changed.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

MARKER = re.compile(r'^(?:•|[0-9]{1,3}[.)]|[A-Za-z][.)])$')
TIGHT = re.compile(r'^([0-9]{1,3})\.[A-Z]')
SPACED = re.compile(r'^([0-9]{1,3})\.\s')


def body(lines):
    weights = Counter()
    for line in lines:
        weights[round(line['s'])] += len(line['t'])
    return max(4, weights.most_common(1)[0][0]) if weights else 12


def same_row(a, b):
    return min(a['y'] + a['h'], b['y'] + b['h']) - max(a['y'], b['y']) >= min(a['h'], b['h']) * 0.5


def split(lines, size_of_body):
    hits, claimed = [], set()
    for i, marker in enumerate(lines):
        if i in claimed or marker['m'] or not MARKER.match(marker['t'].strip()):
            continue
        size = marker['s']
        row = [j for j, other in enumerate(lines) if j != i and j not in claimed and same_row(marker, other)]
        if any(lines[j]['x'] < marker['x'] and lines[j]['x'] + lines[j]['w'] >= marker['x'] - size for j in row):
            continue
        pieces = [j for j in row if -1 <= lines[j]['x'] - (marker['x'] + marker['w']) <= size * 2
                  and abs(lines[j]['s'] - size) <= size * 0.1 and not lines[j]['m']
                  and not MARKER.match(lines[j]['t'].strip())]
        if pieces:
            j = min(pieces, key=lambda j: lines[j]['x'])
            claimed.update([i, j])
            hits.append((marker['t'], f"{marker['t']!r} + {lines[j]['t'][:60]!r}"))
    return hits


def tight(lines, size_of_body):
    hits = []
    for line in lines:
        match = TIGHT.match(line['t'])
        if not match or line['m']:
            continue
        number = int(match.group(1))
        siblings = [int(SPACED.match(other['t']).group(1)) for other in lines if SPACED.match(other['t'])
                    and abs(other['x'] - line['x']) <= size_of_body * 0.5
                    and abs(other['s'] - line['s']) <= line['s'] * 0.1]
        if len(siblings) >= 2 and (number - 1 in siblings or number + 1 in siblings):
            hits.append(('tight', line['t'][:70]))
    return hits


def slash(lines, size_of_body):
    # The next line of the same column: the nearest line below at ordinary spacing near the same edge.
    hits = []
    for line in lines:
        text = line['t'].rstrip()
        if not text.endswith('/') or len(text) < 2:
            continue
        below = [other for other in lines if other['y'] < line['y']
                 and line['y'] - (other['y'] + other['h']) < size_of_body * 0.9
                 and abs(other['x'] - line['x']) < size_of_body * 3]
        if not below:
            continue
        following = max(below, key=lambda other: other['y'])['t']
        before, after = text[-2], following[:1]
        joins = (before.isalnum() or before == '/') and after.isalnum()
        hits.append(('joins' if joins else 'keeps space', f"{text[-45:]!r} || {following[:40]!r}"))
    return hits


def main():
    mode, directory = sys.argv[1], Path(sys.argv[2])
    cases = sys.argv[3:] or sorted(path.stem[len('lines-'):] for path in directory.glob('lines-*.jsonl'))
    survey = {'split': split, 'tight': tight, 'slash': slash}[mode]
    for case in cases:
        hits = []
        for raw in open(directory / f'lines-{case}.jsonl'):
            page = json.loads(raw)
            hits += [(page['page'], kind, detail) for kind, detail in survey(page['lines'], body(page['lines']))]
        kinds = Counter(kind for _, kind, _ in hits)
        print(f"### {case}: {len(hits)} on {len({page for page, _, _ in hits})} pages; {dict(kinds.most_common(6))}")
        for page, kind, detail in hits:
            print(f'  p{page} [{kind}]: {detail}')


main()
