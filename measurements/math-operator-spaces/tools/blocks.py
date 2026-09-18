#!/usr/bin/env python3
"""usage: blocks.py <base.epub> <cand.epub> <page>[,<page>...]

Prints, for each source page, the base and candidate block sequences as a unified diff: one line per
block element (`p`, `pre`, `h1`–`h6`, `li`, `figure`), its tag and text with whitespace squeezed; a
figure prints its image's pixel size. Blocks are cut at the page's pagebreak markers.
"""
import difflib
import html
import re
import struct
import sys
import zipfile


def image_size(data):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    return (0, 0)


def page_blocks(path):
    archive = zipfile.ZipFile(path)
    names = sorted((n for n in archive.namelist() if re.search(r"chapter-\d+\.xhtml$", n)),
                   key=lambda n: int(re.search(r"(\d+)\.xhtml$", n).group(1)))
    pages, current = {}, None
    token = re.compile(r'<span[^>]*id="page-(\d+)"[^>]*/>|<(p|pre|h[1-6]|li|figure)\b[^>]*>(.*?)</\2>', re.S)
    for name in names:
        body = archive.read(name).decode("utf-8")
        for m in token.finditer(body):
            if m.group(1):
                current = int(m.group(1)); pages.setdefault(current, []); continue
            if current is None:
                continue
            tag, inner = m.group(2), m.group(3)
            if tag == "figure":
                src = re.search(r'src="([^"]+)"', inner)
                size = image_size(archive.read("EPUB/" + src.group(1))) if src else (0, 0)
                pages[current].append(f"[figure {size[0]}x{size[1]}]")
            else:
                text = " ".join(html.unescape(re.sub(r"<[^>]+>", "", inner)).split())
                pages[current].append(f"<{tag}> {text[:150]}")
    return pages


base, cand = page_blocks(sys.argv[1]), page_blocks(sys.argv[2])
for number in (int(n) for n in sys.argv[3].split(",")):
    print(f"==== page {number}")
    for line in difflib.unified_diff(base.get(number, []), cand.get(number, []), "base", "cand", lineterm="", n=1):
        if not line.startswith(("---", "+++")):
            print(line)
