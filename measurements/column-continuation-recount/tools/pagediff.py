"""Per-page block diff of two EPUBs (headings, paragraphs, list items, images).

usage: pagediff.py <worktree> base.epub cand.epub [--width N]
"""
import difflib
import sys

sys.path.insert(0, sys.argv[1] + '/tools')
from check_corpus_content import read_pages  # noqa: E402

width = int(sys.argv[sys.argv.index('--width') + 1]) if '--width' in sys.argv else 160
base, _ = read_pages(sys.argv[2], max_uncompressed_bytes=4 << 30, max_entries=100000)
cand, _ = read_pages(sys.argv[3], max_uncompressed_bytes=4 << 30, max_entries=100000)


def items(page):
    if not page:
        return []
    out = ['H ' + h for h in page['headings']]
    out += ['P ' + p for p in page['paragraphs']]
    out += ['L ' + p for p in page['listItems']]
    return out


changed = []
for n in sorted(set(base) | set(cand)):
    b, c = base.get(n), cand.get(n)
    keys = ('text', 'headings', 'paragraphs', 'listItems')
    same = b and c and all(b[k] == c[k] for k in keys) and len(b['images']) == len(c['images'])
    if same:
        continue
    changed.append(n)
    print(f'=== page {n}: images {len(b["images"]) if b else 0} -> {len(c["images"]) if c else 0}; '
          f'words {len((b or {}).get("text", "").split())} -> {len((c or {}).get("text", "").split())}')
    for line in difflib.unified_diff(items(b), items(c), lineterm='', n=0):
        if line.startswith(('---', '+++', '@@')):
            continue
        print('  ' + line[:width])
print('changed pages:', changed)
