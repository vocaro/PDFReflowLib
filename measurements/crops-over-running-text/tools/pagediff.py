import sys, zipfile, re, html, io

# usage: pagediff.py <base.epub> <cand.epub> <page> [page...]
def pages(path):
    z = zipfile.ZipFile(path)
    files = sorted(x for x in z.namelist() if x.endswith('.xhtml') and 'nav' not in x)
    body = ''.join(z.read(n).decode() for n in files)
    body = re.sub(r'<head>.*?</head>', '', body, flags=re.S)
    parts = re.split(r'(<span[^>]*epub:type="pagebreak"[^>]*aria-label="\d+"[^>]*/?>)', body)
    out = {}
    for i, part in enumerate(parts):
        m = re.match(r'.*aria-label="(\d+)"', part or '')
        if m:
            out[int(m.group(1))] = parts[i + 1] if i + 1 < len(parts) else ''
    return z, out

bz, b = pages(sys.argv[1])
cz, c = pages(sys.argv[2])
try:
    from PIL import Image
    have = True
except ImportError:
    have = False
for number in [int(x) for x in sys.argv[3:]]:
    print('==== page', number)
    for label, z, seg in (('base', bz, b.get(number, '')), ('cand', cz, c.get(number, ''))):
        blocks = re.findall(r'<(h[1-6]|p|figure)[^>]*>(.*?)</\1>', seg, re.S)
        texts = [html.unescape(re.sub('<[^>]+>', '', t))[:90] for kind, t in blocks if kind != 'figure']
        images = re.findall(r'src="([^"]+)"', seg)
        sizes = []
        for src in images:
            name = 'EPUB/' + src.split('../')[-1] if not src.startswith('EPUB/') else src
            name = name.replace('EPUB/images/', 'EPUB/images/')
            try:
                data = z.read(name)
                sizes.append((name.split('/')[-1], Image.open(io.BytesIO(data)).size if have else len(data)))
            except KeyError:
                sizes.append((src, 'missing'))
        print(' ', label, 'blocks', len(texts), 'images', sizes)
        for t in texts[:6]:
            print('     ', t)
