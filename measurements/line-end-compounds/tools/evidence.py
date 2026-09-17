import sys, re, collections
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a098637f805ceba97/tools')
from check_corpus_content import read_pages
# For each logged compound join, count the book's unbroken hyphenated, closed and spaced forms in the baseline EPUB.
label = sys.argv[1]
for case in sys.argv[2:]:
    pages, _ = read_pages(f'/private/tmp/h131/base-{case}/{case}/{case}.epub', max_entries=20000, max_uncompressed_bytes=4294967296)
    text = '\n'.join(p['text'] for p in pages.values())
    seen = set()
    for line in open(f'/private/tmp/h131/log/{label}-{case}.tsv'):
        kind, page, op, left, right = line.rstrip('\n').split('\t')
        a = re.search(r'([A-Za-z]+)-$', left)
        b = re.match(r'([A-Za-z0-9/]+)', right)
        if not a or not b:
            print(case, page, kind, op, repr(left[-15:]), repr(right[:15]), 'shape?'); continue
        l, r = a.group(1), b.group(1)
        if (l, r) in seen: continue
        seen.add((l, r))
        hy = len(re.findall(re.escape(l + '-' + r), text, re.I))
        closed = len(re.findall(r'\b' + re.escape(l + r) + r'\b', text, re.I))
        spaced = len(re.findall(re.escape(l + '- ' + r), text, re.I))
        pre = len(re.findall(r'\b' + re.escape(l) + r'-[A-Za-z0-9]', text, re.I))
        print(f'{case}\tp{page}\t{kind}\t{op}\t{l}-{r}\thyphenated={hy}\tclosed={closed}\tspaced={spaced}\tprefix-uses={pre}')
