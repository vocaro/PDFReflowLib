"""List-item joins: a base list item extended by a base paragraph in the candidate.

usage: listjoins.py <worktree> base.epub cand.epub out.json pages...
"""
import json
import sys

sys.path.insert(0, sys.argv[1] + '/tools')
from check_corpus_content import read_pages  # noqa: E402

b, _ = read_pages(sys.argv[2], max_uncompressed_bytes=4 << 30, max_entries=100000)
c, _ = read_pages(sys.argv[3], max_uncompressed_bytes=4 << 30, max_entries=100000)
joins = []
for n in map(int, sys.argv[5:]):
    old = [l for l in b[n]['listItems'] if l not in c[n]['listItems']][0]
    para = [p for p in b[n]['paragraphs'] if p not in c[n]['paragraphs']][0]
    joins.append({'page': n, 'end': old[-90:], 'next': para[:90], 'order': 0})
    print(n, '…' + old[-50:], '‖', para[:50])
json.dump({'joins': joins}, open(sys.argv[4], 'w'))
