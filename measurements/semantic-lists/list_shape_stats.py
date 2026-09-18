#!/usr/bin/env python3
"""Run-level statistics for the classified `<pre>` blocks (issue #29).

A "run" is the chain of sibling markers `classify_pre_blocks.py` found: the candidate
`<ol>`/`<ul>` element. This reports, per book and class, how many runs there are, how many
start at something other than 1, how many skip values, and how many are not monotonically
increasing (Wallace's two-column exercise sets read down the left column and then the right,
so an ordered list would renumber them wrongly).
"""

import argparse
import collections
import json

LIST_CLASSES = ('numbered-list-item', 'bulleted-list-item', 'lettered-sub-item',
                'exercise-item', 'answer-key-entry', 'bibliography-entry',
                'endnote-entry', 'questionnaire-item')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('surveys', nargs='+')
    parser.add_argument('--classes', nargs='*', default=list(LIST_CLASSES))
    arguments = parser.parse_args()
    print(f'{"book":40s} {"class":22s} {"runs":>5s} {"items":>6s} {"pages":>5s} '
          f'{"start≠1":>7s} {"gaps":>5s} {"desc":>5s} {"len1":>5s} {"split":>5s}')
    grand = collections.Counter()
    for path in arguments.surveys:
        data = json.load(open(path))
        case, blocks = data['case'], data['blocks']
        groups = collections.defaultdict(list)
        for block in blocks:
            if block['class'] in arguments.classes:
                groups[(block['class'], block['run'])].append(block)
        by_class = collections.defaultdict(lambda: collections.Counter())
        pages = collections.defaultdict(set)
        for (name, _), items in groups.items():
            stat = by_class[name]
            stat['runs'] += 1
            stat['items'] += len(items)
            if len(items) == 1:
                stat['len1'] += 1
            for block in items:
                pages[name].add(block['page'])
            values = [b['value'][2] for b in items if b['value']]
            if values:
                if values[0] != 1 and items[0]['value'] and items[0]['value'][0] == 'digit':
                    stat['start'] += 1
                if any(b - a != 1 for a, b in zip(values, values[1:])):
                    stat['gaps'] += 1
                if any(b < a for a, b in zip(values, values[1:])):
                    stat['desc'] += 1
            # A run another block interrupts: consecutive items are not adjacent in the flow,
            # so wrapping the run in one element would move the intervening block.
            flows = [b['flow'] for b in items]
            if any(b - a != 1 for a, b in zip(flows, flows[1:])):
                stat['split'] += 1
        for name in sorted(by_class):
            stat = by_class[name]
            print(f'{case:40s} {name:22s} {stat["runs"]:5d} {stat["items"]:6d} '
                  f'{len(pages[name]):5d} {stat["start"]:7d} {stat["gaps"]:5d} '
                  f'{stat["desc"]:5d} {stat["len1"]:5d} {stat["split"]:5d}')
            for field in ('runs', 'items', 'start', 'gaps', 'desc', 'len1', 'split'):
                grand[(name, field)] += stat[field]
    print()
    for name in sorted({n for n, _ in grand}):
        print(f'{"ALL":40s} {name:22s} {grand[(name, "runs")]:5d} '
              f'{grand[(name, "items")]:6d} {"":5s} {grand[(name, "start")]:7d} '
              f'{grand[(name, "gaps")]:5d} {grand[(name, "desc")]:5d} '
              f'{grand[(name, "len1")]:5d} {grand[(name, "split")]:5d}')


if __name__ == '__main__':
    main()
