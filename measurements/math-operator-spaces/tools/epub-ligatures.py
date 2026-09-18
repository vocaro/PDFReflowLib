#!/usr/bin/env python3
"""usage: epub-ligatures.py <epub>...

For each EPUB, counts U+FB00–U+FB06 in the spine text and every ligature followed by whitespace and a
lowercase letter, with whether the two pieces spell a dictionary word together but the first does
not alone (`/usr/share/dict/words`, ligatures spelled out): a split word (#189)."""
import html
import re
import sys
import zipfile

LIGATURES = {"ﬀ": "ff", "ﬁ": "fi", "ﬂ": "fl", "ﬃ": "ffi", "ﬄ": "ffl", "ﬅ": "st", "ﬆ": "st"}
WORDS = {w.strip().lower() for w in open("/usr/share/dict/words")}


def spelled(text):
    return "".join(LIGATURES.get(c, c) for c in text)


def known(word):
    w = word.lower()
    return w in WORDS or (w.endswith("s") and w[:-1] in WORDS) or (w.endswith("ed") and w[:-2] in WORDS) \
        or (w.endswith("ly") and w[:-2] in WORDS)


for path in sys.argv[1:]:
    archive = zipfile.ZipFile(path)
    text = ""
    for name in sorted(n for n in archive.namelist() if n.endswith(".xhtml")):
        body = archive.read(name).decode("utf-8")
        text += html.unescape(re.sub(r"<[^>]+>", " ", body)) + "\n"
    count = sum(text.count(c) for c in LIGATURES)
    spaced, split = [], []
    for m in re.finditer(r"(\w*[ﬀ-ﬆ])(\s+)([a-z]\w*)", text):
        spaced.append(m.group(0))
        left, right = m.group(1), m.group(3)
        if known(spelled(left + right)) and not known(spelled(left)):
            split.append(m.group(0))
    print(f"{path}\tligatures={count}\tfollowedBySpace={len(spaced)}\tsplitWords={len(split)}\t"
          f"spaced={spaced[:6]}\tsplit={split[:6]}")
