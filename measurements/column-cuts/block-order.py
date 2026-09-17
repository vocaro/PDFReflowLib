"""Per-page ordered block sequences from an EPUB, and an order diff between two runs.

usage: blockorder.py BEFORE.epub AFTER.epub PAGES OUT.txt
PAGES is a comma-separated list. For each page: whether the multiset of non-space
characters is identical, whether the block multiset is identical, and a unified diff
of the ordered block sequence (h=heading, p=paragraph, pre, img).
"""
import difflib
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import PurePosixPath

XHTML = '{http://www.w3.org/1999/xhtml}'
EPUB = '{http://www.idpf.org/2007/ops}'
OPF = '{http://www.idpf.org/2007/opf}'
BLOCKS = {'p': 'p', 'pre': 'pre', 'h1': 'h', 'h2': 'h', 'h3': 'h', 'h4': 'h', 'h5': 'h', 'h6': 'h',
          'figcaption': 'cap', 'td': 'td', 'th': 'td', 'aside': None}


def load(path):
    pages = {}
    current = None
    with zipfile.ZipFile(path) as archive:
        package = ET.fromstring(archive.read('EPUB/package.opf'))
        manifest = {e.get('id'): e.get('href') for e in package.find(OPF + 'manifest')}
        for reference in package.find(OPF + 'spine'):
            tree = ET.fromstring(archive.read(str(PurePosixPath('EPUB') / manifest[reference.get('idref')])))

            def text_of(element):
                """Text of a block, stopping at nested page markers (which switch pages)."""
                parts = []
                def inner(e):
                    nonlocal current
                    if 'pagebreak' in e.get(EPUB + 'type', '').split():
                        return
                    if e.text:
                        parts.append(e.text)
                    for child in e:
                        inner(child)
                        if child.tail:
                            parts.append(child.tail)
                inner(element)
                return re.sub(r'\s+', ' ', ''.join(parts)).strip()

            def walk(element):
                nonlocal current
                if 'pagebreak' in element.get(EPUB + 'type', '').split():
                    current = int(element.get('id', 'page-0')[5:])
                    pages.setdefault(current, [])
                    return
                tag = element.tag.replace(XHTML, '')
                if current is not None and tag == 'img':
                    pages[current].append(('img', PurePosixPath(element.get('src', '')).name))
                    return
                kind = BLOCKS.get(tag)
                if current is not None and kind:
                    page = current
                    # a block that begins on this page keeps its text here
                    pages[page].append((kind, text_of(element)))
                    # still descend for page markers and images inside the block
                    for child in element.iter():
                        if child is element:
                            continue
                        if 'pagebreak' in child.get(EPUB + 'type', '').split():
                            current = int(child.get('id', 'page-0')[5:])
                            pages.setdefault(current, [])
                        elif child.tag.replace(XHTML, '') == 'img':
                            pages[current].append(('img', PurePosixPath(child.get('src', '')).name))
                    return
                for child in element:
                    walk(child)

            walk(tree)
    return pages


def main():
    before, after = load(sys.argv[1]), load(sys.argv[2])
    numbers = [int(n) for n in sys.argv[3].split(',') if n]
    with open(sys.argv[4], 'w') as out:
        for n in numbers:
            a, b = before.get(n, []), after.get(n, [])
            chars_a = Counter(c for _, t in a for c in t if not c.isspace())
            chars_b = Counter(c for _, t in b for c in t if not c.isspace())
            same_blocks = Counter(a) == Counter(b)
            out.write('=' * 100 + '\n')
            out.write(f'PAGE {n}  blocks {len(a)}->{len(b)}  sameCharacters={chars_a == chars_b}  sameBlockSet={same_blocks}\n')
            fa = [f'{k:4} {t[:110]}' for k, t in a]
            fb = [f'{k:4} {t[:110]}' for k, t in b]
            for line in difflib.unified_diff(fa, fb, 'before', 'after', lineterm='', n=2):
                out.write('  ' + line + '\n')


main()
