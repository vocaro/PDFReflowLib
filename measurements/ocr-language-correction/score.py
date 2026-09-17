#!/usr/bin/env python3
"""Score probe transcriptions against ground-truth passages (#108 item 1).

usage: score.py <ground-truth.json> <runs dir> <set>... [--misses]

Each passage's tokens are compared with the whole page's OCR tokens (one setting, one model set)
as multisets, in three classes:
  numbers  digit runs with an optional decimal part, from tokens without letters (11/21/54 is
           11, 21, 54; 685-687 is 685, 687; 59,315 is 59, 315 in both truth and OCR)
  codes    whitespace tokens, edge punctuation stripped, containing both letters and digits
           (rnkswp05, IL1, A138, add01_sw)
  words    alphabetic tokens of two or more letters, case-sensitive
Recall = matched / ground-truth count. `lost` counts ground-truth tokens matched with correction off
but not on; `gained` the reverse. Passages not covering a whole page can over-count repeated tokens.
"""
import json
import re
import sys
from collections import Counter

EDGE = re.compile(r"^[^\w]+|[^\w]+$")


def tokens(text):
    numbers, codes, words = Counter(), Counter(), Counter()
    for t in text.split():
        t = EDGE.sub('', t)
        if re.search(r'[A-Za-z]', t):
            if re.search(r'\d', t):
                codes[t] += 1
        else:
            numbers.update(re.findall(r'\d+(?:\.\d+)?', t))
    for w in re.findall(r'[A-Za-z]{2,}', text):
        words[w] += 1
    return {'numbers': numbers, 'codes': codes, 'words': words}


def main():
    args = [a for a in sys.argv[1:] if a != '--misses']
    misses = '--misses' in sys.argv
    truth = json.load(open(args[0]))['passages']
    runs, sets = args[1], args[2:]
    totals = {}
    for name in sets:
        pages = {}
        for book in {p['book'] for p in truth}:
            for line in open(f'{runs}/{name}-{book}.jsonl'):
                r = json.loads(line)
                pages[(book, r['page'], r['correction'])] = '\n'.join(r['lines'])
        for p in truth:
            gt = tokens(p['text'])
            out = []
            for cls in ('numbers', 'codes', 'words'):
                n = sum(gt[cls].values())
                if not n:
                    continue
                got = {}
                for c in (False, True):
                    ocr = tokens(pages[(p['book'], p['page'], c)])[cls]
                    got[c] = gt[cls] & ocr
                lost = got[False] - got[True]
                gained = got[True] - got[False]
                m_off, m_on = sum(got[False].values()), sum(got[True].values())
                key = (name, p['book'], cls)
                t = totals.setdefault(key, [0, 0, 0])
                t[0] += n; t[1] += m_off; t[2] += m_on
                out.append(f"{cls} {m_off}/{n} -> {m_on}/{n} (lost {sum(lost.values())}, gained {sum(gained.values())})")
                if misses and (lost or gained):
                    out.append(f"    lost {dict(lost)} gained {dict(gained)}")
            print(f"{name} {p['id']}: " + '; '.join(o for o in out if not o.startswith('    ')))
            for o in out:
                if o.startswith('    '):
                    print(o)
    print('\nset\tbook\tclass\tgt\toff\ton\toff%\ton%')
    for (name, book, cls), (n, a, b) in sorted(totals.items()):
        print(f"{name}\t{book}\t{cls}\t{n}\t{a}\t{b}\t{100*a/n:.1f}\t{100*b/n:.1f}")


if __name__ == '__main__':
    main()
