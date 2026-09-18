import sys, re, html, zipfile, difflib

# usage: pagediff.py base.epub cand.epub [--detail]: pages whose blocks differ, with a unified diff
def pages(path):
    z = zipfile.ZipFile(path)
    files = sorted((x for x in z.namelist() if x.endswith('.xhtml') and 'nav' not in x),
                   key=lambda n: [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', n)])
    body = ''.join(re.sub(r'<head>.*?</head>', '', z.read(n).decode(), flags=re.S) for n in files)
    parts = re.split(r'(<span[^>]*epub:type="pagebreak"[^>]*/?>)', body)
    out, current = {}, None
    for part in parts:
        m = re.search(r'aria-label="(\d+)"', part) if 'pagebreak' in part else None
        if m:
            current = int(m.group(1)); out.setdefault(current, '')
        elif current is not None:
            out[current] += part
    result = {}
    for n, s in out.items():
        blocks = []
        for kind, inner in re.findall(r'<(h[1-6]|p|pre|figure|li|tr)\b[^>]*>(.*?)</\1>', s, re.S):
            text = html.unescape(re.sub(r'<[^>]+>', ' ', inner))
            text = re.sub(r'\s+', ' ', text).strip()
            blocks.append(f'{kind}: [img]' if kind == 'figure' else f'{kind}: {text}')
        result[n] = blocks
    return result

a, b = pages(sys.argv[1]), pages(sys.argv[2])
detail = '--detail' in sys.argv
changed = [n for n in sorted(set(a) | set(b)) if a.get(n) != b.get(n)]
print('changed pages:', len(changed), changed)
if detail:
    for n in changed:
        print(f'==== page {n}')
        for line in difflib.unified_diff(a.get(n, []), b.get(n, []), lineterm='', n=0):
            if line.startswith(('---', '+++', '@@')): continue
            print('  ' + line[:260])
