#!/usr/bin/env python3
"""usage: xhtmldiff.py <base.epub> <cand.epub>  per XHTML file: identical, whitespace-only, or other difference
(text with tags stripped and entities decoded; markup outside text is compared with whitespace removed too)."""
import html, re, sys, zipfile
a, b = zipfile.ZipFile(sys.argv[1]), zipfile.ZipFile(sys.argv[2])
names = sorted(n for n in set(a.namelist()) | set(b.namelist()) if n.endswith('.xhtml'))
counts = {'identical': 0, 'whitespace': 0, 'other': 0}
for name in names:
    x = a.read(name).decode() if name in a.namelist() else ''
    y = b.read(name).decode() if name in b.namelist() else ''
    if x == y:
        counts['identical'] += 1; continue
    squeeze = lambda s: re.sub(r'\s+', '', html.unescape(s))
    if squeeze(x) == squeeze(y):
        counts['whitespace'] += 1
    else:
        counts['other'] += 1; print('other:', name)
print(counts)
