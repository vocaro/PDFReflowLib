import sys, zipfile, re
import xml.etree.ElementTree as ET
from pathlib import PurePosixPath
H = '{http://www.w3.org/1999/xhtml}'
E = '{http://www.idpf.org/2007/ops}'
OPF = '{http://www.idpf.org/2007/opf}'
BLOCKS = {'h1','h2','h3','h4','h5','h6','p','pre','li','figcaption','td','th'}
out = []
page = [0]
def text(el):
    parts = []
    def rec(e):
        if 'pagebreak' in e.get(E+'type', ''):
            parts.append(f'[[p{e.get("id")[5:]}]]')
        if e.text: parts.append(e.text)
        for c in e:
            rec(c)
            if c.tail: parts.append(c.tail)
    rec(el)
    return re.sub(r'\s+', ' ', ''.join(parts)).strip()
def walk(el):
    tag = el.tag[len(H):] if el.tag.startswith(H) else el.tag
    if 'pagebreak' in el.get(E+'type', ''):
        out.append(f'=== page {el.get("id")[5:]}')
    if tag in BLOCKS:
        t = text(el)
        out.append(f'{tag}: {t}')
        for m in re.findall(r'\[\[p(\d+)\]\]', t):
            out.append(f'=== page {m} (inside)')
        return
    if tag == 'img':
        out.append('img')
    for c in el:
        walk(c)
with zipfile.ZipFile(sys.argv[1]) as z:
    pkg = ET.fromstring(z.read('EPUB/package.opf'))
    man = {e.get('id'): e.get('href') for e in pkg.find(OPF+'manifest')}
    for ref in pkg.find(OPF+'spine'):
        walk(ET.fromstring(z.read(str(PurePosixPath('EPUB')/man[ref.get('idref')]))))
print('\n'.join(out))
