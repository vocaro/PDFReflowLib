#!/usr/bin/env python3
"""Every image a converted EPUB carries, with its page, alternative text and title (#187).

usage: census.py <evaluation-directory | book.epub>

One tab-separated row per `img`, in reading order: source page, alternative text, title, and
whether a `figcaption` follows it inside its figure. The kind is recoverable from the alternative
text (`kind_of`); a caption the source prints shows as its own text.
"""
import pathlib
import sys
import xml.etree.ElementTree as ET
import zipfile

HTML = '{http://www.w3.org/1999/xhtml}'
OPF = '{http://www.idpf.org/2007/opf}'
KINDS = {
    'Mathematical expression': 'equation',
    'Table kept as an image': 'table',
    'Algorithm listing': 'listing',
    'Illustration': 'artwork',
    'Text kept as an image': 'text',
    'Whole page kept as an image': 'page',
    'The printed page, for comparison': 'sourcePage',
}


def kind_of(alt):
    """The converter's kind for an alternative text; a printed caption is `caption`."""
    if alt in KINDS:
        return KINDS[alt]
    if alt.startswith('Preserved region from page') or alt.startswith('Original page'):
        return 'provenance'
    return 'caption' if alt else 'empty'


def epub_of(path):
    path = pathlib.Path(path)
    if path.suffix == '.epub':
        return path
    found = sorted(path.rglob('*.epub'))
    if not found:
        sys.exit(f'no EPUB under {path}')
    return found[0]


def rows(epub):
    with zipfile.ZipFile(epub) as archive:
        container = ET.fromstring(archive.read('META-INF/container.xml'))
        opf_path = next(e.get('full-path') for e in container.iter() if e.get('full-path'))
        opf = ET.fromstring(archive.read(opf_path))
        base = pathlib.PurePosixPath(opf_path).parent
        items = {item.get('id'): item.get('href') for item in opf.iter(OPF + 'item')}
        page = None
        for ref in opf.iter(OPF + 'itemref'):
            document = ET.fromstring(archive.read(str(base / items[ref.get('idref')])))
            for element in document.iter():
                if element.get('{http://www.idpf.org/2007/ops}type') == 'pagebreak' and element.get('id', '').startswith('page-'):
                    page = int(element.get('id')[5:])
                if element.tag == HTML + 'figure':
                    captioned = element.find(HTML + 'figcaption') is not None
                    for image in element.iter(HTML + 'img'):
                        yield page, image.get('alt', ''), image.get('title', ''), captioned


def main():
    for page, alt, title, captioned in rows(epub_of(sys.argv[1])):
        print(f'{page}\t{kind_of(alt)}\t{alt}\t{title}\t{"figcaption" if captioned else "-"}')


if __name__ == '__main__':
    main()
