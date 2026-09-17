import sys, difflib, re
# Classifies block-dump differences: hunks whose concatenated text is unchanged (a paragraph
# split into heading + paragraph, or a retag) versus hunks that change text.
a = [l.rstrip('\n') for l in open(sys.argv[1])]
b = [l.rstrip('\n') for l in open(sys.argv[2])]
def body(l): return l.split(': ', 1)[1] if ': ' in l else l
def norm(s): return re.sub(r'\s+', ' ', s).strip()
odd = []; retag = 0; split = 0
for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
    if tag == 'equal': continue
    old = ' '.join(body(x) for x in a[i1:i2] if not x.startswith('==='))
    new = ' '.join(body(x) for x in b[j1:j2] if not x.startswith('==='))
    if norm(old) == norm(new):
        if len(a[i1:i2]) == len(b[j1:j2]): retag += 1
        else: split += 1
        continue
    odd.append((i1, a[i1:i2], b[j1:j2]))
print('text-preserving hunks: retagged', retag, 'split', split, 'other', len(odd))
for i, x, y in odd:
    print('--- base line', i + 1)
    for l in x: print('  <', l[:200])
    for l in y: print('  >', l[:200])
