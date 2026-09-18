#!/usr/bin/env python3
# usage: crossjoins.py <base.epub> <cand.epub> : paragraphs continued across a page marker in one EPUB
# but not the other, by the junction text (the end on page N and the start on page N+k).
import sys
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2/tools')
from check_corpus_content import read_pages
limits = dict(max_entries=20000, max_uncompressed_bytes=4294967296)

def junctions(path):
    pages, markers = read_pages(path, **limits)
    found = set()
    seen = {}
    for number in markers:
        for key, text in pages[number].get('paragraphIDs', {}).items():
            if key in seen:
                page, before = seen[key]
                found.add((page, number, ' '.join(before.split()[-14:]), ' '.join(text.split()[:10])))
            seen[key] = (number, text)
    return found

base, cand = junctions(sys.argv[1]), junctions(sys.argv[2])
for label, items in (('+ new', cand - base), ('- lost', base - cand)):
    for page, number, end, start in sorted(items):
        print(f'{label} {page}->{number}: …{end} | {start}…')
