#!/usr/bin/env python3
"""What a screen reader reads for one source page of a converted EPUB: blocks in document order,
each image as `[image: alt]` (#187). No `title`, which assistive technology does not read by default.

usage: linearize.py <book.epub> <page>
"""
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

HTML = '{http://www.w3.org/1999/xhtml}'
OPS = '{http://www.idpf.org/2007/ops}'


def main():
    epub, wanted = sys.argv[1], int(sys.argv[2])
    with zipfile.ZipFile(epub) as archive:
        names = sorted((n for n in archive.namelist() if re.fullmatch(r'EPUB/chapter-\d+\.xhtml', n)),
                       key=lambda n: int(re.search(r'\d+', n).group()))
        page, out = None, []
        for name in names:
            body = ET.fromstring(archive.read(name)).find(HTML + 'body')
            for block in body:
                for element in block.iter():
                    if element.get(OPS + 'type') == 'pagebreak':
                        page = int(element.get('id')[5:])
                if page != wanted:
                    continue
                if block.tag == HTML + 'figure':
                    for image in block.iter(HTML + 'img'):
                        out.append(f"[image: {image.get('alt')}]")
                    for caption in block.iter(HTML + 'figcaption'):
                        out.append(f'[figcaption: {"".join(caption.itertext())}]')
                else:
                    text = ' '.join(''.join(block.itertext()).split())
                    if text:
                        out.append(text)
        print('\n'.join(out))


if __name__ == '__main__':
    main()
