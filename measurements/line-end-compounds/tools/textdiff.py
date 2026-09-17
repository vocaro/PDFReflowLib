import sys, json, difflib, re
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a098637f805ceba97/tools')
from check_corpus_content import read_pages
# usage: textdiff.py label case
label, case = sys.argv[1], sys.argv[2]
cmp = json.load(open(f'/private/tmp/h131/cmp-{label}-{case}.json'))
fields = cmp['changedPageFields']
base, _ = read_pages(f'/private/tmp/h131/base-{case}/{case}/{case}.epub', max_entries=20000, max_uncompressed_bytes=4294967296)
cand, _ = read_pages(f'/private/tmp/h131/{label}-{case}/{case}/{case}.epub', max_entries=20000, max_uncompressed_bytes=4294967296)
print('changed pages', len(cmp['changedPages']), 'images', len(cmp['changedImages']), 'report', cmp['changedReportFields'], 'nav', cmp['navigationChanged'])
for page in cmp['changedPages']:
    f = fields[str(page)]
    key = page if page in base else str(page)
    a, b = base[key]['text'], cand[key]['text']
    if a == b:
        print(f'p{page}\t{f}\t(text same)')
        continue
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op == 'equal':
            continue
        print(f'p{page}\t{op}\t{a[max(0,i1-25):i2+15]!r} -> {b[max(0,j1-25):j2+15]!r}')
