"""Split-sentence recount: an open paragraph followed, past figures, captions, headings and page
breaks, by a paragraph that continues the sentence.

usage: recount.py book.epub [--json out.json] [--all]
Each candidate: page of P's end, page of Q, the kinds between (I image, C caption, H heading, B page break,
L list item, R pre/list), P tail, Q head, and the class of Q's opening (lower, digit, other).
"""
import json
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

X = '{http://www.w3.org/1999/xhtml}'
E = '{http://www.idpf.org/2007/ops}'


def blocks(path):
    z = zipfile.ZipFile(path)
    opf = ET.fromstring(z.read('EPUB/package.opf'))
    ns = '{http://www.idpf.org/2007/opf}'
    manifest = {e.get('id'): e.get('href') for e in opf.find(ns + 'manifest')}
    page = 0
    out = []
    for ref in opf.find(ns + 'spine'):
        tree = ET.fromstring(z.read('EPUB/' + manifest[ref.get('idref')]))
        body = tree.find(X + 'body')
        for e in body:
            tag = e.tag[len(X):]
            if tag == 'span' and 'pagebreak' in e.get(E + 'type', ''):
                page = int(e.get('id')[5:])
                out.append(('B', '', page, page))
                continue
            start = page
            # inline page markers inside a joined block
            for s in e.iter(X + 'span'):
                if 'pagebreak' in s.get(E + 'type', ''):
                    page = int(s.get('id')[5:])
            text = ''.join(e.itertext()).strip()
            if tag == 'figure':
                kind = 'I'
            elif tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
                kind = 'H'
            elif tag == 'pre':
                kind = 'R'
            elif tag == 'p':
                kind = 'C' if re.match(r'^(Figure|Table)\s+[0-9]', text) else 'P'
            elif tag == 'aside':
                kind = 'N'
            else:
                kind = tag
            out.append((kind, text, start, page))
    return out


CLOSING = '”’"\')]'


def open_end(text):
    t = re.sub(r'\s*\[(?:Figures?|Tables?)[^\]]*\]\s*$', '', text.rstrip())
    t = t.rstrip().rstrip(CLOSING).rstrip()
    t = re.sub(r'[¹²³⁰-⁹]+$', '', t)
    return bool(t) and t[-1] not in '.!?:'


def main():
    bs = blocks(sys.argv[1])
    cands = []
    for i, (k, t, p0, p1) in enumerate(bs):
        if k not in ('P', 'R') or not open_end(t) or '\n' in t:
            continue
        j = i + 1
        between = ''
        while j < len(bs) and bs[j][0] in 'ICHBN':
            between += bs[j][0]
            j += 1
        if j >= len(bs) or bs[j][0] not in ('P',):
            continue
        q = bs[j][1]
        if not q:
            continue
        stripped = between.replace('B', '')
        if not stripped and '--all' not in sys.argv:
            continue
        c = q[0]
        opening = 'lower' if c.islower() else 'digit' if c.isdigit() else 'upper' if c.isupper() else 'other'
        cands.append({'end_page': p1, 'next_page': bs[j][2], 'between': between, 'opening': opening,
                      'kind': k, 'end': t[-100:], 'next': q[:100], 'words': len(t.split())})
    for c in cands:
        print(f"p{c['end_page']}->{c['next_page']} {c['kind']} [{c['between']}] {c['opening']:5} "
              f"w{c['words']} …{c['end'][-50:]!r} ‖ {c['next'][:50]!r}")
    from collections import Counter
    print(Counter(c['opening'] for c in cands), len(cands))
    if '--json' in sys.argv:
        json.dump(cands, open(sys.argv[sys.argv.index('--json') + 1], 'w'), indent=1)


main()
