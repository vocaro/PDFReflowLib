"""Page-level diff of two EPUBs' spine text split at page markers; prints changed pages' markup lines."""
import re, sys, zipfile, difflib

def pages(path):
    z = zipfile.ZipFile(path)
    names = sorted((n for n in z.namelist() if n.endswith('.xhtml') and 'nav' not in n),
                   key=lambda n: [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', n)])
    text = ''.join(z.read(n).decode('utf-8') for n in names)
    parts = re.split(r'<span epub:type="pagebreak"[^>]*id="page-(\d+)"[^>]*/>', text)
    out = {}
    for i in range(1, len(parts), 2):
        body = re.sub(r'id="[^"]*"', '', parts[i + 1])
        body = re.sub(r'image-\d+\.(png|jpg)', 'IMG', body)
        body = re.sub(r'<(/?)(html|head|body)[^>]*>|<title>.*?</title>|<\?xml[^>]*\?>|<!DOCTYPE[^>]*>|<link[^>]*/>', '', body)
        out[int(parts[i])] = [l for l in re.split(r'(?=<(?:p|h\d|figure|li|pre|aside|table)\b)', body) if l.strip()]
    return out, z

a, za = pages(sys.argv[1])
b, zb = pages(sys.argv[2])
changed = [p for p in sorted(set(a) | set(b)) if a.get(p) != b.get(p)]
print('changed pages', changed)
for p in changed[:40]:
    print(f'--- page {p}')
    for l in difflib.unified_diff(a.get(p, []), b.get(p, []), lineterm='', n=0):
        if l.startswith(('---', '+++', '@@')):
            continue
        print('  ' + l[:400].replace('\n', ' '))
ia = sorted(n for n in za.namelist() if 'images/' in n)
ib = sorted(n for n in zb.namelist() if 'images/' in n)
print('images', len(ia), '->', len(ib))
