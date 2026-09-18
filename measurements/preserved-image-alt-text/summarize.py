#!/usr/bin/env python3
"""Count the survey's preserved images by book and kind (#187).

usage: summarize.py <survey-directory>   (one `<pdf basename>.tsv` per book from survey.swift)
"""
import collections
import pathlib
import sys

# Corpus ids for the cached file names; the two non-English books are not surveyed.
CASES = {
    'faa-h-8083-25c': 'faa-phak-8083-25c',
    'Beginning_and_Intermediate_Algebra': 'wallace-algebra-2010',
    'GPO-WARRENCOMMISSIONREPORT': 'gpo-warren-1964',
    'GPO-911REPORT': 'gpo-911-2004',
    'the-fed-explained': 'fed-explained-2021',
    'DGA': 'dga-2025-2030',
    'noaa_61592_DS1': 'noaa-nca5-2023',
    'CDOC-108hdoc97': 'gpo-our-flag-2003',
    'CIA-UAP-015-Project_Blue_Book_Special_Report_No_14': 'cia-blue-book-14-1955',
    'cdc_6023_DS1': 'cdc-zombie-pandemic-2011',
    'jresv82n3p173_A1b': 'nbs-jres-geltman-1977',
    '2311.07842v1': 'arxiv-replay-clocks-2023',
    'mcs2025-copper': 'usgs-mcs2025-copper',
    '22-451_7m58': 'scotus-loper-bright-2024',
    'rrs2002-01': 'census-rrs2002-01',
    'complaint_for_a_civil_case': 'uscourts-pro-se-1-2016',
    '20200002975': 'ntrs-20200002975-gwl-2020',
    'November-December2012': 'usda-ars-agresearch-2012-11',
    '20190030725': 'ntrs-20190030725-dasc-2019',
    '20180003024': 'ntrs-20180003024-earthdata-slides-2018',
    'THM-Close-Out-Report-and-Exec-Summ-for-STI-Review': 'ntrs-20210020887-techport-thm-2021',
}
KINDS = ('equation', 'table', 'listing', 'artwork', 'text', 'unsupported')


def main():
    root = pathlib.Path(sys.argv[1])
    total = collections.Counter()
    print('| Document | ' + ' | '.join(KINDS) + ' | captioned | art: raster | art: vector |')
    print('| --- |' + ' ---: |' * (len(KINDS) + 3))
    for path in sorted(root.glob('*.tsv'), key=lambda p: CASES.get(p.stem, p.stem)):
        counts = collections.Counter()
        for line in path.read_text().splitlines():
            fields = line.split('\t')
            if len(fields) < 9:
                continue
            counts[fields[2]] += 1
            if fields[3] == 'captioned':
                counts['captioned'] += 1
            if fields[2] == 'artwork':
                counts['art-' + fields[4]] += 1
        total.update(counts)
        print(f'| `{CASES.get(path.stem, path.stem)}` | '
              + ' | '.join(str(counts[k]) for k in KINDS)
              + f" | {counts['captioned']} | {counts['art-raster']} | {counts['art-vector']} |")
    print('| **all** | ' + ' | '.join(f'**{total[k]}**' for k in KINDS)
          + f" | **{total['captioned']}** | **{total['art-raster']}** | **{total['art-vector']}** |")


if __name__ == '__main__':
    main()
