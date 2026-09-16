#!/usr/bin/env python3
"""Cross-page join counts and the exact joined pairs, for before/after comparison."""
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import PurePosixPath

HTML = '{http://www.w3.org/1999/xhtml}'
OPF = '{http://www.idpf.org/2007/opf}'
EPUB = '{http://www.idpf.org/2007/ops}'
HEADINGS = {HTML + 'h' + str(n) for n in range(1, 7)}
BLOCKS = HEADINGS | {HTML + t for t in ('p', 'pre', 'figure', 'li', 'table')}


def text_of(e):
    return ' '.join(''.join(e.itertext()).split())


def joins(path):
    """Every block that contains a page marker: (start page, end page, tail, head)."""
    out = []
    page = [0]

    def walk(el):
        if 'pagebreak' in el.get(EPUB + 'type', '').split():
            page[0] = int(el.get('id', 'page-0')[5:])
            return
        if el.tag in BLOCKS:
            start = page[0]
            inner = [int(s.get('id', 'page-0')[5:]) for s in el.iter()
                     if s is not el and 'pagebreak' in s.get(EPUB + 'type', '').split()]
            if inner:
                whole = text_of(el)
                # Split the text at the marker using the tail text of the marker element.
                out.append((start, inner[-1], whole[:60], whole[-60:]))
                page[0] = inner[-1]
            return
        for child in el:
            walk(child)

    with zipfile.ZipFile(path) as z:
        pkg = ET.fromstring(z.read('EPUB/package.opf'))
        manifest = {e.get('id'): e.get('href') for e in pkg.find(OPF + 'manifest')}
        for ref in pkg.find(OPF + 'spine'):
            chapter = PurePosixPath('EPUB') / manifest[ref.get('idref')]
            walk(ET.fromstring(z.read(str(chapter))).find(HTML + 'body'))
    return out


a, b = joins(sys.argv[1]), joins(sys.argv[2])
ka = {(x[0], x[1]) for x in a}
kb = {(x[0], x[1]) for x in b}
print('joins: %d -> %d' % (len(a), len(b)))
if ka - kb:
    print('  lost  :', sorted(ka - kb))
if kb - ka:
    print('  gained:', sorted(kb - ka))
for x in b:
    if (x[0], x[1]) in kb - ka:
        print('    p%d->p%d  …%s | %s…' % (x[0], x[1], x[2][:0] or x[2], x[3]))
