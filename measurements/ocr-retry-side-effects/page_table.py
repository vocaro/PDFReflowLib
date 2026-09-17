#!/usr/bin/env python3
"""Per-page EPUB words and images of two evaluations, for every page that differs (#129).

usage: page_table.py <baseline evaluation dir> <candidate evaluation dir> [--pages 1,2,...] [--text N]

Also marks pages whose `ocrUsed` message reports the banded retry in either run and prints totals
over the listed pages. `--text N` prints the first N candidate words of each listed page.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from check_corpus_content import read_pages  # noqa: E402


def load(directory):
    receipt = json.loads((Path(directory) / 'result.json').read_text())
    pages, _ = read_pages(Path(directory) / (receipt['case']['id'] + '.epub'))
    retried = {w['page'] for w in receipt['conversionReport']['warnings']
               if w['code'] == 'ocrUsed' and 'two overlapping bands' in w['message']}
    return pages, retried


def main():
    args = sys.argv[1:]
    text = 0
    if '--text' in args:
        i = args.index('--text'); text = int(args[i + 1]); del args[i:i + 2]
    only = None
    if '--pages' in args:
        i = args.index('--pages'); only = [int(p) for p in args[i + 1].split(',')]; del args[i:i + 2]
    (base, base_retried), (cand, cand_retried) = load(args[0]), load(args[1])
    numbers = only or sorted(set(base) | set(cand))
    totals = [0, 0, 0, 0]
    print('page retried  words base -> cand   images base -> cand')
    for n in numbers:
        b, c = base.get(n, {}), cand.get(n, {})
        bw, cw = len(b.get('text', '').split()), len(c.get('text', '').split())
        bi, ci = len(b.get('images', [])), len(c.get('images', []))
        if only is None and (bw, bi) == (cw, ci) and b.get('text') == c.get('text'):
            continue
        totals = [totals[0] + bw, totals[1] + cw, totals[2] + bi, totals[3] + ci]
        mark = ('B' if n in base_retried else '-') + ('C' if n in cand_retried else '-')
        same = '' if b.get('text') != c.get('text') or (bw, bi) != (cw, ci) else '  (identical)'
        print(f'{n:4} {mark:>7}  {bw:6} -> {cw:<6} {cw - bw:+5}   {bi:3} -> {ci:<3}{same}')
        if text:
            print('      ' + ' '.join(c.get('text', '').split()[:text]))
    print(f'total        {totals[0]:6} -> {totals[1]:<6} {totals[1] - totals[0]:+5}   {totals[2]:3} -> {totals[3]}')


if __name__ == '__main__':
    main()
