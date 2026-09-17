#!/usr/bin/env python3
"""usage: pagediff.py base.epub cand.epub page [page...]  unified diff of each page's markup, one block per line."""
import difflib, re, sys, zipfile

def pages(path):
    z = zipfile.ZipFile(path)
    names = sorted([n for n in z.namelist() if re.search(r'chapter-\d+\.xhtml$', n)], key=lambda s: int(re.findall(r'\d+', s)[-1]))
    body = ''.join(re.sub(r'(?s).*<body>|</body>.*', '', z.read(n).decode()) for n in names)
    body = re.sub(r' id="(heading|note|noteref)-[^"]*"', '', body)
    body = re.sub(r'images/image-\d+', 'images/image-N', body)
    parts = re.split(r'(<span epub:type="pagebreak"[^>]*id="page-(\d+)"[^>]*/>)', body)
    result, current = {}, None
    i = 0
    while i < len(parts):
        if i + 2 < len(parts) and parts[i + 1] and parts[i + 1].startswith('<span epub:type="pagebreak"'):
            if current is not None: result[current] += parts[i]
            current = int(parts[i + 2]); result[current] = ''
            i += 3
        else:
            if current is not None: result[current] += parts[i]
            i += 1
    return {k: re.sub(r'(</(p|h\d|table|figure|pre|div|caption|tr)>)', r'\1\n', v).replace('<caption>', '\n<caption>').replace('<tbody>', '\n<tbody>').replace('<thead>', '\n<thead>') for k, v in result.items()}

base, cand = pages(sys.argv[1]), pages(sys.argv[2])
for page in map(int, sys.argv[3:]):
    a = [l for l in base.get(page, '').split('\n') if l.strip()]
    b = [l for l in cand.get(page, '').split('\n') if l.strip()]
    print(f'==== page {page}')
    for line in difflib.unified_diff(a, b, lineterm='', n=0):
        if line.startswith(('---', '+++')): continue
        print(line[:260])
