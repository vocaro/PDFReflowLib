import sys, zipfile, re, hashlib
import xml.etree.ElementTree as ET
H = '{http://www.w3.org/1999/xhtml}'
epub, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(epub) as z:
    names = z.namelist()
    nav = [n for n in names if n.endswith('nav.xhtml')]
    root = ET.fromstring(z.read(nav[0]))
    lines = []
    def walk(ol, depth):
        for li in ol.findall(H + 'li'):
            a = li.find(H + 'a')
            if a is not None:
                t = re.sub(r'\s+', ' ', ''.join(a.itertext())).strip()
                lines.append(f'{depth}\t{a.get("href").split("#")[0]}\t{t}')
            for sub in li.findall(H + 'ol'):
                walk(sub, depth + 1)
    for n in root.iter(H + 'nav'):
        if 'toc' in (n.get('{http://www.idpf.org/2007/ops}type') or ''):
            for ol in n.findall(H + 'ol'):
                walk(ol, 1)
    open(out + '.nav', 'w').write('\n'.join(lines) + '\n')
    imgs = sorted(hashlib.sha256(z.read(n)).hexdigest()[:16] + ' ' + n for n in names
                  if re.search(r'\.(png|jpe?g|gif|svg)$', n))
    open(out + '.img', 'w').write('\n'.join(imgs) + '\n')
print(f'nav={len(lines)} images={len(imgs)}')
