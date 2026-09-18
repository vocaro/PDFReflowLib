import sys, re, html, zipfile

# usage: blocks.py <epub> [page ...]: each page's blocks, one per line (tag: text), images as [img]
def pages(path):
    z = zipfile.ZipFile(path)
    files = sorted((x for x in z.namelist() if x.endswith('.xhtml') and 'nav' not in x),
                   key=lambda n: [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', n)])
    body = ''.join(re.sub(r'<head>.*?</head>', '', z.read(n).decode(), flags=re.S) for n in files)
    parts = re.split(r'(<span[^>]*epub:type="pagebreak"[^>]*/?>)', body)
    out, current = {}, None
    for part in parts:
        m = re.search(r'aria-label="(\d+)"', part) if 'pagebreak' in part else None
        if m:
            current = int(m.group(1)); out.setdefault(current, '')
        elif current is not None:
            out[current] += part
    return out

p = pages(sys.argv[1])
want = [int(x) for x in sys.argv[2:]] or sorted(p)
for n in want:
    print(f'==== page {n}')
    for kind, inner in re.findall(r'<(h[1-6]|p|pre|figure|li)\b[^>]*>(.*?)</\1>', p.get(n, ''), re.S):
        text = html.unescape(re.sub(r'<[^>]+>', '', inner)).strip()
        if kind == 'figure' or '<img' in inner:
            print('  [img]', text[:100])
        else:
            print(f'  {kind}:', text)
