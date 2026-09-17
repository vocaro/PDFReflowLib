import sys, difflib
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a098637f805ceba97/tools')
from check_corpus_content import read_pages
base, _ = read_pages(sys.argv[1], max_entries=200000, max_uncompressed_bytes=40 * 2**30)
cand, _ = read_pages(sys.argv[2], max_entries=200000, max_uncompressed_bytes=40 * 2**30)
print('pages', len(base), len(cand))
for key in base:
    a, b = base[key]['text'], cand.get(key, {}).get('text', '')
    if a == b:
        continue
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op != 'equal':
            print(f'p{key}\t{op}\t{a[max(0,i1-30):i2+20]!r} -> {b[max(0,j1-30):j2+20]!r}')
