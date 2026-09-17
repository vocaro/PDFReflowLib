"""Captions (`Figure|Table N` paragraphs) that end without terminal punctuation, with the next text block.
usage: captions.py book.epub"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from recount import blocks, open_end  # noqa: E402

bl = blocks(sys.argv[1])
n = 0
for i, (k, t, p0, p1) in enumerate(bl):
    if k != 'C' or not open_end(t):
        continue
    j = i + 1
    while j < len(bl) and bl[j][0] in 'IB':
        j += 1
    nxt = bl[j] if j < len(bl) else ('', '', 0, 0)
    n += 1
    print(f'p{p1} …{t[-60:]!r} ‖ {nxt[0]} {nxt[1][:60]!r}')
print('open captions:', n)
