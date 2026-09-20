#!/usr/bin/env python3
"""Capture one corpus page's tag evidence: content stream, fonts and structure subtree.

Usage: capture_tag_fixture.py <pdf> <page> <out.json> <note>

Reads with qpdf only; nothing is modified. What is captured is the page's own bytes:
  * `contentStream` - the page's content stream exactly as the source stores it, decoded.
  * `fonts` - each font resource's subtype, encoding name and decoded ToUnicode map.
  * `elements` - every structure element the page's ParentTree entry names, with every
    ancestor up to the tree root, each with its role, parent, and children in source order
    (an MCID integer, or another captured element). Elements outside this page are pruned.
  * `parentTree` - the page's ParentTree entry: the element that owns each MCID.
  * `roleMap`, `xobjects`, `mediaBox` - the rest of what a tag reader resolves on the page.

The result is read by `SourceTagFixture` in the test target, which replays it as a one-page
document. Nothing here is reconstruction output: every field is the source PDF's own.
"""
import hashlib
import json
import re
import subprocess
import sys


def show(pdf, n, filtered=False):
    cmd = ['qpdf', '--show-object=%s' % n, pdf]
    if filtered:
        cmd.insert(2, '--filtered-stream-data')
    return subprocess.run(cmd, capture_output=True).stdout.decode('latin-1')


def pagemap(pdf):
    out = subprocess.run(['qpdf', '--show-pages', pdf], capture_output=True, text=True).stdout
    pages, cur = {}, None
    for line in out.splitlines():
        m = re.match(r'page (\d+): (\d+) 0 R', line)
        if m:
            cur = int(m.group(1))
            pages[cur] = {'page': int(m.group(2)), 'contents': []}
            continue
        m = re.match(r'\s+(\d+) 0 R', line)
        if m and cur:
            pages[cur]['contents'].append(int(m.group(1)))
    return pages


def nums_entry(text, key):
    """The value of `key` in a /Nums array: an inline array's text, or `N 0 R`."""
    m = re.search(r'/Nums \[', text)
    if not m:
        return None
    i, end = m.end(), len(text)
    while i < end:
        while i < end and text[i] in ' \r\n\t':
            i += 1
        if i >= end or text[i] == ']':
            return None
        number = re.match(r'-?\d+', text[i:])
        if not number:
            return None
        candidate = int(number.group(0))
        i += number.end()
        while i < end and text[i] in ' \r\n\t':
            i += 1
        if text[i] == '[':
            depth, start = 0, i
            while i < end:
                if text[i] == '[':
                    depth += 1
                elif text[i] == ']':
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
            value = text[start:i]
        else:
            ref = re.match(r'\d+ 0 R', text[i:])
            if not ref:
                return None
            value = ref.group(0)
            i += ref.end()
        if candidate == key:
            return value
    return None


def parent_entry(pdf, tree, key):
    s = show(pdf, tree)
    m = re.search(r'/Limits \[ (-?\d+) (-?\d+) \]', s)
    if m and not (int(m.group(1)) <= key <= int(m.group(2))):
        return None
    value = nums_entry(s, key)
    if value is not None:
        return show(pdf, int(value.split()[0])) if value.endswith('0 R') else value
    m = re.search(r'/Kids \[(.*?)\]', s, re.S)
    if m:
        for ref in re.findall(r'(\d+) 0 R', m.group(1)):
            found = parent_entry(pdf, int(ref), key)
            if found is not None:
                return found
    return None


def kids_of(text):
    """The /K value as a list of MCID integers and element references, in source order."""
    m = re.search(r'/K (\[.*?\]|\d+ 0 R|\d+)', text, re.S)
    if not m:
        return []
    body = m.group(1)
    if not body.startswith('['):
        ref = re.match(r'(\d+) 0 R', body)
        return [{'element': int(ref.group(1))}] if ref else [int(body)]
    result = []
    for token in re.findall(r'\d+ 0 R|\d+', body[1:-1]):
        ref = re.match(r'(\d+) 0 R', token)
        result.append({'element': int(ref.group(1))} if ref else int(token))
    return result


def fonts(pdf, page):
    entry = re.search(r'/Font << (.*?) >>', page)
    if not entry:
        return []
    result = []
    for name, ref in re.findall(r'/(\S+) (\d+) 0 R', entry.group(1)):
        dictionary = show(pdf, ref)
        subtype = re.search(r'/Subtype /(\w+)', dictionary)
        encoding = re.search(r'/Encoding /(\w+)', dictionary)
        encodingRef = re.search(r'/Encoding (\d+) 0 R', dictionary)
        unicodeRef = re.search(r'/ToUnicode (\d+) 0 R', dictionary)
        item = {'name': name, 'object': '%s 0 R' % ref,
                'subtype': subtype.group(1) if subtype else None,
                'encoding': encoding.group(1) if encoding else None}
        if encodingRef:
            base = re.search(r'/BaseEncoding /(\w+)', show(pdf, encodingRef.group(1)))
            item['encoding'] = base.group(1) if base else None
            item['encodingFromDictionary'] = True
        if unicodeRef:
            item['toUnicode'] = show(pdf, unicodeRef.group(1), filtered=True)
        result.append(item)
    return result


def xobjects(pdf, page):
    entry = re.search(r'/XObject << (.*?) >>', page)
    if not entry:
        return []
    result = []
    for name, ref in re.findall(r'/(\S+) (\d+) 0 R', entry.group(1)):
        subtype = re.search(r'/Subtype /(\w+)', show(pdf, ref))
        result.append({'name': name, 'object': '%s 0 R' % ref,
                       'subtype': subtype.group(1) if subtype else None})
    return result


def main():
    pdf, number, out, note = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
    digest = hashlib.sha256(open(pdf, 'rb').read()).hexdigest()
    entry = pagemap(pdf)[number]
    stream = ''.join(show(pdf, c, filtered=True) for c in entry['contents'])
    page = show(pdf, entry['page'])
    key = int(re.search(r'/StructParents (\d+)', page).group(1))
    catalog = int(re.search(r'/Root (\d+) 0 R', show(pdf, 'trailer')).group(1))
    root = int(re.search(r'/StructTreeRoot (\d+) 0 R', show(pdf, catalog)).group(1))
    rootText = show(pdf, root)
    tree = int(re.search(r'/ParentTree (\d+) 0 R', rootText).group(1))
    roleMap = {}
    mapRef = re.search(r'/RoleMap (\d+) 0 R', rootText)
    if mapRef:
        roleMap = dict(re.findall(r'/(\w+) /(\w+)', show(pdf, int(mapRef.group(1)))))
    array = parent_entry(pdf, tree, key)
    tokens = re.findall(r'null|\d+ 0 R', array[array.index('[') + 1:array.rindex(']')])
    owners = {}
    for mcid, token in enumerate(tokens):
        if token != 'null':
            owners[mcid] = int(token.split()[0])

    elements, order = {}, []

    def capture(node):
        if node in elements or node == root:
            return
        text = show(pdf, node)
        role = re.search(r'/S /(\w+)', text)
        parent = re.search(r'/P (\d+) 0 R', text)
        elements[node] = {
            'object': node,
            'role': role.group(1) if role else None,
            'parent': int(parent.group(1)) if parent else None,
            'page': bool(re.search(r'/Pg \d+ 0 R', text)),
            'kids': kids_of(text),
        }
        order.append(node)
        if parent:
            capture(int(parent.group(1)))

    for node in set(owners.values()):
        capture(node)
    # Prune children that are neither this page's MCIDs nor captured elements. An integer kid is
    # this element's only where the page's ParentTree names this element as that MCID's owner:
    # a list or a paragraph that continues onto the next page carries that page's MCIDs too, and
    # they collide with this page's own numbering, which a reader then reads as duplicates.
    known = set(elements)
    for node, item in elements.items():
        item['kids'] = [k for k in item['kids']
                        if (isinstance(k, int) and owners.get(k) == node) or
                        (isinstance(k, dict) and k['element'] in known)]
    rootKids = [n for n, item in elements.items() if item['parent'] is None or item['parent'] == root]
    for n in rootKids:
        elements[n]['parent'] = None
    json.dump({
        'sourceSHA256': digest,
        'page': number,
        'contentObjects': ['%s 0 R' % c for c in entry['contents']],
        'mediaBox': [float(v) for v in re.search(r'/MediaBox \[ ([-0-9. ]+) \]', page).group(1).split()],
        'structParents': key,
        'structureRoot': root,
        'roleMap': roleMap,
        'rootKids': sorted(rootKids),
        'parentTree': {str(k): v for k, v in sorted(owners.items())},
        'elements': [elements[n] for n in sorted(elements)],
        'fonts': fonts(pdf, page),
        'xobjects': xobjects(pdf, page),
        'contentStream': stream,
        'provenance': note,
    }, open(out, 'w'), indent=2)
    print(out, len(stream), 'bytes,', len(elements), 'elements,', len(owners), 'MCIDs, rootKids', rootKids)


main()
