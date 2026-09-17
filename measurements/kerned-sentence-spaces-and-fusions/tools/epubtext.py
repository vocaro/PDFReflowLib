#!/usr/bin/env python3
"""usage: epubtext.py <epub> <out.tsv>  one row per text block: xhtml file name, block text (tags removed, entities decoded)."""
import html, re, sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
with open(sys.argv[2], 'w', encoding='utf-8') as out:
    for name in sorted(n for n in z.namelist() if n.endswith('.xhtml')):
        data = z.read(name).decode('utf-8')
        body = data.split('<body', 1)[-1]
        for block in re.findall(r'<(?:p|h[1-6]|li|td|th|figcaption|dt|dd)\b[^>]*>(.*?)</(?:p|h[1-6]|li|td|th|figcaption|dt|dd)>', body, re.S):
            text = html.unescape(re.sub(r'<[^>]+>', '', block))
            text = re.sub(r'\s+', ' ', text).strip()
            if text:
                out.write(f"{name.rsplit('/', 1)[-1]}\t{text}\n")
