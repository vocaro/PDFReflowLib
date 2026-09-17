#!/usr/bin/env python3
"""Survey 9/11 notes page transitions in an unpacked EPUB directory."""
import html, re, sys, json, glob, os

root = sys.argv[1]
files = sorted(glob.glob(os.path.join(root, 'EPUB', 'chapter-*.xhtml')), key=lambda p: int(re.search(r'chapter-(\d+)', p).group(1)))
lines = []
for f in files:
    body = open(f, encoding='utf-8').read()
    m = re.search(r'<body[^>]*>(.*)</body>', body, re.S)
    for line in m.group(1).split('\n'):
        if line.strip():
            lines.append(line)

PB = re.compile(r'<span epub:type="pagebreak"[^>]*id="page-(\d+)"[^>]*/>')

def text(s):
    s = PB.sub('\x00', s)
    s = re.sub(r'<[^>]+>', '', s)
    return html.unescape(s)

# blocks: (page_at_start, raw)
blocks = []
page = 0
for line in lines:
    # leading pagebreak(s) belong before the block
    while True:
        m = PB.match(line)
        if not m:
            break
        page = int(m.group(1))
        blocks.append(('break', page, None))
        line = line[m.end():]
    if not line.strip():
        continue
    blocks.append(('block', page, line))
    for m in PB.finditer(line):
        page = int(m.group(1))

NOTE = re.compile(r'^\s*([1-9][0-9]{0,2})\.\s*\S')
out = []
for i, b in enumerate(blocks):
    if b[0] == 'block':
        raw = b[2]
        for m in PB.finditer(raw):
            p = int(m.group(1))
            if 469 <= p <= 585:
                t = text(raw)
                k = t.index('\x00') if '\x00' in t else 0
                # find which break this is
                parts = t.split('\x00')
                idx = [int(x.group(1)) for x in PB.finditer(raw)].index(p)
                before = parts[idx].rstrip()[-80:]
                after = parts[idx + 1].lstrip()[:80]
                out.append(dict(page=p, kind='joined', before=before, after=after,
                                tag=re.match(r'<(\w+)', raw).group(1)))
    elif b[0] == 'break' and 469 <= b[1] <= 585:
        p = b[1]
        # previous block text
        j = i - 1
        while j >= 0 and blocks[j][0] != 'block':
            j -= 1
        k = i + 1
        while k < len(blocks) and blocks[k][0] != 'block':
            k += 1
        prev = text(blocks[j][2]).replace('\x00', '') if j >= 0 else ''
        nxt_raw = blocks[k][2] if k < len(blocks) else ''
        nxt = text(nxt_raw).replace('\x00', '')
        m = NOTE.match(nxt)
        kind = 'note-start' if m else 'separate'
        out.append(dict(page=p, kind=kind, before=prev.rstrip()[-80:], after=nxt.lstrip()[:80],
                        tag=re.match(r'<(\w+)', nxt_raw).group(1) if nxt_raw else '',
                        keyed='id="note-' in nxt_raw))
json.dump(out, sys.stdout, indent=1, ensure_ascii=False)
