#!/usr/bin/env python3
"""Threshold sweep over replay-coverage output (#116).

usage: sweep.py <replay dir> [book...]

For each (minimum uncovered rows, minimum uncovered fraction) pair: clean pages flagged per book,
and detection of simulated 50% and 80% losses (block and scattered) pooled over pages that have
recognized lines and are not already flagged clean.
"""
import json
import sys

BOOKS = ['census', 'cdc', 'warren', 'warren-sample', 'jres', 'flag', 'bluebook']


def flagged(m, rows, fraction):
    return m['uncoveredRows'] >= rows and m['fraction'] >= fraction


def main():
    directory = sys.argv[1]
    books = sys.argv[2:] or BOOKS
    data = {b: [json.loads(l) for l in open(f'{directory}/replay-{b}.jsonl')] for b in books}
    print('rows fraction | clean pages flagged | detected: block 0.5, scattered 0.5, block 0.8, scattered 0.8')
    for rows in (5, 8, 12, 16):
        for fraction in (0.2, 0.35, 0.5, 0.6, 0.7):
            fp = ' '.join(f"{b}:{sum(flagged(r['clean'], rows, fraction) for r in data[b])}" for b in books)
            detected = []
            for share in (0.5, 0.8):
                for kind in ('block', 'scattered'):
                    sims = [s['metric'] for b in books for r in data[b]
                            if r['lines'] > 0 and not flagged(r['clean'], rows, fraction)
                            for s in r['simulated'] if s['kind'] == kind and s['share'] == share]
                    detected.append(f'{sum(flagged(m, rows, fraction) for m in sims)}/{len(sims)}')
            print(f'{rows:>2} {fraction:.2f} | {fp} | {" ".join(detected)}')


if __name__ == '__main__':
    main()
