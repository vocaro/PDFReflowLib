"""digest.py <name>: condense out/<name>.epub + out/<name>.log into out/<name>.digest.json.gz, then delete both."""
import gzip, hashlib, json, re, sys, zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

W = Path('/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a90893956cdc3fa18')
sys.path.insert(0, str(W / 'tools'))
import check_corpus_content as checker  # noqa

S = Path(__file__).resolve().parent / 'out'
name = sys.argv[1]
keep = '--keep' in sys.argv
epub, log = S / f'{name}.epub', S / f'{name}.log'
raw = log.read_text(errors='replace')
start = raw.rfind('\n{\n')
result = json.loads(raw[start + 1:])
warnings = [(w['code'], w.get('page'), w.get('message', '')) for w in result['warnings']]
pages, _ = checker.read_pages(epub)
digest = {'epubSHA256': hashlib.sha256(epub.read_bytes()).hexdigest(),
          'summary': {k: v for k, v in result.items() if k != 'warnings'},
          'warnings': warnings, 'pages': {}, 'nav': [], 'images': {}}
for number, page in pages.items():
    digest['pages'][number] = {'text': checker.normalized(page['text']),
        'headings': list(page['headings']), 'paragraphs': list(page['paragraphs']),
        'listItems': list(page['listItems']), 'images': len(page['images'])}
with zipfile.ZipFile(epub) as archive:
    for entry in archive.namelist():
        if '/images/' in entry:
            digest['images'][entry] = hashlib.sha256(archive.read(entry)).hexdigest()
    for entry in archive.namelist():
        if entry.endswith('nav.xhtml'):
            tree = ET.fromstring(archive.read(entry))
            H = '{http://www.w3.org/1999/xhtml}'
            def walk(el, depth):
                for li in el.findall(H + 'li'):
                    a = li.find(H + 'a')
                    if a is not None:
                        digest['nav'].append([depth, ''.join(a.itertext()).strip(), a.get('href')])
                    for ol in li.findall(H + 'ol'):
                        walk(ol, depth + 1)
            for nav in tree.iter(H + 'nav'):
                if 'toc' in nav.get('{http://www.idpf.org/2007/ops}type', ''):
                    for ol in nav.findall(H + 'ol'):
                        walk(ol, 1)
out = S / f'{name}.digest.json.gz'
with gzip.open(out, 'wt') as handle:
    json.dump(digest, handle)
codes = {}
for code, _, _ in warnings:
    codes[code] = codes.get(code, 0) + 1
print(name, digest['epubSHA256'][:12], 'warnings', len(warnings), 'structureFallback pages',
      len({p for c, p, _ in warnings if c == 'structureFallback'}), 'nav', len(digest['nav']), 'pages', len(pages),
      'images', len(digest['images']))
if not keep:
    epub.unlink(); log.unlink()
