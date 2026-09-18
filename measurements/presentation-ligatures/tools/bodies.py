#!/usr/bin/env python3
"""usage: bodies.py <baseline.epub> <candidate.epub> — whether the spine bodies, concatenated in spine
order with same-book file names removed from links, are equal once the baseline's ligatures are spelled
out, and how many spine files each has (a spine packing change moves blocks between files only)."""
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
TABLE = {'ﬀ': 'ff', 'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬃ': 'ffi', 'ﬄ': 'ffl', 'ﬅ': 'ſt', 'ﬆ': 'st'}
OPF = '{http://www.idpf.org/2007/opf}'


def body(path, spell):
    z = zipfile.ZipFile(path)
    package = ET.fromstring(z.read('EPUB/package.opf'))
    manifest = {e.get('id'): e.get('href') for e in package.find(OPF + 'manifest')}
    hrefs = [manifest[r.get('idref')] for r in package.find(OPF + 'spine')]
    parts = []
    for href in hrefs:
        text = z.read('EPUB/' + href).decode()
        text = text[text.index('<body'):text.rindex('</body>')]
        text = re.sub(r'<body[^>]*>', '', text)
        text = re.sub(r'href="[^"#]*\.xhtml#', 'href="#', text)
        if spell:
            text = re.sub('[ﬀ-ﬆ]', lambda m: TABLE[m.group(0)], text)
        parts.append(text.strip())
    return '\n'.join(parts), len(hrefs)


a, na = body(sys.argv[1], True)
b, nb = body(sys.argv[2], False)
print(f'spine files {na}/{nb}; concatenated bodies equal after spelling out: {a == b}')
if a != b:
    i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
    print(repr(a[i - 100:i + 100]))
    print(repr(b[i - 100:i + 100]))
