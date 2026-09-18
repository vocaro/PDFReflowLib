"""Summarize a survey-all.sh run for #176 and write letterless-pages.tsv.

usage: python3 summarize.py <survey directory> [tsv]

Prints the English page count, every page whose text layer holds no letter with the rows the ink
test reads there, and which of them the image-only rule would recognize.
"""
import glob
import json
import os
import sys

ENGLISH = {'slides', 'dga', 'nbs', 'flag', 'usgs', 'prose1', 'nasa', 'dasc', 'techport', 'agresearch',
           'census', 'replay', 'loper', 'cdc', 'fed', '911', 'faa', 'algebra', 'bluebook', 'noaa', 'warren'}
COLUMNS = ['book', 'page', 'lines', 'characters', 'blank', 'imageBacked', 'crops', 'darkFraction',
           'inkThreshold', 'textRows', 'uncoveredRows', 'ruleTextRows', 'ruleUncoveredRows', 'text']


def main(directory, tsv=None):
    english = letterless = 0
    rows = []
    for path in sorted(glob.glob(os.path.join(directory, '*.jsonl'))):
        book = os.path.basename(path)[:-6]
        for record in (json.loads(line) for line in open(path)):
            if book in ENGLISH:
                english += 1
            if record['letters']:
                continue
            letterless += 1
            ink = [i for i in record['ink'] if i['dpi'] == 180.0]
            if not ink:  # a blank page is never rendered
                continue
            ink = ink[0]
            rows.append([book, record['page'], record['lines'], record['characters'],
                         int(record['blank']), int(record['imageBacked']), record['crops'],
                         '%.3f' % ink['darkFraction'], ink['threshold'],
                         ink['textRows'], ink['uncoveredRows'],
                         ink['ruleTextRows'], ink['ruleUncoveredRows'],
                         record['text'].replace('\n', '\\n').replace('\t', ' ')[:60]])
    rows.sort(key=lambda row: (row[0], row[1]))
    print('English pages surveyed:', english)
    print('letter-less text layers:', letterless, '| rendered at 180 DPI:', len(rows))
    header = '%-9s %4s %5s %5s %5s %6s  %s'
    print(header % ('book', 'page', 'lines', 'chars', 'imgBk', 'dark', 'rows/uncovered -> rule | text'))
    for row in rows:
        print('%-9s %4d %5d %5d %5d %6s  %3d/%-3d -> %3d/%-3d | %s'
              % (row[0], row[1], row[2], row[3], row[5], row[7], row[9], row[10], row[11], row[12], row[13]))
    recognized = [(row[0], row[1]) for row in rows if row[12] >= 2 and not row[5]]
    print('recognized by the rule (>= 2 uncovered rows, not image-backed):', recognized)
    if tsv:
        with open(tsv, 'w') as out:
            out.write('\t'.join(COLUMNS) + '\n')
            for row in rows:
                out.write('\t'.join(str(value) for value in row) + '\n')
        print(len(rows), 'rows ->', tsv)


if __name__ == '__main__':
    main(*sys.argv[1:])
