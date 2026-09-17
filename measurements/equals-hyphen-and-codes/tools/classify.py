import sys, re, difflib, collections, json
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a473a0f035122cb0e/tools')
import check_corpus_content as c

S = sys.argv[2] if len(sys.argv) > 2 else './'  # directory holding base-<case>/ and cand-<case>/ lane outputs
case = sys.argv[1]
books = {}
for label in ('base', 'cand'):
    r = c.read_pages(S + f'/{label}-{case}/{case}/{case}.epub')
    books[label] = r[0] if isinstance(r, tuple) else r
kinds = collections.Counter()
other = []
for page in sorted(set(books['base']) | set(books['cand'])):
    a = books['base'].get(page, {}).get('text', '').split(' ')
    b = books['cand'].get(page, {}).get('text', '').split(' ')
    if a == b:
        continue
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op == 'equal':
            continue
        old, new = ' '.join(a[i1:i2]), ' '.join(b[j1:j2])
        if re.fullmatch(r'(\S*[A-Za-z])= (\S+)', old) and new in (re.sub(r'= ', '', old), re.sub(r'= ', '-', old)):
            kinds['= break ' + ('removed' if '-' not in new[len(old.split('=')[0]):len(old.split('=')[0]) + 1] else 'kept')] += 1
        elif re.fullmatch(r'(\S*[A-Za-z])= (\S+)', old) and new == old.replace('= ', '- '):
            kinds['= break kept spaced (digit/capital)'] += 1
        elif old.count('- ') >= 1 and new == old.replace('- ', '-'):
            kinds['code join'] += 1
            other.append((page, 'code', old, new))
        elif op == 'insert':
            kinds['inserted (former crop text)'] += 1
            other.append((page, 'insert', old, new[:120]))
        else:
            kinds['other'] += 1
            other.append((page, op, old[:160], new[:160]))
print(dict(kinds))
for row in other:
    print(row)
