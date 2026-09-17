"""Print a page's blocks in reading order from an EPUB (headings, paragraphs, list items, images).

usage: pagedump.py <worktree> book.epub page[,page...] [--width N]
"""
import re
import sys
import zipfile
import html

width = int(sys.argv[sys.argv.index('--width') + 1]) if '--width' in sys.argv else 150
pages = set(int(p) for p in sys.argv[3].split(','))
z = zipfile.ZipFile(sys.argv[2])
names = sorted((n for n in z.namelist() if n.endswith('.xhtml') and 'nav' not in n),
               key=lambda n: [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', n)])
current = None
token = re.compile(r'<(h[1-6]|p|li|img|figure|figcaption|table|aside|span)\b([^>]*)>(.*?)(?=<(?:h[1-6]|p|li|img|figure|figcaption|table|aside|/body|span)\b|$)', re.S)
for name in names:
    doc = z.read(name).decode('utf-8')
    for m in re.finditer(r'<(h[1-6]|p|li|img|figcaption|span|aside|table)\b([^>]*)/?>', doc):
        tag, attrs = m.group(1), m.group(2)
        page = re.search(r'epub:type="pagebreak"[^>]*?(?:title|aria-label)="(\d+)"|id="page-?(\d+)"', attrs)
        if page:
            current = int(page.group(1) or page.group(2))
            continue
        if current not in pages:
            continue
        if tag == 'img':
            src = re.search(r'src="([^"]+)"', attrs)
            print(f'  [{current}] IMG {src.group(1) if src else ""}')
            continue
        if tag in ('span', 'aside', 'table'):
            if tag != 'span':
                print(f'  [{current}] <{tag}{attrs[:60]}>')
            continue
        end = doc.find(f'</{tag}>', m.end())
        text = re.sub(r'<[^>]+>', '', doc[m.end():end])
        text = html.unescape(' '.join(text.split()))
        print(f'  [{current}] {tag.upper():3} {text[:width]}')
