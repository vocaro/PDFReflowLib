"""Independent before/after check: chapter starts, complete body markup, assets and links."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import read_pages

HTML = '{http://www.w3.org/1999/xhtml}'
OPF = '{http://www.idpf.org/2007/opf}'


def inspect(path):
    bodies, starts, images, targets, links = [], [], {}, {}, []
    with zipfile.ZipFile(path) as archive:
        assert len(archive.infolist()) <= 20_000
        assert sum(e.file_size for e in archive.infolist()) <= 4 * 1024**3
        package = ET.fromstring(archive.read('EPUB/package.opf'))
        manifest = {e.get('id'): e.get('href') for e in package.find(OPF + 'manifest')}
        for item in package.find(OPF + 'spine'):
            name = 'EPUB/' + manifest[item.get('idref')]
            data = archive.read(name)
            body = data.split(b'<body>', 1)[1].split(b'</body>', 1)[0]
            bodies.append(body)
            tree = ET.fromstring(data)
            first = tree.find(HTML + 'body')[0]
            starts.append({'file': name, 'firstID': first.get('id'), 'bodyBytes': len(body)})
            targets[name] = first.get('id') or 'document-start'
            targets.update({name + '#' + e.get('id'): e.get('id') for e in tree.iter() if e.get('id')})
        for entry in archive.infolist():
            if entry.filename.startswith('EPUB/images/'):
                with archive.open(entry) as stream:
                    images[entry.filename] = hashlib.file_digest(stream, 'sha256').hexdigest()
        nav = ET.fromstring(archive.read('EPUB/nav.xhtml'))
        for e in nav.iter(HTML + 'a'):
            target = 'EPUB/' + e.get('href')
            assert target in targets, target
            links.append((targets[target], ''.join(e.itertext())))
    pages, markers = read_pages(path, max_entries=20_000, max_uncompressed_bytes=4 * 1024**3)
    return {'body': b''.join(bodies), 'starts': starts, 'images': images,
            'links': links, 'pages': pages, 'markers': markers}


def compare(before, after, chapter_pages):
    old, new = inspect(before), inspect(after)
    assert old['body'] == new['body'], 'Source block markup changed'
    assert old['images'] == new['images'], 'Image bytes changed'
    assert old['pages'] == new['pages'], 'Page text, styles, images or block semantics changed'
    assert old['markers'] == new['markers'], 'Page anchors changed'
    assert old['links'] == new['links'], 'Navigation text or destination identity changed'
    old_starts = {e['firstID'] for e in old['starts']}
    new_starts = {e['firstID'] for e in new['starts']}
    assert all(f'page-{p}' in new_starts for p in chapter_pages), 'Chapter opening is not a spine start'
    return {'beforeSpineCount': len(old['starts']), 'afterSpineCount': len(new['starts']),
            'pages': len(new['markers']), 'identicalImages': len(new['images']),
            'completeBodyMarkupIdentical': True, 'pageSemanticsIdentical': True, 'navigationTargetsIdentical': True,
            'chapterPages': chapter_pages,
            'baselineMissingChapterStarts': [p for p in chapter_pages if f'page-{p}' not in old_starts],
            'newSpineDocuments': new['starts'],
            'bodySHA256': hashlib.sha256(new['body']).hexdigest()}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path)
    parser.add_argument('after', type=Path)
    parser.add_argument('--noaa', action='store_true')
    args = parser.parse_args()
    chapters = json.loads((ROOT / 'corpus/noaa-nca5-2023-chapters.json').read_text())['chapters'] if args.noaa else []
    print(json.dumps(compare(args.before, args.after, [c['startPage'] for c in chapters]), indent=2))
