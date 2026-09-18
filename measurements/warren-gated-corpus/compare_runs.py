import json, sys, zipfile, hashlib, re
a_dir, b_dir = sys.argv[1], sys.argv[2]
for d in (a_dir, b_dir):
    r = json.load(open(d + '/result.json'))
    z = zipfile.ZipFile(d + '/gpo-warren-1964.epub')
    entry = sum(i.file_size for i in z.infolist())
    print(d.rsplit('/', 1)[-1], json.dumps({
        'seconds': round(r['conversionSeconds'], 1), 'cpu': round(r['converterCPUSeconds'], 1),
        'rssMiB': round(r['converterPeakRSSBytes'] / 2**20, 1),
        'footprintMiB': round(r.get('converterPeakPhysicalFootprintBytes', 0) / 2**20, 1),
        'epubBytes': r['outputBytes'], 'entryBytes': entry, 'headroom': 512 * 2**20 - entry,
        'memoryGate': r.get('memoryGate', {}).get('passed'), 'runPassed': r.get('runPassed'),
        'ocrPages': r['conversionReport']['recognizedPageCount'], 'images': r['conversionReport']['imageCount'],
        'epubcheck': open(d + '/epubcheck.log').read().strip().splitlines()[-3]}))
za, zb = zipfile.ZipFile(a_dir + '/gpo-warren-1964.epub'), zipfile.ZipFile(b_dir + '/gpo-warren-1964.epub')
na, nb = za.namelist(), zb.namelist()
print('same entry list', na == nb)
ra = json.load(open(a_dir + '/conversion-report.json')); rb = json.load(open(b_dir + '/conversion-report.json'))
ra.pop('outputURL', None); rb.pop('outputURL', None)
print('reports equal', ra == rb)
ocr = {w['page'] for w in ra['warnings'] if w['code'] == 'ocrUsed'}
diff = []
for n in na:
    x, y = za.read(n), zb.read(n)
    if x != y:
        diff.append(n)
print('differing entries', diff)
for n in diff:
    if n.endswith('.xhtml'):
        pa = re.split(r'(?=<span epub:type="pagebreak")', za.read(n).decode())
        pb = re.split(r'(?=<span epub:type="pagebreak")', zb.read(n).decode())
        pages = [re.search(r'id="page-(\d+)"', s).group(1) for s, t in zip(pa, pb) if s != t and 'id="page-' in s]
        print(n, 'pages differing', pages, 'ocr pages', sorted(ocr))
    elif n.endswith('.opf') or n.endswith('nav.xhtml'):
        a, b = za.read(n).decode().splitlines(), zb.read(n).decode().splitlines()
        print(n, [(s, t) for s, t in zip(a, b) if s != t][:4])
