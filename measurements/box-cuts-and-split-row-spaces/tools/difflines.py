#!/usr/bin/env python3
# usage: difflines.py <id> ... : every product line that differs between base and cand survey TSVs,
# classified as an inserted space, a restored soft hyphen, or other.
import sys, difflib
D = '/private/tmp/claude-501/i177/diag/lines'
for case in sys.argv[1:]:
    base = [l.rstrip('\n').split('\t') for l in open(f'{D}/{case}.base.tsv')]
    cand = [l.rstrip('\n').split('\t') for l in open(f'{D}/{case}.cand.tsv')]
    if len(base) != len(cand):
        print(case, 'LINE COUNT DIFFERS', len(base), len(cand))
    counts = {}
    for b, c in zip(base, cand):
        if b[2] == c[2]:
            continue
        bt, ct = b[2], c[2]
        if ct.replace(' ', '') == bt.replace(' ', '') and len(ct) > len(bt):
            kind = 'space'
            # show each insertion with context
            sm = difflib.SequenceMatcher(None, bt, ct, autojunk=False)
            where = [ct[max(0, j1 - 15):j2 + 15] for tag, i1, i2, j1, j2 in sm.get_opcodes() if tag == 'insert']
        elif ct.replace('­', '') == bt:
            kind = 'softhyphen'
            where = [ct[-30:]]
        else:
            kind = 'other'
            where = [bt, ct]
        counts[kind] = counts.get(kind, 0) + 1
        print(f'{case}\t{b[0]}\t{b[1]}\t{kind}\t' + ' | '.join(w.replace('­', '<SHY>') for w in where))
    print(f'# {case} {counts}', file=sys.stderr)
