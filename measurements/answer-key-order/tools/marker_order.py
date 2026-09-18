#!/usr/bin/env python3
"""How many of Wallace's numbered runs read in printed order (#185, #195).

Reads an EPUB's spine in order and takes every block that opens with an `N)` marker: a `<pre>`
entry, or a `<p class="math">` entry whose value became MathML (#190). A preserved crop without
MathML carries its number only in its pixels, so it is skipped rather than guessed.

A *run* is the markers of one page between two blocks that are not entries: a title
(`Answers - Integers`), a section number (`1.2`), a heading or an instruction paragraph. A crop or
an entry's wrapped continuation does not end a run. A run of two or more markers reads *in
order* when its numbers only ever rise, and is *consecutive* when each is one more than the last
(the rule #194 and #195 set for an ordered list). Pages before 438 are the exercises, from 438 the
answer keys, as `measurements/semantic-lists/classify_pre_blocks.py` divides them.
`continuedAcrossABreak` counts pairs of runs on one page where the later continues the earlier's
numbering across a title or label, the mark of a key's title read inside the key (an exercise set
is also divided by its instruction lines, so the count means little there).

    python3 measurements/answer-key-order/tools/marker_order.py <wallace.epub> [--list]
"""

import argparse
import json
import re
import zipfile
from pathlib import PurePosixPath
import xml.etree.ElementTree as ET

HTML = '{http://www.w3.org/1999/xhtml}'
OPF = '{http://www.idpf.org/2007/opf}'
EPUB = '{http://www.idpf.org/2007/ops}'
BLOCKS = {HTML + tag for tag in ('p', 'pre', 'figure', 'table', 'li',
                                 'h1', 'h2', 'h3', 'h4', 'h5', 'h6')}
MARKER = re.compile(r'^\s*([0-9]{1,3})\)')
ANSWERS_FROM = 438


def blocks(path):
    """(page, kind, number) for every top-level block in reading order."""
    result = []
    with zipfile.ZipFile(path) as archive:
        package = ET.fromstring(archive.read('EPUB/package.opf'))
        manifest = {e.get('id'): e.get('href') for e in package.find(OPF + 'manifest')}
        page = None

        def walk(element):
            nonlocal page
            if 'pagebreak' in element.get(EPUB + 'type', '').split():
                marker = element.get('id', '')
                if re.fullmatch(r'page-[1-9][0-9]*', marker):
                    page = int(marker[5:])
            if element.tag in BLOCKS:
                text = ''.join(element.itertext())
                match = MARKER.match(text)
                tag = element.tag[len(HTML):]
                if match and tag in ('pre', 'p', 'li'):
                    result.append((page, 'entry', int(match.group(1))))
                elif tag == 'figure' or tag == 'pre':
                    result.append((page, 'skip', None))
                else:
                    result.append((page, 'break', None))
                # A page break inside a block still moves the page on.
                for child in element.iter():
                    if 'pagebreak' in child.get(EPUB + 'type', '').split():
                        marker = child.get('id', '')
                        if re.fullmatch(r'page-[1-9][0-9]*', marker):
                            page = int(marker[5:])
                return
            for child in element:
                walk(child)

        for reference in package.find(OPF + 'spine'):
            chapter = PurePosixPath('EPUB') / manifest[reference.get('idref')]
            tree = ET.fromstring(archive.read(str(chapter)))
            walk(tree.find(HTML + 'body'))
    return result


def runs(items):
    """Page-bounded runs of marker numbers, split at every non-entry block."""
    found, current, page = [], [], None
    for item_page, kind, number in items:
        if item_page != page or kind == 'break':
            if current:
                found.append((page, current))
            current = []
            page = item_page
        if kind == 'entry':
            current.append(number)
    if current:
        found.append((page, current))
    return found


def summary(path):
    totals = {}
    detail = {'exercise': [], 'answer-key': []}
    found = runs(blocks(path))
    # A key's title or section number read inside it splits one key into two runs that each rise:
    # the later run on the page continues the earlier one instead of restarting.
    for (page, earlier), (later_page, later) in zip(found, found[1:]):
        if page is not None and page == later_page and later[0] > earlier[-1]:
            name = 'answer-key' if page >= ANSWERS_FROM else 'exercise'
            stat = totals.setdefault(name, {})
            stat['continuedAcrossABreak'] = stat.get('continuedAcrossABreak', 0) + 1
            detail[name].append({'page': page, 'continues': [earlier[-1], later[0]]})
    for page, numbers in found:
        if page is None or len(numbers) < 2:
            continue
        name = 'answer-key' if page >= ANSWERS_FROM else 'exercise'
        steps = list(zip(numbers, numbers[1:]))
        rising = all(b > a for a, b in steps)
        consecutive = all(b == a + 1 for a, b in steps)
        stat = totals.setdefault(name, {})
        for key in ('runs', 'markers', 'inOrder', 'consecutive', 'outOfOrder', 'outOfOrderMarkers'):
            stat.setdefault(key, 0)
        stat['runs'] += 1
        stat['markers'] += len(numbers)
        stat['inOrder'] += rising
        stat['consecutive'] += consecutive
        if not rising:
            stat['outOfOrder'] += 1
            stat['outOfOrderMarkers'] += len(numbers)
            detail[name].append({'page': page, 'numbers': numbers})
    return totals, detail


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('epub')
    parser.add_argument('--list', action='store_true', help='list every run that is out of order')
    arguments = parser.parse_args()
    totals, detail = summary(arguments.epub)
    print(json.dumps(totals, indent=1, sort_keys=True))
    if arguments.list:
        for name, found in detail.items():
            for run in found:
                print(name, run['page'], run.get('numbers') or 'continues %d with %d' % tuple(run['continues']))


if __name__ == '__main__':
    main()
