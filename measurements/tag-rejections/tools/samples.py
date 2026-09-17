"""samples.py <stderr-file>: classify SAMPLE lines (anchors rejected for no line / ambiguity)."""
import collections, sys
c = collections.Counter(); pages = collections.defaultdict(set)
for line in open(sys.argv[1], errors='replace'):
    if not line.startswith('SAMPLE'): continue
    parts = line.rstrip('\n').split('\t')
    page, kind, point, length, hexbytes, ascii_ = parts[1], parts[2], parts[3], parts[4], parts[5], parts[6]
    n = int(length[3:])
    if set(bytes.fromhex(hexbytes)) <= {0x20} and n <= 8 and n == len(hexbytes) // 2:
        cls = 'spaces only (single-byte 0x20)'
    elif n == 0:
        cls = 'empty string'
    elif n <= 3:
        cls = 'short show (<=3 bytes: superscript/marker)'
    else:
        cls = 'text run'
    key = f'{kind.split("(")[0]} / {cls}'
    c[key] += 1; pages[key].add(int(page))
for k, v in c.most_common():
    ps = sorted(pages[k])
    print(f'{k}\t{v} anchors on {len(ps)} pages\t{ps[:25]}')
