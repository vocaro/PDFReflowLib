#!/usr/bin/env python3
"""usage: review.py <insertions.tsv> <pdf> <out-prefix> <sample|all|regex> [count] [seed]

Renders, for inserted spaces from insertions.py, a 200-dpi strip around the two words beside each
space and stacks them into sheets of 25 (<out-prefix>-NN.png), labelled with a row number, the page and
the candidate pair. `sample` draws `count` rows at random with `seed`; `all` takes every row; any other
value is a regular expression matched against the pair column. The pair is located in the page's
`mutool trace` glyphs (visual lines, spaces removed); a row whose pair occurs other than once on the
page is labelled `ambiguous` and rendered at its first occurrence. Writes <out-prefix>-rows.tsv, the
reviewed rows with their numbers."""
import os
import random
import re
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../missing-spaces-survey/tools"))
import glyphs  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8")]
rows = [r for r in rows if len(r) >= 8 and r[3] != "other"]
pdf, prefix, mode = sys.argv[2], sys.argv[3], sys.argv[4]
count = int(sys.argv[5]) if len(sys.argv) > 5 else 100
seed = int(sys.argv[6]) if len(sys.argv) > 6 else 119
if mode == "sample":
    rows = random.Random(seed).sample(rows, min(count, len(rows)))
elif mode != "all":
    rows = [r for r in rows if re.search(mode, r[6])]
rows.sort(key=lambda r: (int(r[1]), int(r[2])))
cache, heights, strips = {}, {}, []
listing = open(prefix + "-rows.tsv", "w", encoding="utf-8")
for n, r in enumerate(rows):
    page = int(r[1])
    listing.write(f"{n}\t" + "\t".join(r) + "\n")
    if page not in cache:
        lines = glyphs.visual_lines(glyphs.page_glyphs(pdf, page))
        cache[page] = [([g for g in line["glyphs"] if g["u"].strip()], line) for line in lines]
        info = subprocess.run(["/opt/homebrew/bin/pdfinfo", "-f", str(page), "-l", str(page), pdf], capture_output=True).stdout.decode()
        heights[page] = float(re.search(r"Page\s+%d size:\s+[\d.]+ x ([\d.]+)" % page, info).group(1))
    pair = r[6]
    left_word, _, right_word = pair.partition(" ")
    compact = left_word + right_word
    hits = []
    for kept, line in cache[page]:
        owner = []
        for g in kept:
            owner.extend([g] * len(g["u"]))
        text = "".join(g["u"] for g in kept)
        at = text.find(compact)
        while at >= 0:
            hits.append((owner, at, line))
            at = text.find(compact, at + 1)
    label = f"#{n} p{page} {r[3]}: {pair}"
    if not hits:
        strips.append((None, label + "  UNLOCATED"))
        continue
    if len(hits) > 1:
        label += "  ambiguous"
    owner, at, line = hits[0]
    first, last = owner[at], owner[at + len(compact) - 1]
    x0, x1 = first["x"] - 6, last["end"] + 6
    top = heights[page] - line["y"] - line["size"] * 1.1
    dpi = int(os.environ.get("REVIEW_DPI", "200"))
    scale = dpi / 72
    name = f"{prefix}-strip-{n:03d}"
    subprocess.run(["/opt/homebrew/bin/pdftoppm", "-f", str(page), "-l", str(page), "-r", str(dpi),
                    "-x", str(max(0, int(x0 * scale))), "-y", str(max(0, int(top * scale))),
                    "-W", str(int(min(x1 - x0, 300 * 200 / dpi) * scale)), "-H", str(int(line["size"] * 1.6 * scale)),
                    "-png", "-singlefile", pdf, name])
    image = Image.open(name + ".png").convert("RGB")
    os.remove(name + ".png")
    strips.append((image, label))
listing.close()
for sheet_index in range(0, len(strips), 25):
    group = strips[sheet_index:sheet_index + 25]
    width = max([760] + [i.width + 330 for i, _ in group if i])
    height = sum((i.height if i else 20) + 6 for i, _ in group)
    sheet = Image.new("RGB", (width, height), "white")
    draw, y = ImageDraw.Draw(sheet), 0
    for image, label in group:
        draw.text((4, y + 4), label[:60], fill="red")
        if image:
            sheet.paste(image, (320, y))
            y += image.height + 6
        else:
            y += 26
    sheet.save(f"{prefix}-{sheet_index // 25:02d}.png")
print(len(strips), "strips", sum(1 for i, _ in strips if i is None), "unlocated")
