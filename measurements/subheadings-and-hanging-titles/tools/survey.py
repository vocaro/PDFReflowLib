import re, sys
# Caption survey and heading page lookup over one block dump.
page = 0
long_captions = []
wanted = set(sys.argv[2:])
for l in open(sys.argv[1]):
    l = l.rstrip('\n')
    m = re.match(r'=== page (\d+)', l)
    if m:
        page = int(m.group(1)); continue
    kind, _, text = l.partition(': ')
    if text in wanted and kind.startswith('h'):
        print('heading', repr(text), 'page', page)
    m = re.match(r'(Figure \d+-\d+[A-Za-z]?\.)(.*)', text)
    if kind == 'p' and m:
        parts = re.split(r'(?<=[.?!\]])\s+', m.group(2).strip())
        if len(text) > 160 or len(parts) > 2:
            long_captions.append((page, text))
print('long captions', len(long_captions))
for p, t in long_captions:
    # A sentence that opens lowercase after a caption sentence suggests absorbed body text.
    if re.search(r'[.?!]\s+[a-z]', t):
        print('  lowercase continuation', p, t[:160])
