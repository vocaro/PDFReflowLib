"""summarize.py <book>: census tables for census/<book>-base.tsv and -cand.tsv, the anchors each rejected
(census/<book>-*.samples, classified as #75's samples.py did), and every page whose tag status changed."""
import collections, csv, sys
from pathlib import Path
here = Path(__file__).resolve().parent.parent / 'census'
book = sys.argv[1]

def load(label):
    return {int(r['page']): r for r in csv.DictReader(open(here / f'{book}-{label}.tsv'), delimiter='\t')}

def status(r):
    if r['validates'] == 'false': return 'tree validation'
    if r['applies'].startswith('notAttempted'): return r['applies']
    if r['pageReason'] != '-': return 'page invalid: ' + r['pageReason'].split('@')[0]
    return 'all groups apply' if r['applies'] == 'all' else 'some groups rejected'

def samples(label):
    c = collections.Counter(); pages = collections.defaultdict(set)
    path = here / f'{book}-{label}.samples'
    for line in open(path, errors='replace'):
        parts = line.rstrip('\n').split('\t')
        page, kind, length, hexbytes = int(parts[1]), parts[2], int(parts[4][3:]), parts[5]
        if length and set(bytes.fromhex(hexbytes)) <= {0x20} and length == len(hexbytes) // 2:
            cls = 'spaces only'
        elif length <= 3: cls = 'short show (<=3 bytes)'
        else: cls = 'text run'
        key = f'{kind.split("(")[0]} / {cls}'
        c[key] += 1; pages[key].add(page)
    return c, pages

rows = {label: load(label) for label in ('base', 'cand')}
for label, data in rows.items():
    pages = collections.Counter(status(r) for r in data.values())
    groups = collections.Counter(); gpages = collections.Counter(); blank = collections.Counter(); bpages = collections.Counter()
    for r in data.values():
        for kv in ([] if r['groupReasons'] == '-' else r['groupReasons'].split(',')):
            k, v = kv.split('='); groups[k] += int(v); gpages[k] += 1
        for kv in ([] if r['blank'] == '-' else r['blank'].split(',')):
            k, v = kv.split('='); blank[k] += int(v); bpages[k] += 1
    tagged = sum(int(r['taggedLines']) for r in data.values()); lines = sum(int(r['lines']) for r in data.values())
    print(f'== {book} {label}: {len(data)} tagged pages, {tagged}/{lines} lines tagged')
    for k, v in sorted(pages.items()): print(f'   pages  {k}: {v}')
    for k, v in groups.most_common(): print(f'   groups {k}: {v} groups on {gpages[k]} pages')
    for k, v in blank.most_common(): print(f'   ignored space-only shows {k}: {v} on {bpages[k]} pages')
    c, p = samples(label)
    for k, v in c.most_common(): print(f'   anchors {k}: {v} on {len(p[k])} pages {sorted(p[k])[:12]}')
b, a = rows['base'], rows['cand']
print('== changed pages (page: base status, rejected groups, tagged lines -> candidate)')
for n in sorted(b):
    x, y = b[n], a[n]
    if (status(x), x['rejectedGroups'], x['taggedLines'], x['groupReasons']) != (status(y), y['rejectedGroups'], y['taggedLines'], y['groupReasons']):
        print(f'   {n}: {status(x)} rej={x["rejectedGroups"]} tagged={x["taggedLines"]}/{x["lines"]} [{x["groupReasons"]}] -> '
              f'{status(y)} rej={y["rejectedGroups"]} tagged={y["taggedLines"]} [{y["groupReasons"]}] blank[{y["blank"]}]')
