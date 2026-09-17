"""Join boundaries gained or lost between two EPUBs of the same book.

usage: boundaries.py base.epub cand.epub [--json out.json]
A boundary is the end of one text block (P, R or C) and the start of the next text block in reading
order. It is gained when the candidate holds a block containing the tail of the first joined to the
head of the second (with a space, nothing, or a removed line-end hyphen), and lost the other way round.
"""
import json
import sys

exec(open(__file__.replace('boundaries.py', 'recount.py')).read().split('def main')[0])


def joins(first, second):
    """Boundaries of `first` whose two sides sit in one block of `second`."""
    texts = [b[1] for b in second if b[0] in 'PRC']
    whole = set(texts)
    units = [(i, b) for i, b in enumerate(first) if b[0] in 'PRC' and b[1]]
    found = []
    for (i, pb), (j, qb) in zip(units, units[1:]):
        if pb[1] in whole and qb[1] in whole:
            continue
        tail, head = pb[1][-50:], qb[1][:50]
        forms = [tail + ' ' + head, tail + head] + ([tail[:-1] + head] if tail.endswith('-') else [])
        if any(form in text for text in texts for form in forms):
            found.append({'end_page': pb[3], 'next_page': qb[2], 'kinds': pb[0] + qb[0],
                          'between': ''.join(b[0] for b in first[i + 1:j]),
                          'end': pb[1][-100:], 'next': qb[1][:100]})
    return found


base, cand = blocks(sys.argv[1]), blocks(sys.argv[2])
gained, lost = joins(base, cand), joins(cand, base)
print(len(gained), 'gained,', len(lost), 'lost')
for sign, items in (('+', gained), ('-', lost)):
    for g in items:
        print(f"{sign} p{g['end_page']}->{g['next_page']} {g['kinds']} [{g['between']}] "
              f"…{g['end'][-55:]!r} ‖ {g['next'][:55]!r}")
if '--json' in sys.argv:
    json.dump({'gained': gained, 'lost': lost}, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)
