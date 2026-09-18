import sys, re

def load(path):
    pages = {}
    current = None
    for line in open(path, encoding='utf-8', errors='replace'):
        if re.match(r'^\d+\t', line):
            current = int(line.split('\t')[0])
            pages[current] = [line.rstrip('\n')]
        elif current is not None:
            pages[current].append(line.rstrip('\n'))
    return pages

width = int(sys.argv[3]) if len(sys.argv) > 3 else 160
base, cand = load(sys.argv[1]), load(sys.argv[2])
changed = [p for p in sorted(set(base) | set(cand)) if base.get(p) != cand.get(p)]

def taken(block):
    if not block: return None
    m = re.search(r'taken=(\d+)/(\d+)', block[0])
    return (int(m.group(1)), int(m.group(2))) if m else None

tb = sum((taken(base.get(p)) or (0, 0))[0] for p in changed)
tc = sum((taken(cand.get(p)) or (0, 0))[0] for p in changed)
print(f'changed pages: {len(changed)} {changed[:80]}  words taken on them {tb} -> {tc}')
for p in changed:
    print('--- base', p); print('\n'.join(l[:width] for l in base.get(p, ['missing'])))
    print('+++ cand', p); print('\n'.join(l[:width] for l in cand.get(p, ['missing'])))
