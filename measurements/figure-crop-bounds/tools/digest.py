"""Per-page digest of two EPUBs: words, images, tokens lost/gained.

usage: digest.py base.epub cand.epub [--pages] [--out file.json]
"""
import collections
import json
import re
import sys

sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-aaf0cc0e6019a1210/tools')
from check_corpus_content import read_pages  # noqa: E402

base, _ = read_pages(sys.argv[1], max_uncompressed_bytes=4 << 30, max_entries=100000)
cand, _ = read_pages(sys.argv[2], max_uncompressed_bytes=4 << 30, max_entries=100000)


def tokens(text):
    return [t for t in re.findall(r"[A-Za-z0-9][A-Za-z0-9'’-]*", text)]


rows = []
totals = collections.Counter()
for n in sorted(set(base) | set(cand)):
    b, c = base.get(n), cand.get(n)
    bt, ct = tokens(b['text']) if b else [], tokens(c['text']) if c else []
    if b and c and b['text'] == c['text'] and len(b['images']) == len(c['images']):
        continue
    lost = list((collections.Counter(bt) - collections.Counter(ct)).elements())
    gained = list((collections.Counter(ct) - collections.Counter(bt)).elements())
    row = {'page': n, 'words': [len(bt), len(ct)], 'images': [len(b['images']) if b else 0, len(c['images']) if c else 0],
           'lost': lost, 'gainedCount': len(gained), 'textEqual': bool(b and c and b['text'] == c['text'])}
    rows.append(row)
    totals['pages'] += 1
    totals['wordsBase'] += len(bt)
    totals['wordsCand'] += len(ct)
    totals['imagesBase'] += row['images'][0]
    totals['imagesCand'] += row['images'][1]
    totals['lost'] += len(lost)
    if lost:
        totals['pagesWithLost'] += 1
print(dict(totals))
print('book images', sum(len(p['images']) for p in base.values()), '->', sum(len(p['images']) for p in cand.values()))
print('book words', sum(len(tokens(p['text'])) for p in base.values()), '->', sum(len(tokens(p['text'])) for p in cand.values()))
if '--pages' in sys.argv:
    for row in rows:
        print(f"p{row['page']}: words {row['words'][0]}->{row['words'][1]} (+{row['gainedCount']}) images {row['images'][0]}->{row['images'][1]}"
              + (f" LOST {row['lost'][:12]}" if row['lost'] else ''))
if '--out' in sys.argv:
    json.dump(rows, open(sys.argv[sys.argv.index('--out') + 1], 'w'), indent=1)
