import sys, zipfile, re, html
from collections import Counter

# usage: chars.py <epub> [--pages] — characters of reflowed text, images and warnings.
path = sys.argv[1]
z = zipfile.ZipFile(path)
names = [n for n in z.namelist() if n.endswith('.xhtml') and 'nav' not in n]
text_total = 0
per_page = Counter()
images = 0
page = 0
for n in sorted(names):
    body = z.read(n).decode('utf-8')
    # strip elements that are not reflowed text
    body = re.sub(r'<head>.*?</head>', '', body, flags=re.S)
    for chunk in re.split(r'(<[^>]+>)', body):
        if chunk.startswith('<'):
            m = re.match(r'<span[^>]*epub:type="pagebreak"[^>]*aria-label="([^"]+)"', chunk)
            if m:
                try: page = int(m.group(1))
                except ValueError: pass
            if chunk.startswith('<img'):
                images += 1
            continue
        t = html.unescape(chunk).strip()
        if t:
            text_total += len(t)
            per_page[page] += len(t)
print(f'{path}: text characters {text_total}, images {images}, pages {len(per_page)}')
if '--pages' in sys.argv:
    for p in sorted(per_page): print(f'  page {p}: {per_page[p]}')
