import sys, re, collections
# Compact listing of a join log: kind, operation, the word before the hyphen and the next word.
rows = collections.Counter()
for line in open(sys.argv[1]):
    kind, page, op, left, right = line.rstrip('\n').split('\t')
    lw = re.split(r'[\s(“"‘]', left)[-1]
    rw = ' '.join(right.split(' ')[:2])
    rows[(kind, op, lw, rw)] += 1
filt = sys.argv[2] if len(sys.argv) > 2 else ''
for (kind, op, lw, rw), n in sorted(rows.items()):
    if filt and filt != kind:
        continue
    print(f'{n}\t{kind}\t{op}\t{lw} | {rw}')
