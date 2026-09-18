#!/usr/bin/env python3
# usage: pagediff.py <base.epub> <cand.epub> <compare.json> : for every changed page, the paragraphs
# only in the baseline (-) and only in the candidate (+), and whether the page's words changed.
import sys, json, difflib
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2/tools')
from check_corpus_content import read_pages
limits = dict(max_entries=20000, max_uncompressed_bytes=4294967296)
base, _ = read_pages(sys.argv[1], **limits)
cand, _ = read_pages(sys.argv[2], **limits)
pages = json.load(open(sys.argv[3]))['changedPages']
width = int(sys.argv[4]) if len(sys.argv) > 4 else 220
for p in pages:
    b, c = base.get(p, {}), cand.get(p, {})
    bp, cp = b.get('paragraphs', []), c.get('paragraphs', [])
    bw, cw = b.get('text', '').split(), c.get('text', '').split()
    same_words = sorted(bw) == sorted(cw)
    print(f'=== page {p}: words {"same multiset" if same_words else "CHANGED"}; paragraphs {len(bp)} -> {len(cp)}')
    if not same_words:
        sm = difflib.SequenceMatcher(None, bw, cw, autojunk=False)
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag != 'equal':
                print(f'   words {tag}: {" ".join(bw[max(0,i1-3):i2+3])!r} -> {" ".join(cw[max(0,j1-3):j2+3])!r}')
    for para in bp:
        if para not in cp:
            print('  -', para[:width])
    for para in cp:
        if para not in bp:
            print('  +', para[:width])
