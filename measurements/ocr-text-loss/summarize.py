#!/usr/bin/env python3
"""Summarize replay-coverage output (#116).

usage: summarize.py <replay jsonl>... [--pages] [--rows R] [--fraction F]

Prints, per file, the clean uncovered-fraction distribution, clean pages that would be flagged
under the thresholds, and the detection rate of each simulated loss. `--pages` lists every page.
Thresholds default to the library's; overriding them re-evaluates without rerunning the replay.
"""
import json
import sys


def flagged(metric, rows, fraction):
    return metric['uncoveredRows'] >= rows and metric['fraction'] >= fraction


def quantiles(values):
    values = sorted(values)
    if not values:
        return '-'
    pick = lambda q: values[min(len(values) - 1, int(q * (len(values) - 1) + 0.5))]
    return f'median {pick(0.5):.3f} p90 {pick(0.9):.3f} p99 {pick(0.99):.3f} max {values[-1]:.3f}'


def main():
    args = sys.argv[1:]
    pages = '--pages' in args
    rows, fraction = 8, 0.2
    for flag in ('--rows', '--fraction'):
        if flag in args:
            i = args.index(flag)
            value = args[i + 1]
            del args[i:i + 2]
            if flag == '--rows':
                rows = int(value)
            else:
                fraction = float(value)
    args = [a for a in args if a != '--pages']
    for path in args:
        records = [json.loads(line) for line in open(path)]
        name = path.rsplit('/', 1)[-1]
        with_text = [r for r in records if r['lines'] > 0]
        print(f'{name}: {len(records)} pages, {len(with_text)} with lines; thresholds rows>={rows} fraction>={fraction}')
        print(f'  clean fraction (pages with rows): {quantiles([r["clean"]["fraction"] for r in records if r["clean"]["rows"]])}')
        print(f'  clean uncovered rows: {quantiles([float(r["clean"]["uncoveredRows"]) for r in records])}')
        fp = [r for r in records if flagged(r['clean'], rows, fraction)]
        print(f'  clean pages flagged: {len(fp)} ' + ' '.join(
            f'p{r["page"]}({r["clean"]["uncoveredRows"]}/{r["clean"]["rows"]},{r["clean"]["fraction"]:.2f})' for r in fp))
        for kind in ('block', 'scattered'):
            for share in (0.2, 0.35, 0.5, 0.8):
                sims = [s['metric'] for r in with_text for s in r['simulated']
                        if s['kind'] == kind and s['share'] == share]
                # Only pages where the simulated drop removed text rows matter for detection.
                hit = sum(flagged(m, rows, fraction) for m in sims)
                print(f'  {kind} {share:.2f}: detected {hit}/{len(sims)} '
                      f'(fraction {quantiles([m["fraction"] for m in sims])})')
        if pages:
            for r in records:
                c = r['clean']
                sims = ' '.join(f'{s["kind"][0]}{s["share"]:.2f}:{s["metric"]["uncoveredRows"]}/{s["metric"]["fraction"]:.2f}'
                                + ('*' if flagged(s['metric'], rows, fraction) else '') for s in r['simulated'])
                print(f'  p{r["page"]} lines {r["lines"]} {r["seconds"]:.3f}s rows {c["rows"]} '
                      f'unc {c["uncoveredRows"]} {c["fraction"]:.3f}{"*" if flagged(c, rows, fraction) else ""} | {sims}')


if __name__ == '__main__':
    main()
