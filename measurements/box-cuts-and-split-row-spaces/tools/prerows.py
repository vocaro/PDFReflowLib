#!/usr/bin/env python3
# usage: prerows.py <epub> : <pre> blocks opening with a minus sign directly after a paragraph, by page
import sys, zipfile, re
z = zipfile.ZipFile(sys.argv[1])
count = 0
for name in sorted(n for n in z.namelist() if n.endswith('.xhtml')):
    text = z.read(name).decode('utf-8')
    for m in re.finditer(r'<p>((?:(?!</p>).)*)</p>\s*<pre>(−[^<]*)</pre>', text, re.S):
        para = re.sub(r'<[^>]+>', '', m.group(1))
        if len(para) < 30:
            pages = re.findall(r'aria-label="(\d+)"', text[:m.start()])
            count += 1
            print(pages[-1] if pages else '?', repr(para), repr(m.group(2)))
print('total', count)
