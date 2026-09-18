import sys, re, zipfile, hashlib
# usage: imgdiff.py base.epub cand.epub: pages whose image bytes (in order) differ
def pages(path):
    z = zipfile.ZipFile(path)
    files = sorted((x for x in z.namelist() if x.endswith('.xhtml') and 'nav' not in x),
                   key=lambda n: [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', n)])
    body = ''.join(z.read(n).decode() for n in files)
    out, current = {}, None
    for part in re.split(r'(<span[^>]*epub:type="pagebreak"[^>]*/?>)', body):
        m = re.search(r'aria-label="(\d+)"', part) if 'pagebreak' in part else None
        if m: current = int(m.group(1)); out[current] = []
        elif current is not None:
            for src in re.findall(r'<img[^>]*src="([^"]+)"', part):
                out[current].append(hashlib.sha256(z.read('EPUB/' + src)).hexdigest()[:12])
    return out
a, b = pages(sys.argv[1]), pages(sys.argv[2])
print([n for n in sorted(set(a) | set(b)) if a.get(n) != b.get(n)])
