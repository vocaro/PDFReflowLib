#!/usr/bin/env python3
"""usage: textdiff.py <baseline.epub> <candidate.epub>

Reads both EPUBs' spine text page by page (tools/check_corpus_content.read_pages) and reports
(1) pages whose text differs, (2) pages that still differ once the baseline's U+FB00-U+FB06 are
spelled out as the candidate spells them, i.e. any text change other than the ligatures, and
(3) the same for every other text entry of the package (OPF, nav), and raw bytes of non-text entries."""
import re
import sys
import zipfile
sys.path.insert(0, str(__import__('pathlib').Path(__file__).resolve().parents[3] / 'tools'))
from check_corpus_content import read_pages

TABLE = {'ﬀ': 'ff', 'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬃ': 'ffi', 'ﬄ': 'ffl', 'ﬅ': 'ſt', 'ﬆ': 'st'}
LIG = re.compile('[ﬀ-ﬆ]')


def spelled(text):
    return LIG.sub(lambda m: TABLE[m.group(0)], text)


base, cand = sys.argv[1], sys.argv[2]
limits = dict(max_entries=20000, max_uncompressed_bytes=4294967296)
bp, _ = read_pages(base, **limits)
cp, _ = read_pages(cand, **limits)
changed = [n for n in sorted(set(bp) | set(cp)) if bp.get(n, {}).get('text') != cp.get(n, {}).get('text')]
other = [n for n in changed if spelled(bp.get(n, {}).get('text', '')) != cp.get(n, {}).get('text', '')]
ligatures_left = sum(len(LIG.findall(p['text'])) for p in cp.values())
print(f'pages {len(bp)}/{len(cp)}; text differs on {len(changed)} pages; differs beyond ligatures on {len(other)} {other[:10]}; '
      f'ligatures left in candidate text {ligatures_left}')
for n in other[:3]:
    a, b = spelled(bp[n]['text']), cp[n]['text']
    i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
    print(f'  p{n}: base …{a[max(0, i - 60):i + 60]!r}\n        cand …{b[max(0, i - 60):i + 60]!r}')
za, zb = zipfile.ZipFile(base), zipfile.ZipFile(cand)
na, nb = za.namelist(), zb.namelist()
if na != nb:
    print('  entry lists differ:', sorted(set(na) ^ set(nb))[:10])
text_other, binary_other = [], []
for name in sorted(set(na) & set(nb)):
    a, b = za.read(name), zb.read(name)
    if a == b:
        continue
    if name.endswith(('.xhtml', '.opf', '.ncx', '.css', '.html', '.xml')):
        if spelled(a.decode('utf-8')) != b.decode('utf-8'):
            text_other.append(name)
    else:
        binary_other.append(name)
print(f'entries: text entries differing beyond ligatures {len(text_other)} {text_other[:8]}; other entries differing {len(binary_other)} {binary_other[:8]}')
