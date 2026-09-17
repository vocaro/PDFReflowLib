import sys, re, glob, html
root = sys.argv[1]
files = sorted(glob.glob(root + '/EPUB/chapter-*.xhtml'), key=lambda p: int(re.search(r'chapter-(\d+)', p).group(1)))
src = '\n'.join(re.search(r'<body[^>]*>(.*)</body>', open(f, encoding='utf-8').read(), re.S).group(1) for f in files)
for key in sys.argv[2:]:
    c, n = map(int, key.split('-'))
    a = src.find('id="noteref-c%d-%d"' % (c, n - 1))
    b = src.find('id="noteref-c%d-%d"' % (c, n + 1))
    seg = src[a:b]
    pages = re.findall(r'id="page-(\d+)"', src[:a])[-1:] + re.findall(r'id="page-(\d+)"', seg)
    t = re.sub(r'<span epub:type="pagebreak"[^>]*id="page-(\d+)"[^>]*/>', r'[[p\1]]', seg)
    t = re.sub(r'<sup><a [^>]*>(\d+)</a></sup>', r'^\1', t)
    t = html.unescape(re.sub(r'<[^>]+>', ' ', t))
    t = re.sub(r'\s+', ' ', t)
    print('== c%d-%d pages %s chars %d' % (c, n, pages, len(t)))
    hits = [m.start() for m in re.finditer(r'(?<![0-9])%d(?![0-9])' % n, t)]
    print('   digit hits:', [t[max(0, h - 50):h + 30] for h in hits][:6])
    if len(t) < 1500:
        print('   ', t)
