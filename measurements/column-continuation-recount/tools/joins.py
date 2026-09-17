"""Classify page changes between two EPUBs: same-page paragraph joins versus other changes.

usage: joins.py <worktree> base.epub cand.epub [--json out.json]
A join is a candidate paragraph equal to base paragraphs P and Q concatenated (space, or a removed
line-end hyphen). Reports each join's P tail and Q head, and every page whose changes are not only joins.
"""
import json
import re
import sys

sys.path.insert(0, sys.argv[1] + '/tools')
from check_corpus_content import read_pages  # noqa: E402

base, _ = read_pages(sys.argv[2], max_uncompressed_bytes=4 << 30, max_entries=100000)
cand, _ = read_pages(sys.argv[3], max_uncompressed_bytes=4 << 30, max_entries=100000)


def joined(p, q, c):
    return c in (p + ' ' + q, p + q) or (p.endswith('-') and c in (p[:-1] + q, p + q))


joins, other = [], []
for n in sorted(set(base) | set(cand)):
    b, c = base.get(n), cand.get(n)
    if not b or not c:
        other.append(n)
        continue
    bp, cp = list(b['paragraphs']), list(c['paragraphs'])
    page_joins = []
    rest_b, rest_c = list(bp), list(cp)
    for text in cp:
        if text in bp:
            continue
        for i, p in enumerate(bp):
            for j, q in enumerate(bp):
                if i != j and joined(p, q, text):
                    page_joins.append({'page': n, 'end': p[-90:], 'next': q[:90], 'order': j - i})
                    if p in rest_b: rest_b.remove(p)
                    if q in rest_b: rest_b.remove(q)
                    if text in rest_c: rest_c.remove(text)
                    break
            else:
                continue
            break
    rest_b = [t for t in rest_b if t not in cp]
    rest_c = [t for t in rest_c if t not in bp]
    same_else = (b['headings'] == c['headings'] and b['listItems'] == c['listItems']
                 and len(b['images']) == len(c['images']))
    joins += page_joins
    if rest_b or rest_c or not same_else:
        other.append(n)
    elif not page_joins and b['text'] != c['text']:
        other.append(n)
print(f'{len(joins)} joins on {len({j["page"] for j in joins})} pages; other changes on {len(other)} pages: {other}')
for j in joins:
    print(f'p{j["page"]} [{j["order"]:+d}] …{j["end"][-60:]} ‖ {j["next"][:60]}…')
if '--json' in sys.argv:
    json.dump({'joins': joins, 'other': other}, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)
