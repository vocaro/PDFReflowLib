#!/usr/bin/env python3
"""Compare the base recognition with the retry variants from probe-retry.swift (#116).

usage: retry_summary.py <retry jsonl>... [--diff N]

Per page: lines, uncovered rows / text rows and uncovered fraction for each variant. With --diff N
it also prints up to N base-only and tiles-only lines per page (whitespace-insensitive match
against the other transcript), to show what the bands add or lose.
"""
import json
import re
import sys


def squash(text):
    return re.sub(r'\s', '', text)


def main():
    args = sys.argv[1:]
    diff = 0
    if '--diff' in args:
        i = args.index('--diff')
        diff = int(args[i + 1])
        del args[i:i + 2]
    for path in args:
        totals = {}
        for line in open(path):
            record = json.loads(line)
            variants = {v['name']: v for v in record['variants']}
            cells = []
            for name, v in variants.items():
                c = v['coverage']
                cells.append(f"{name} {v['lines']} {c['uncoveredRows']}/{c['rows']} {c['fraction']:.2f}")
                t = totals.setdefault(name, [0, 0])
                t[0] += v['lines']
                t[1] += c['uncoveredRows']
            print(f"{path.rsplit('/', 1)[-1]} p{record['page']}: " + ' | '.join(cells))
            if diff and variants['base'].get('texts') is not None and variants['tiles'].get('texts') is not None:
                base, tiles = variants['base']['texts'], variants['tiles']['texts']
                base_all, tiles_all = squash(''.join(base)), squash(''.join(tiles))
                only_base = [t for t in base if squash(t) not in tiles_all]
                only_tiles = [t for t in tiles if squash(t) not in base_all]
                print(f'    base-only {len(only_base)}, tiles-only {len(only_tiles)}; '
                      f'characters base {len(base_all)} tiles {len(tiles_all)}')
                for t in only_base[:diff]:
                    print(f'      - {t}')
                for t in only_tiles[:diff]:
                    print(f'      + {t}')
        print('  totals: ' + ' | '.join(f'{n} lines {t[0]} uncovered rows {t[1]}' for n, t in totals.items()))


if __name__ == '__main__':
    main()
