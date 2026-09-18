#!/usr/bin/env python3
# usage: blocks.py <epub> <page> [<page> ...] : print each page's blocks (paragraph ids and text)
import sys
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2/tools')
from check_corpus_content import read_pages

pages, _ = read_pages(sys.argv[1], max_entries=20000, max_uncompressed_bytes=4294967296)
for p in sys.argv[2:]:
    page = pages.get(int(p)) or pages.get(p)
    print(f'=== page {p}')
    if not page:
        print('  (missing)')
        continue
    ids = page.get('paragraphIDs', {})
    for key, text in ids.items():
        print(f'  [{key}] {text}')
