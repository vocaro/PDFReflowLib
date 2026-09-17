#!/usr/bin/env python3
"""Recognized words left outside table regions under candidate table policies for kept retries (#129).

usage: policy_words.py <probe dump.jsonl>

  first   the first recognition alone (tables and lines; the pre-#116 page)
  retry   the retry's lines and tables (458a2e9)
  keep1   the retry's lines with the first recognition's tables
  agree   the retry's lines with those retry tables that overlap a first-recognition table

Counts are words of lines whose center lies outside every table, before layout; tables are the
number of regions. Layout can join or grow regions, so EPUB counts differ (see the record).
"""
import json
import sys


def rect(b):
    return (b[0], b[1], b[0] + b[2], b[1] + b[3])


def intersects(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def outside(lines, tables):
    n = 0
    for line in lines:
        x0, y0, x1, y1 = rect(line['box'])
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        if not any(t[0] <= cx <= t[2] and t[1] <= cy <= t[3] for t in tables):
            n += len(line['text'].split())
    return n


def main():
    totals = {}
    print('page  first(w/t)  retry(w/t)  keep1(w/t)  agree(w/t)')
    for raw in open(sys.argv[1]):
        r = json.loads(raw)
        if not r.get('retryKept'):
            continue
        first = [rect(t) for t in r['first']['tables']]
        retry = [rect(t) for t in r['retry']['tables']]
        agree = [t for t in retry if any(intersects(t, f) for f in first)]
        rows = {
            'first': (outside(r['first']['lines'], first), len(first)),
            'retry': (outside(r['retry']['lines'], retry), len(retry)),
            'keep1': (outside(r['retry']['lines'], first), len(first)),
            'agree': (outside(r['retry']['lines'], agree), len(agree)),
        }
        for k, v in rows.items():
            t = totals.setdefault(k, [0, 0])
            t[0] += v[0]; t[1] += v[1]
        print(f"{r['page']:4}  " + '  '.join(f'{w:5}/{t}' for w, t in rows.values()))
    print('total ' + '  '.join(f'{k} {w}/{t}' for k, (w, t) in totals.items()))


if __name__ == '__main__':
    main()
