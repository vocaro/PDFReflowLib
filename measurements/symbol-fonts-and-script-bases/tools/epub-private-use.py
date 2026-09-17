#!/usr/bin/env python3
"""usage: epub-private-use.py <epub> [page ...] | epub-private-use.py --pua <epub>
Raw XHTML markup of source pages (split at page-break spans), private-use characters shown as <U+XXXX>.
--pua: count private-use characters per page."""
import re, sys, zipfile
import xml.etree.ElementTree as ET

def pages(path):
    with zipfile.ZipFile(path) as z:
        opf = ET.fromstring(z.read('EPUB/package.opf'))
        ns = '{http://www.idpf.org/2007/opf}'
        manifest = {e.get('id'): e.get('href') for e in opf.find(ns + 'manifest')}
        text = ''.join(z.read('EPUB/' + manifest[r.get('idref')]).decode() for r in opf.find(ns + 'spine'))
    parts = re.split(r'<span epub:type="pagebreak"[^>]*id="page-(\d+)"[^>]*/>', text)
    result = {}
    for i in range(1, len(parts), 2):
        result.setdefault(int(parts[i]), '')
        result[int(parts[i])] += parts[i + 1]
    return result

def show(s):
    return ''.join(f'<U+{ord(c):04X}>' if 0xE000 <= ord(c) <= 0xF8FF else c for c in s)

if sys.argv[1] == '--pua':
    total = 0
    for number, body in sorted(pages(sys.argv[2]).items()):
        chars = [c for c in body if 0xE000 <= ord(c) <= 0xF8FF]
        if chars:
            total += len(chars)
            print(number, len(chars), ' '.join(sorted({f'U+{ord(c):04X}' for c in chars})))
    print('TOTAL', total)
else:
    p = pages(sys.argv[1])
    for n in sys.argv[2:]:
        print(f'=== page {n}')
        print(show(p.get(int(n), '')))
