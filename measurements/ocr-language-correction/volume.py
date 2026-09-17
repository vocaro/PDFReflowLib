#!/usr/bin/env python3
"""Text volume with correction off and on (#108 item 1): does correction drop or reorder text?

usage: volume.py <runs dir> <set>... [--dropped N]

Per set and book: lines, whitespace tokens, tokens with digits and letters, and lines present with
correction off whose whitespace-stripped text occurs nowhere in the correction-on page (and the
reverse). With --dropped N it prints up to N such off-only lines per book.
"""
import json
import re
import sys

BOOKS = ['census', 'cdc', 'bluebook', 'warren']


def main():
    args = sys.argv[1:]
    show = 0
    if '--dropped' in args:
        i = args.index('--dropped')
        show = int(args[i + 1])
        del args[i:i + 2]
    runs, sets = args[0], args[1:]
    for name in sets:
        for book in BOOKS:
            pages = {}
            for line in open(f'{runs}/{name}-{book}.jsonl'):
                r = json.loads(line)
                pages.setdefault(r['page'], {})[r['correction']] = r['lines']
            stats = {c: [0, 0, 0, 0] for c in (False, True)}
            only = {False: [], True: []}
            for page, by in sorted(pages.items()):
                for c in (False, True):
                    toks = ' '.join(by[c]).split()
                    s = stats[c]
                    s[0] += len(by[c]); s[1] += len(toks)
                    s[2] += sum(bool(re.search(r'\d', t)) for t in toks)
                    s[3] += sum(len(re.findall(r'\d', t)) for t in toks)
                    other = re.sub(r'\s', '', ''.join(by[not c]))
                    for text in by[c]:
                        if re.sub(r'\s', '', text) not in other:
                            only[c].append((page, text))
            print(f"{name} {book}: lines {stats[False][0]}->{stats[True][0]}, tokens {stats[False][1]}->{stats[True][1]}, "
                  f"digit tokens {stats[False][2]}->{stats[True][2]}, digits {stats[False][3]}->{stats[True][3]}, "
                  f"off-only lines {len(only[False])}, on-only lines {len(only[True])}")
            for page, text in only[False][:show]:
                print(f"    off-only p{page}: {text}")


if __name__ == '__main__':
    main()
