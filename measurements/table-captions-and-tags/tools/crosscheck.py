import json, re, sys
"""usage: crosscheck.py survey.json converted.epub  compare each tagged table's rows with the emitted tables' rows."""
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from check_corpus_content import read_pages
pages, _ = read_pages(sys.argv[2])
def key(s): return re.sub(r'[\s\-‐]', '', s)
for table in json.load(open(sys.argv[1])):
    for page in table['pages']:
        grids = pages.get(page, {}).get('tables', [])
        tagged_rows = [row for row in table['rows'] if any(c['lines'] for c in row)]
        print(f'page {page}: tagged rows {len(table["rows"])}, cells {sum(len(r) for r in table["rows"])}; emitted tables {len(grids)}',
              '' if not grids else f'rows {len(grids[0]["cells"])} x cols {len(grids[0]["cells"][0])}, header rows {grids[0]["headerRows"]}')
        if not grids:
            continue
        # Expanded colspans repeat a cell's text in the grid; keep one copy of each written cell.
        emitted = []
        for g in grids:
            for index, row in enumerate(g['cells']):
                starts = sorted(start for r, start, _ in g['spans'] if r == index)
                emitted.append(key(''.join(row[start] for start in starts)))
        unmatched = []
        # A table continued across pages is checked against the emitted tables of all its pages.
        if len(table['pages']) > 1:
            emitted = []
            for other in table['pages']:
                for g in pages.get(other, {}).get('tables', []):
                    for index, row in enumerate(g['cells']):
                        starts = sorted(start for r, start, _ in g['spans'] if r == index)
                        emitted.append(key(''.join(row[start] for start in starts)))
        for row in table['rows']:
            text = key(''.join(' '.join(c['lines']) for c in row))
            if text and text not in emitted:
                unmatched.append(' | '.join(' / '.join(c['lines'])[:40] for c in row))
        order = [key(''.join(' '.join(c['lines']) for c in row)) for row in table['rows']]
        order = [o for o in order if o in emitted]
        positions = [emitted.index(o) for o in order]
        print('   rows matched', len(order), 'unmatched', len(unmatched), 'in order', positions == sorted(positions))
        for u in unmatched[:6]:
            print('     unmatched tagged row:', u)
