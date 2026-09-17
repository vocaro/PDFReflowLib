#!/usr/bin/env python3
"""usage: wsdiff.py <base-epub-text.tsv> <cand-epub-text.tsv>  compares epubtext.py dumps: block counts, blocks that differ,
and blocks that differ once all whitespace is removed (printed)."""
import re, sys
base = [l.rstrip('\n').split('\t', 1) for l in open(sys.argv[1], encoding='utf-8')]
cand = [l.rstrip('\n').split('\t', 1) for l in open(sys.argv[2], encoding='utf-8')]
print('blocks', len(base), len(cand))
changed = sum(1 for a, b in zip(base, cand) if a != b)
squeeze = lambda s: re.sub(r'\s+', '', s)
other = [(a, b) for a, b in zip(base, cand) if squeeze(a[1]) != squeeze(b[1]) or a[0] != b[0]]
print('changed blocks', changed, 'non-whitespace changes', len(other))
for a, b in other[:20]:
    print('  base:', a[1][:200]); print('  cand:', b[1][:200])
