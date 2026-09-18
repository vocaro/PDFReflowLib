#!/usr/bin/env python3
"""usage: page-images.py <epub> <page> <out-prefix>

Writes every image a source page's blocks reference (in order) as <out-prefix>-NN.png, so a changed
preserved region can be read beside the page render."""
import re
import sys
import zipfile

archive = zipfile.ZipFile(sys.argv[1])
page, prefix = int(sys.argv[2]), sys.argv[3]
names = sorted((n for n in archive.namelist() if re.search(r"chapter-\d+\.xhtml$", n)),
               key=lambda n: int(re.search(r"(\d+)\.xhtml$", n).group(1)))
current, count = None, 0
token = re.compile(r'<span[^>]*id="page-(\d+)"[^>]*/>|<img[^>]*src="([^"]+)"')
for name in names:
    for m in token.finditer(archive.read(name).decode("utf-8")):
        if m.group(1):
            current = int(m.group(1))
        elif current == page:
            count += 1
            with open(f"{prefix}-{count:02d}.png", "wb") as out:
                out.write(archive.read("EPUB/" + m.group(2)))
print(count, "images")
