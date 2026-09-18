#!/usr/bin/env python3
# usage: junctions.py <base.epub> <cand.epub> <page>... : for each baseline paragraph the candidate
# joined into an earlier one on the same page, the candidate's words around the junction.
import sys
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2/tools')
from check_corpus_content import read_pages
base, _ = read_pages(sys.argv[1])
cand, _ = read_pages(sys.argv[2])
for p in map(int, sys.argv[3:]):
    bp, cp = base[p]['paragraphs'], cand[p]['paragraphs']
    for para in bp:
        if para in cp:
            continue
        head = ' '.join(para.split()[:5])
        for joined in cp:
            at = joined.find(head)
            if at > 0:
                before = joined[:at].split()[-7:]
                after = joined[at:].split()[:7]
                print(f'{p}\t{" ".join(before)} | {" ".join(after)}')
