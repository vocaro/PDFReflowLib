#!/usr/bin/env python3
"""Table regions of the first recognition and the kept band retry, per page (#129).

usage: table_regions.py <probe dump.jsonl> [--text]

For each page whose retry is kept: table counts and page-area share in each pass, the retry tables
that overlap no first-pass table ("new"), and the words each pass recognized inside those new
regions (lines whose center lies inside), with the share of alphabetic words found in
/usr/share/dict/words as a rough readability signal.
"""
import json
import re
import sys

WORDS = {w.strip().lower() for w in open('/usr/share/dict/words')}


def rect(b):
    return (b[0], b[1], b[0] + b[2], b[1] + b[3])


def intersects(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def inside(line, region):
    x0, y0, x1, y1 = rect(line['box'])
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return region[0] <= cx <= region[2] and region[1] <= cy <= region[3]


def area(rs):
    return sum((r[2] - r[0]) * (r[3] - r[1]) for r in rs)


def readable(words):
    alpha = [re.sub(r'[^a-z]', '', w.lower()) for w in words]
    alpha = [w for w in alpha if len(w) >= 3]
    return (sum(w in WORDS for w in alpha) / len(alpha)) if alpha else None


def main():
    text = '--text' in sys.argv
    for raw in open(sys.argv[1]):
        r = json.loads(raw)
        if not r.get('retryKept'):
            if r.get('flagged'):
                print(f"p{r['page']}: flagged, retry not kept")
            continue
        first = [rect(t) for t in r['first']['tables']]
        retry = [rect(t) for t in r['retry']['tables']]
        new = [t for t in retry if not any(intersects(t, f) for f in first)]
        fw = [w for l in r['first']['lines'] for w in l['text'].split()]
        rw = [w for l in r['retry']['lines'] for w in l['text'].split()]
        fin = [w for l in r['first']['lines'] if any(inside(l, t) for t in new) for w in l['text'].split()]
        rin = [w for l in r['retry']['lines'] if any(inside(l, t) for t in new) for w in l['text'].split()]
        fout = [w for l in r['first']['lines'] if not any(inside(l, t) for t in first) for w in l['text'].split()]
        rout = [w for l in r['retry']['lines'] if not any(inside(l, t) for t in retry) for w in l['text'].split()]
        rkeepfirst = [w for l in r['retry']['lines'] if not any(inside(l, t) for t in first) for w in l['text'].split()]
        fmt = lambda v: '-' if v is None else f'{v:.2f}'
        print(f"p{r['page']}: tables first {len(first)} ({area(first):.2f}) retry {len(retry)} ({area(retry):.2f}) "
              f"new {len(new)} ({area(new):.2f}) | words first {len(fw)} retry {len(rw)} | outside own tables: "
              f"first {len(fout)} retry {len(rout)} retry-outside-first-tables {len(rkeepfirst)} | in new tables: "
              f"first {len(fin)} ({fmt(readable(fin))}) retry {len(rin)} ({fmt(readable(rin))})")
        if text and new:
            print('   first:', ' '.join(fin[:40]))
            print('   retry:', ' '.join(rin[:40]))


if __name__ == '__main__':
    main()
