#!/usr/bin/env python3
"""Compare two EPUBs page by page: blocks (tag + text), headings, images. usage: pages.py base.epub cand.epub"""
import re, sys, zipfile, html
from collections import Counter

def blocks(path):
    z = zipfile.ZipFile(path)
    opf = next(n for n in z.namelist() if n.endswith('.opf'))
    root = opf.rsplit('/', 1)[0]
    text = z.read(opf).decode()
    manifest = dict(re.findall(r'<item [^>]*id="([^"]+)"[^>]*href="([^"]+)"', text))
    manifest.update({i: h for h, i in re.findall(r'<item [^>]*href="([^"]+)"[^>]*id="([^"]+)"', text)})
    spine = re.findall(r'<itemref [^>]*idref="([^"]+)"', text)
    body = ''.join(z.read(f'{root}/{manifest[i]}').decode() for i in spine)
    pages = {}
    page = 0
    for m in re.finditer(r'id="page-(\d+)"|<(h[1-6]|p|pre|li|figcaption|td|th|blockquote|aside)\b[^>]*>(.*?)</\2>|<img [^>]*src="([^"]+)"', body, re.S):
        if m.group(1):
            page = int(m.group(1)); continue
        if m.group(4):
            pages.setdefault(page, []).append(('img', m.group(4))); continue
        t = html.unescape(re.sub(r'<[^>]+>', '', m.group(3)))
        t = re.sub(r'\s+', ' ', t).strip()
        pages.setdefault(page, []).append((m.group(2), t))
    return pages

a, b = blocks(sys.argv[1]), blocks(sys.argv[2])
for label, p in (('base', a), ('cand', b)):
    hs = Counter(k for v in p.values() for k, _ in v if k.startswith('h'))
    words = Counter(w for v in p.values() for k, t in v if k != 'img' for w in t.split())
    print(label, 'headings', sum(hs.values()), dict(sorted(hs.items())), 'blocks', sum(len(v) for v in p.values()),
          'images', sum(1 for v in p.values() for k, _ in v if k == 'img'), 'words', sum(words.values()))
wa = Counter(w for v in a.values() for k, t in v if k != 'img' for w in t.split())
wb = Counter(w for v in b.values() for k, t in v if k != 'img' for w in t.split())
print('word multiset delta:', dict(wa - wb), dict(wb - wa))
for page in sorted(set(a) | set(b)):
    if a.get(page) != b.get(page):
        print(f'--- page {page}')
        for k, t in a.get(page, []):
            if (k, t) not in b.get(page, []): print('  -', k, t[:160])
        for k, t in b.get(page, []):
            if (k, t) not in a.get(page, []): print('  +', k, t[:160])
