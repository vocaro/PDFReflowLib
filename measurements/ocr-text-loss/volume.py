#!/usr/bin/env python3
"""Per-compile OCR volume (#116): lines, tokens, Vision word and transcript counts per book.

usage: volume.py <runs dir> <name>... [--pages BOOK]

With --pages it prints per-page line counts for BOOK across the named compiles.
"""
import json
import sys


def load(runs, name, book):
    try:
        return {r['page']: r for r in map(json.loads, open(f'{runs}/{name}-{book}.jsonl'))}
    except FileNotFoundError:
        return None


def main():
    args = sys.argv[1:]
    pages_book = None
    if '--pages' in args:
        i = args.index('--pages')
        pages_book = args[i + 1]
        del args[i:i + 2]
    runs, names = args[0], args[1:]
    if pages_book:
        data = {n: load(runs, n, pages_book) for n in names}
        pages = sorted({p for d in data.values() if d for p in d})
        print('page ' + ' '.join(f'{n:>10}' for n in names))
        for p in pages:
            print(f'{p:>4} ' + ' '.join(f'{len(data[n][p]["lines"]) if data[n] and p in data[n] else "-":>10}'
                                        for n in names))
        return
    for name in names:
        fingerprint = '?'
        try:
            for line in open(f'{runs}/{name}-cache.jsonl'):
                fingerprint = json.loads(line)['cache']['programsSHA256'][:16]
        except FileNotFoundError:
            pass
        for book in ('census', 'cdc', 'warren', 'warren-sample', 'bluebook', 'flag', 'jres'):
            d = load(runs, name, book)
            if d is None:
                continue
            lines = sum(len(r['lines']) for r in d.values())
            tokens = sum(len(l['text'].split()) for r in d.values() for l in r['lines'])
            words = sum(r['words'] for r in d.values())
            chars = sum(r['transcriptCharacters'] for r in d.values())
            print(f'{name} {fingerprint} {book}: pages {len(d)} lines {lines} tokens {tokens} '
                  f'vision words {words} transcript chars {chars}')


if __name__ == '__main__':
    main()
