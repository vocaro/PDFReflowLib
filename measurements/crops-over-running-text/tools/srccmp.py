import subprocess, zipfile, re, html, sys

# usage: srccmp.py <pdf> <pages> <base.epub> <cand.epub>
pdf, count, base, cand = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]

def source(page):
    text = subprocess.run(['pdftotext', '-f', str(page), '-l', str(page), pdf, '-'],
                          capture_output=True, text=True).stdout
    return len(re.sub(r'\s+', '', text))

def epub(path):
    z = zipfile.ZipFile(path)
    out, page = {}, 0
    for n in sorted(x for x in z.namelist() if x.endswith('.xhtml') and 'nav' not in x):
        body = re.sub(r'<head>.*?</head>', '', z.read(n).decode(), flags=re.S)
        for chunk in re.split(r'(<[^>]+>)', body):
            if chunk.startswith('<'):
                m = re.match(r'<span[^>]*epub:type="pagebreak"[^>]*aria-label="([^"]+)"', chunk)
                if m:
                    try: page = int(m.group(1))
                    except ValueError: pass
                continue
            out[page] = out.get(page, 0) + len(re.sub(r'\s+', '', html.unescape(chunk)))
    return out

b, c = epub(base), epub(cand)
ts = tb = tc = 0
print('page  source   base   cand')
for p in range(1, count + 1):
    s = source(p)
    print(f'{p:5} {s:7} {b.get(p,0):6} {c.get(p,0):6}')
    ts += s; tb += b.get(p, 0); tc += c.get(p, 0)
print(f'total {ts:7} {tb:6} {tc:6}')
