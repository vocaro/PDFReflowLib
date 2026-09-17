"""Evidence probe (#145): page-space start/end of each text show on one page of the FAA PDF.
usage: measure.py pdf page ymin ymax
Only the page content stream (Form XObjects are skipped), CID (Identity-H, W/DW) and simple (Widths) fonts.
"""
import re
import subprocess
import sys

pdf, page, ymin, ymax = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])


def show(obj):
    return subprocess.run(['mutool', 'show', pdf, obj], capture_output=True, text=True).stdout


def ref(text, key):
    m = re.search(r'/' + key + r'\s+(\d+) 0 R', text)
    return m.group(1) if m else None


resources = show(f'pages/{page}/Resources')
fontdict = re.search(r'/Font\s*<<(.*?)>>', resources, re.S).group(1)
fonts = {}
for name, num in re.findall(r'/(\S+)\s+(\d+) 0 R', fontdict):
    d = show(num)
    if '/Type0' in d:
        desc = show(ref(d, 'DescendantFonts') and re.search(r'\[\s*(\d+) 0 R', show(ref(d, 'DescendantFonts'))).group(1))
        dw = float(re.search(r'/DW\s+([\d.]+)', desc).group(1)) if '/DW' in desc else 1000
        w = {}
        m = re.search(r'/W\s*\[(.*)\]', desc, re.S)
        if m:
            toks = re.findall(r'\[|\]|[\d.]+', m.group(1))
            i = 0
            while i < len(toks):
                first = int(toks[i]); i += 1
                if toks[i] == '[':
                    i += 1; c = first
                    while toks[i] != ']':
                        w[c] = float(toks[i]); c += 1; i += 1
                    i += 1
                else:
                    last = int(toks[i]); val = float(toks[i + 1]); i += 2
                    for c in range(first, last + 1): w[c] = val
        fonts[name] = ('cid', w, dw)
    else:
        fc = re.search(r'/FirstChar\s+(\d+)', d)
        ws = re.search(r'/Widths\s*(?:\[(.*?)\]|(\d+) 0 R)', d, re.S)
        arr = ws.group(1) if ws and ws.group(1) else (show(ws.group(2)) if ws else '')
        vals = [float(x) for x in re.findall(r'[\d.]+', arr)]
        fonts[name] = ('simple', {int(fc.group(1)) + i: v for i, v in enumerate(vals)} if fc else {}, 0)

content = subprocess.run(['mutool', 'show', '-b', pdf, f'pages/{page}/Contents'], capture_output=True).stdout.decode('latin1')
tok = re.compile(r'<<|>>|\[|\]|<[0-9A-Fa-f\s]*>|\((?:\\.|[^\\)])*\)|/[^\s/\[\]()<>]+|[-+]?\d*\.?\d+|[A-Za-z\'"*]+[01]?\*?')


def mul(a, b):
    return [a[0] * b[0] + a[1] * b[2], a[0] * b[1] + a[1] * b[3], a[2] * b[0] + a[3] * b[2],
            a[2] * b[1] + a[3] * b[3], a[4] * b[0] + a[5] * b[2] + b[4], a[4] * b[1] + a[5] * b[3] + b[5]]


I = [1, 0, 0, 1, 0, 0]
ctm = I; tm = I; tlm = I; font = None; size = 0; tc = 0; tw = 0; tz = 100; tl = 0
stack = []; ops = []
for t in tok.findall(content):
    if t in ('[', ']') or t.startswith(('<', '(', '/')) or re.match(r'^[-+]?\d*\.?\d+$', t) or t in ('<<', '>>'):
        ops.append(t); continue
    op = t
    nums = [float(x) for x in ops if re.match(r'^[-+]?\d*\.?\d+$', x)]
    if op == 'q': stack.append((ctm, font, size, tc, tw, tz, tl))
    elif op == 'Q' and stack: ctm, font, size, tc, tw, tz, tl = stack.pop()
    elif op == 'cm' and len(nums) >= 6: ctm = mul(nums[-6:], ctm)
    elif op == 'BT': tm = tlm = I
    elif op == 'Tf': font = [x for x in ops if x.startswith('/')][-1][1:]; size = nums[-1]
    elif op == 'Tc': tc = nums[-1]
    elif op == 'Tw': tw = nums[-1]
    elif op == 'Tz': tz = nums[-1]
    elif op == 'TL': tl = nums[-1]
    elif op == 'Tm': tlm = tm = nums[-6:]
    elif op in ('Td', 'TD'):
        if op == 'TD': tl = -nums[-1]
        tlm = tm = mul([1, 0, 0, 1, nums[-2], nums[-1]], tlm)
    elif op == 'T*': tlm = tm = mul([1, 0, 0, 1, 0, -tl], tlm)
    elif op in ('Tj', 'TJ'):
        kind, widths, dw = fonts.get(font, ('?', {}, 0))
        m = mul(tm, ctm); x0 = m[4]; y0 = m[5]
        adv = 0; trailing = 0; pending = 0; n = 0
        for item in ops:
            if item.startswith('<') and not item.startswith('<<'):
                hexs = re.sub(r'\s', '', item[1:-1])
                codes = [int(hexs[i:i + 4], 16) for i in range(0, len(hexs), 4)] if kind == 'cid' else [int(hexs[i:i + 2], 16) for i in range(0, len(hexs), 2)]
                adv -= pending; pending = 0
                for c in codes:
                    wv = widths.get(c, dw) / 1000
                    sp = tc + (tw if kind == 'simple' and c == 32 else 0)
                    adv += (wv * size + sp) * tz / 100; trailing = sp * tz / 100; n += 1
            elif item.startswith('('):
                adv -= pending; pending = 0
                s = item[1:-1]
                for ch in s.encode('latin1'):
                    wv = widths.get(ch, 0) / 1000
                    sp = tc + (tw if ch == 32 else 0)
                    adv += (wv * size + sp) * tz / 100; trailing = sp * tz / 100; n += 1
            elif re.match(r'^[-+]?\d*\.?\d+$', item) and op == 'TJ':
                pending += float(item) / 1000 * size * tz / 100
        end = x0 + (adv - trailing) * m[0]
        if ymin <= y0 <= ymax:
            print(f'{font:6} y{y0:7.2f} x{x0:7.2f} end{end:7.2f} glyphs{n:3} tc{tc} tw{tw}')
        tm = mul([1, 0, 0, 1, adv - pending, 0], tm)
    ops = []
