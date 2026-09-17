#!/usr/bin/env python3
"""Pages where a preserved figure (and caption) interrupts a sentence: <p> ending without
terminal punctuation, figure, optional caption paragraph, then <p> starting lowercase."""
import re, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = sorted([n for n in z.namelist() if re.search(r'chapter-\d+\.xhtml$', n)],
               key=lambda n: int(re.search(r'(\d+)\.xhtml', n).group(1)))
body = ''.join(z.read(n).decode() for n in names)
pages = []
page = 0; state = None; last_text = None
for token in re.finditer(r'id="page-(\d+)"|<p[^>]*>(.*?)</p>|<figure>', body, re.S):
    if token.group(1): page = int(token.group(1)); state = None; continue
    if token.group(0) == '<figure>':
        if last_text is not None and not re.search(r'[.:?!”"\]\)]\s*$', last_text): state = 'figure'
        continue
    text = re.sub(r'<[^>]+>', '', token.group(2)).strip()
    if 'state' in dir() and state == 'figure':
        if text.startswith('Figure'): last_text = last_text; continue
        if text[:1].islower(): pages.append(page)
        state = None
    last_text = text
print(len(pages), pages)
