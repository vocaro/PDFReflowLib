#!/usr/bin/env python3
"""Per-page reflowed words (EPUB text between pagebreak markers) vs pdftotext words.
usage: words.py EPUB PDF [pages comma list]"""
import re, subprocess, sys, zipfile, html
epub, pdf = sys.argv[1], sys.argv[2]
wanted = set(int(p) for p in sys.argv[3].split(',')) if len(sys.argv) > 3 else None
z = zipfile.ZipFile(epub)
names = sorted([n for n in z.namelist() if re.search(r'chapter-\d+\.xhtml$', n)],
               key=lambda n: int(re.search(r'(\d+)\.xhtml', n).group(1)))
pages = {}
fallback = {}
cur = None
for n in names:
    body = z.read(n).decode()
    for part in re.split(r'(<span epub:type="pagebreak"[^>]*/>)', body):
        m = re.match(r'<span epub:type="pagebreak"[^>]*id="page-(\d+)"', part)
        if m:
            cur = int(m.group(1)); continue
        if cur is None: continue
        if wanted and cur not in wanted: continue
        fallback[cur] = fallback.get(cur, False) or ('alt="Page ' in part or 'alt="Original page %d"' % cur in part and '<p' not in part and '<h' not in part)
        text = re.sub(r'<figcaption>.*?</figcaption>', ' ', part, flags=re.S)
        text = re.sub(r'<[^>]+>', ' ', text)
        pages[cur] = pages.get(cur, 0) + len(re.findall(r'\w+', html.unescape(text)))
for p in sorted(pages):
    t = subprocess.run(['pdftotext', '-f', str(p), '-l', str(p), '-layout', pdf, '-'], capture_output=True, text=True).stdout
    print(f'page {p}: reflowed={pages[p]} pdftotext={len(re.findall(r"\w+", t))}')
