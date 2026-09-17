import sys, re, collections
# usage: titlemap.py titles.tsv dump.txt STYLE SIZE [STATUS]
# For each probe title of that style/size, the element kind the dump emits for it (by exact text or prefix).
tsv, dump, style, size = sys.argv[1:5]
status = sys.argv[5] if len(sys.argv) > 5 else None
blocks = []
cur = 0
for l in open(dump):
    l = l.rstrip('\n')
    m = re.match(r'=== page (\d+)', l)
    if m:
        if '(inside)' not in l: cur = int(m.group(1))
        continue
    if ': ' in l:
        kind, text = l.split(': ', 1)
        blocks.append((cur, kind, re.sub(r'\[\[p\d+\]\]', '', text)))
counts = collections.Counter()
for row in open(tsv):
    page, st, tag, sty, sz, x, text = row.rstrip('\n').split('\t')
    if sty != style or sz != size or (status and st != status): continue
    page = int(page)
    kinds = [k for p, k, t in blocks if abs(p - page) <= 1 and t == text]
    kind = kinds[0] if kinds else ('prefix:' + next((k for p, k, t in blocks if abs(p - page) <= 1 and t.startswith(text + ' ')), 'none'))
    counts[(st, tag, kind)] += 1
    print(page, st, tag, kind, text, sep='\t')
for k, v in sorted(counts.items()):
    print('#', v, *k, file=sys.stderr)
