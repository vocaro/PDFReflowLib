import zipfile, re, collections, json, sys

epub = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else None
z = zipfile.ZipFile(epub)
sizes = {i.filename.split('/')[-1]: i.file_size for i in z.infolist()
         if i.filename.lower().endswith(('.png', '.jpg', '.jpeg'))}
img = {}
for n in z.namelist():
    if not n.endswith('.xhtml'):
        continue
    t = z.read(n).decode('utf8', errors='replace')
    for m in re.finditer(r'<img[^>]*>', t):
        s = m.group(0)
        src = re.search(r'src="([^"]+)"', s).group(1).split('/')[-1]
        alt = (re.search(r'alt="([^"]*)"', s) or [None, ''])[1] if re.search(r'alt="([^"]*)"', s) else ''
        alt = re.search(r'alt="([^"]*)"', s).group(1) if re.search(r'alt="([^"]*)"', s) else ''
        pm = re.search(r'page (\d+)', alt)
        kind = 'reference' if alt.startswith('Original page') else 'region'
        img[src] = (int(pm.group(1)) if pm else None, kind, alt, sizes.get(src, 0))

mib = lambda b: round(b / 1048576, 2)
entry = sum(i.file_size for i in z.infolist())
print('entry bytes', entry, mib(entry), 'MiB;  images', len(sizes), mib(sum(sizes.values())), 'MiB')
for kind in ('reference', 'region'):
    sel = [v for v in img.values() if v[1] == kind]
    print(f'{kind}: {len(sel)} assets, {mib(sum(v[3] for v in sel))} MiB, '
          f'mean {round(sum(v[3] for v in sel)/max(1,len(sel))/1024)} KiB')
byp = collections.Counter()
kindp = collections.defaultdict(set)
for p, k, a, b in img.values():
    byp[p] += b
    kindp[p].add(k)
print('pages with any image:', len(byp))
both = [p for p, ks in kindp.items() if len(ks) > 1]
print('pages with both a reference and regions:', len(both), sorted(both)[:30])
print('top 12 pages by bytes:', [(p, mib(b)) for p, b in byp.most_common(12)])
if out:
    json.dump({s: list(v) for s, v in img.items()}, open(out, 'w'))
