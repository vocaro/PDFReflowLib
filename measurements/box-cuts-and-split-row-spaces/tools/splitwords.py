#!/usr/bin/env python3
# usage: splitwords.py <epub> : word pairs `a b` whose join `ab` the book prints elsewhere and whose
# second half the book never prints alone (candidates for a broken word left open).
import sys, re, collections
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2/tools')
from check_corpus_content import read_pages
pages, _ = read_pages(sys.argv[1], max_entries=20000, max_uncompressed_bytes=4294967296)
words = collections.Counter()
texts = {}
for number, page in pages.items():
    tokens = re.findall(r"[A-Za-z]+", page['text'])
    texts[number] = tokens
    words.update(t.lower() for t in tokens)
for number, tokens in sorted(texts.items()):
    for a, b in zip(tokens, tokens[1:]):
        joined = (a + b).lower()
        if words[joined] >= 1 and words[b.lower()] <= 1 and len(b) >= 2:
            print(number, a, b)
