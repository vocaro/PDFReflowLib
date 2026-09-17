import re, sys, zipfile
def nav(path):
    z = zipfile.ZipFile(path)
    n = z.read('EPUB/nav.xhtml').decode()
    toc = re.findall(r'<li><a href="[^"#]*#([^"]*)">(.*?)</a></li>', n.split('page-list')[0])
    pages = re.findall(r'#page-(\d+)"', n.split('page-list')[1])
    levels = []
    for name in z.namelist():
        if name.endswith('.xhtml') and 'chapter' in name:
            levels += re.findall(r'<h(\d) id="([^"]+)">', z.read(name).decode())
    return [t for _, t in toc], pages, sorted((i, l) for l, i in levels)
a, b = nav(sys.argv[1]), nav(sys.argv[2])
print('toc', len(a[0]), len(b[0]))
print(' removed', [x for x in a[0] if x not in b[0]])
print(' added', [x for x in b[0] if x not in a[0]])
print('pages equal', a[1] == b[1], len(a[1]), len(b[1]))
la = dict(a[2]); lb = dict(b[2])
print('level changes', [(i, la[i], lb[i]) for i in la if i in lb and la[i] != lb[i]])
