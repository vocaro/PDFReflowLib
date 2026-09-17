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

base, cand = load(sys.argv[1]), load(sys.argv[2])
changed = [p for p in sorted(set(base) | set(cand)) if base.get(p) != cand.get(p)]
print(f'changed pages: {len(changed)} {changed[:50]}')
for p in changed:
    print('--- base', p); print('\n'.join(base.get(p, ['missing'])))
    print('+++ cand', p); print('\n'.join(cand.get(p, ['missing'])))
