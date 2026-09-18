#!/usr/bin/env python3
"""usage: count.py <epub>... -> counts of U+FB00-U+FB06 in every text entry of each EPUB."""
import sys, zipfile, collections
for path in sys.argv[1:]:
    z = zipfile.ZipFile(path)
    c = collections.Counter()
    for n in z.namelist():
        if n.endswith(('.xhtml', '.opf', '.ncx', '.html', '.css')):
            for ch in z.read(n).decode('utf-8'):
                if 0xFB00 <= ord(ch) <= 0xFB06:
                    c['U+%04X' % ord(ch)] += 1
    print(path, sum(c.values()), dict(sorted(c.items())))
