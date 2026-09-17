import sys, re, collections, os
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a098637f805ceba97/tools')
from check_corpus_content import read_pages

# usage: spaced.py <run-prefix> <out-prefix> case...
prefix, out = sys.argv[1], sys.argv[2]
pat = re.compile(r'(\S{0,25}[^\s\-–—])- (\S{1,25})')
for case in sys.argv[3:]:
    path = f'{prefix}-{case}/{case}/{case}.epub'
    pages, _ = read_pages(path, max_entries=20000, max_uncompressed_bytes=4294967296)
    cls = collections.Counter()
    with open(f'{out}-{case}.txt', 'w') as f:
        for p in sorted(pages, key=lambda x: int(x) if str(x).isdigit() else 0):
            t = pages[p]['text']
            for m in pat.finditer(t):
                r = m.group(2)[0]
                k = 'lower' if r.islower() else 'upper' if r.isupper() else 'digit' if r.isdigit() else 'other'
                cls[k] += 1
                f.write(f"p{p}\t{k}\t{m.group(1)}- {m.group(2)}\n")
    print(case, dict(cls))
