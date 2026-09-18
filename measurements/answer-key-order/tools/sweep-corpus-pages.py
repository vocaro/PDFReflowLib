#!/usr/bin/env python3
"""Convert each cached corpus source with both CLIs and report any page whose blocks differ.

Each pair of EPUBs is deleted as soon as its pages are read, so at most two outputs exist at a
time. Prints one line per case: the pages that differ, or `identical`. A copy of
`measurements/answer-key-columns/sweep-corpus-pages.py` with its paths taken from the command line:

    sweep-corpus-pages.py <baseline CLI> <candidate CLI> <scratch directory> <case-id> ...
"""
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import PurePosixPath

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
BASELINE, CANDIDATE, SCRATCH = sys.argv[1:4] if len(sys.argv) > 3 else (None, None, None)
OPF = '{http://www.idpf.org/2007/opf}'
HTML = '{http://www.w3.org/1999/xhtml}'
EPUB = '{http://www.idpf.org/2007/ops}'
BLOCKS = {HTML + t for t in ('p', 'pre', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'figure', 'table')}


def pages(path):
    out = {}
    with zipfile.ZipFile(path) as ar:
        package = ET.fromstring(ar.read('EPUB/package.opf'))
        manifest = {e.get('id'): e.get('href') for e in package.find(OPF + 'manifest')}
        current = None
        for ref in package.find(OPF + 'spine'):
            chapter = PurePosixPath('EPUB') / manifest[ref.get('idref')]
            tree = ET.fromstring(ar.read(str(chapter)))
            for block in tree.find(HTML + 'body').iter():
                if 'pagebreak' in block.get(EPUB + 'type', '').split():
                    mid = block.get('id', '')
                    current = int(mid[5:]) if mid.startswith('page-') else None
                    continue
                if block.tag not in BLOCKS or current is None:
                    continue
                text = []
                for e in block.iter():
                    if e.tag == HTML + 'img':
                        text.append('[IMG]')
                    if e.text:
                        text.append(e.text)
                    if e is not block and e.tail:
                        text.append(e.tail)
                value = re.sub(r'\s+', ' ', ''.join(text)).strip()
                if value:
                    out.setdefault(current, []).append(block.tag[len(HTML):] + ' ' + value)
    return out


def convert(binary, source, out):
    subprocess.run([binary, source, out, '--package-identifier', 'urn:uuid:test',
                    '--modification-date', '2026-01-01T00:00:00Z'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)


def main(ids):
    manifest = json.load(open(os.path.join(ROOT, 'corpus/manifest.json')))
    documents = {d['id']: d['filename'] for d in manifest['documents']}
    for case in ids:
        source = os.path.join(ROOT, 'corpus/cache', documents[case])
        base, cand = SCRATCH + '/sweep-base.epub', SCRATCH + '/sweep-cand.epub'
        try:
            convert(BASELINE, source, base)
            convert(CANDIDATE, source, cand)
            a, b = pages(base), pages(cand)
            changed = sorted(n for n in set(a) | set(b) if a.get(n) != b.get(n))
            print(case, 'changed' if changed else 'identical', changed, flush=True)
        except Exception as error:                       # noqa: BLE001 - a survey, not a gate
            print(case, 'ERROR', error, flush=True)
        finally:
            for path in (base, cand):
                if os.path.exists(path):
                    os.remove(path)
            free = shutil.disk_usage('/System/Volumes/Data').free / 2**30
        if free < 8:
            print('stopping: %.1f GiB free' % free)
            return


if __name__ == '__main__':
    main(sys.argv[4:])
