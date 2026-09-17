import sys, re, collections
# Per-book tallies of changed joins by class from join logs.
for path in sys.argv[1:]:
    t = collections.Counter()
    for line in open(path):
        kind, page, op, left, right = line.rstrip('\n').split('\t')
        if kind == 'block':
            t['block:' + ('removed' if op == '-1' else 'kept')] += 1
            continue
        before = left[-2]
        nxt = right[:1]
        if before.isdigit():
            t['number'] += 1
        elif nxt.isdigit():
            t['word+digit'] += 1
        elif op == 'removeHyphen':
            t['capital:removed'] += 1
        else:
            t['capital:kept'] += 1
    print(path.split('/')[-1], dict(t), sum(t.values()))
