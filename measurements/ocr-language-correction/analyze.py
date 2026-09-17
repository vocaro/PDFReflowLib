#!/usr/bin/env python3
"""Summarize language-correction probe runs (#108 item 1).

usage: analyze.py <runs dir> <set>... [--changes out.tsv]

For each model set and book: dictionary-word rate (share of lowercase alphabetic words of four or
more letters, surrounding punctuation stripped, found in /usr/share/dict/words, as #94 measured),
the same rate over all alphabetic words of four or more letters (case-folded), line counts, and a
token-level diff of correction off -> on per page (difflib over whitespace tokens of the page).
"""
import difflib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

BOOKS = ['census', 'cdc', 'bluebook', 'warren']
WORDS = {w.strip().lower() for w in open('/usr/share/dict/words')}
STRIP = re.compile(r"^[^\w]+|[^\w]+$")


def words(text):
    return [STRIP.sub('', t) for t in text.split()]


def dict_counts(lines):
    lower = found_lower = alpha = found_alpha = 0
    for w in words(' '.join(lines)):
        if len(w) >= 4 and w.isalpha() and w.isascii():
            alpha += 1
            found_alpha += w.lower() in WORDS
            if w.islower():
                lower += 1
                found_lower += w in WORDS
    return lower, found_lower, alpha, found_alpha


def load(runs, name, book):
    path = Path(runs) / f'{name}-{book}.jsonl'
    if not path.exists():
        return None
    pages = defaultdict(dict)
    for line in path.open():
        r = json.loads(line)
        pages[r['page']][r['correction']] = r['lines']
    return pages


def main():
    args = sys.argv[1:]
    changes_out = None
    if '--changes' in args:
        i = args.index('--changes')
        changes_out = args[i + 1]
        del args[i:i + 2]
    runs, sets = args[0], args[1:]
    rows = []
    for name in sets:
        for book in BOOKS:
            pages = load(runs, name, book)
            if pages is None:
                continue
            totals = {False: [0, 0, 0, 0], True: [0, 0, 0, 0]}
            lines = {False: 0, True: 0}
            changed_pages = 0
            ops = 0
            numeric_ops = 0
            for page, by in sorted(pages.items()):
                for c in (False, True):
                    for k, v in enumerate(dict_counts(by[c])):
                        totals[c][k] += v
                    lines[c] += len(by[c])
                a = ' '.join(by[False]).split()
                b = ' '.join(by[True]).split()
                if by[False] != by[True]:
                    changed_pages += 1
                for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
                    if tag == 'equal':
                        continue
                    ops += 1
                    before, after = ' '.join(a[i1:i2]), ' '.join(b[j1:j2])
                    numeric = bool(re.search(r'\d', before + after))
                    numeric_ops += numeric
                    context = ' '.join(a[max(0, i1 - 4):i1]) + ' [...] ' + ' '.join(a[i2:i2 + 4])
                    rows.append((name, book, page, tag, before, after, int(numeric), context))
            def rate(t, k):
                return 100 * t[k + 1] / t[k] if t[k] else float('nan')
            print(f"{name:7} {book:9} pages={len(pages):3} changedPages={changed_pages:3} "
                  f"lines off/on={lines[False]}/{lines[True]} diffOps={ops} numericOps={numeric_ops} "
                  f"dictLower off={rate(totals[False], 0):.2f}% ({totals[False][1]}/{totals[False][0]}) "
                  f"on={rate(totals[True], 0):.2f}% ({totals[True][1]}/{totals[True][0]}) "
                  f"dictAll off={rate(totals[False], 2):.2f}% on={rate(totals[True], 2):.2f}%")
    if changes_out:
        with open(changes_out, 'w') as f:
            f.write('set\tbook\tpage\top\toff\ton\tnumeric\tcontext\n')
            for r in rows:
                f.write('\t'.join(str(x).replace('\t', ' ') for x in r) + '\n')


if __name__ == '__main__':
    main()
