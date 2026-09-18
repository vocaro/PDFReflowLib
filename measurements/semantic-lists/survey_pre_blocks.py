#!/usr/bin/env python3
"""Survey the `<pre>` blocks an EPUB emits, for issue #29 (semantic lists).

Reads the spine in order, tracks `epub:type="pagebreak"` markers, and writes one JSON
record per `<pre>` element: source page, spine file, ordinal, the block's lines (its own
line breaks preserved), whether it is monospaced, and the marker its first line opens with.

Classification is advisory: the record's prose is the authority. This only measures.
"""

import argparse
import json
import re
import sys
import zipfile
from pathlib import PurePosixPath
import xml.etree.ElementTree as ET

HTML = '{http://www.w3.org/1999/xhtml}'
OPF = '{http://www.idpf.org/2007/opf}'
EPUB = '{http://www.idpf.org/2007/ops}'

# The library's own list test, LayoutReconstructor.isList.
IS_LIST = re.compile(r'^(?:(?:[•*−-]|[0-9]+[.)]|[A-Za-z][.)])\s|[0-9]+\)−)')
MARKER = re.compile(r'^(?:[0-9]{1,9}|[A-Za-z])([.)])(?=\s)')
BULLET = re.compile(r'^([•*−●▪–-])\s')


def text_of(element):
    """All text under `element`, with <br/> and block children as newlines."""
    parts = []

    def walk(node):
        if node.tag == HTML + 'br':
            parts.append('\n')
        if node.text:
            parts.append(node.text)
        for child in node:
            walk(child)
            if child.tail:
                parts.append(child.tail)

    walk(element)
    return ''.join(parts)


def marker_of(line):
    """(kind, punctuation, value) for a numbered/lettered marker, else None."""
    match = MARKER.match(line)
    if not match:
        return None
    token = line[:match.start(1)]
    if token.isdigit():
        return ('digit', match.group(1), int(token))
    return ('upper' if token.isupper() else 'lower', match.group(1), ord(token))


TOP_LEVEL = {HTML + tag for tag in ('p', 'pre', 'figure', 'table', 'div',
                                    'h1', 'h2', 'h3', 'h4', 'h5', 'h6')}


def survey(path):
    """Every `<pre>` block, plus `flow`, its position among the chapter's top-level blocks,
    so a run of list items interrupted by a paragraph or a figure can be recognised."""
    blocks = []
    with zipfile.ZipFile(path) as archive:
        package = ET.fromstring(archive.read('EPUB/package.opf'))
        manifest = {e.get('id'): e.get('href') for e in package.find(OPF + 'manifest')}
        ordinal = 0
        flow = 0
        page = None
        for reference in package.find(OPF + 'spine'):
            chapter = PurePosixPath('EPUB') / manifest[reference.get('idref')]
            tree = ET.fromstring(archive.read(str(chapter)))
            body = tree.find(HTML + 'body')
            stack = [body] if body is not None else [tree]

            def walk(element, top):
                nonlocal page, ordinal, flow
                if 'pagebreak' in element.get(EPUB + 'type', '').split():
                    marker = element.get('id', '')
                    if re.fullmatch(r'page-[1-9]\d*', marker):
                        page = int(marker[5:])
                if element.tag in TOP_LEVEL and top:
                    flow += 1
                if element.tag == HTML + 'pre':
                    ordinal += 1
                    raw = text_of(element)
                    lines = [line for line in raw.split('\n')]
                    first = lines[0] if lines else ''
                    blocks.append({
                        'ordinal': ordinal,
                        'flow': flow,
                        'page': page,
                        'file': chapter.name,
                        'lines': lines,
                        'lineCount': len(lines),
                        'characters': len(raw),
                        'isList': bool(IS_LIST.match(first)),
                        'marker': marker_of(first),
                        'bullet': (BULLET.match(first).group(1) if BULLET.match(first) else None),
                        'hasSup': element.find('.//' + HTML + 'sup') is not None,
                        'hasSub': element.find('.//' + HTML + 'sub') is not None,
                        'hasAnchor': element.find('.//' + HTML + 'a') is not None,
                    })
                    return
                for child in element:
                    walk(child, top and element.tag not in TOP_LEVEL)

            for child in stack[0]:
                walk(child, True)
    return blocks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('epub')
    parser.add_argument('--case', required=True)
    parser.add_argument('--output', required=True)
    arguments = parser.parse_args()
    blocks = survey(arguments.epub)
    with open(arguments.output, 'w') as handle:
        json.dump({'case': arguments.case, 'blocks': blocks}, handle)
    pages = {b['page'] for b in blocks}
    print(f'{arguments.case}: {len(blocks)} <pre> blocks on {len(pages)} pages', file=sys.stderr)


if __name__ == '__main__':
    main()
