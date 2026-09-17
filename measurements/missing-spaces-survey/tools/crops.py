#!/usr/bin/env python3
"""usage: crops.py <insertions.tsv> <pdf> <out.png> [verdict|all] [limit]

Renders, for each reviewed insertion, a strip of its source line at 144 dpi and stacks the strips
into one image, each labelled with page and the candidate text, for visual confirmation. A line
is located as the first `mutool trace` visual line (glyphs.py) whose glyphs, spaces removed,
contain the candidate line; the strip spans that line's glyphs (at most 520 pt). Strips are stacked with Pillow.
"""
import re
import subprocess
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glyphs  # noqa: E402

PDFTOPPM = "/opt/homebrew/bin/pdftoppm"


def page_height(pdf, page):
    out = subprocess.run(["/opt/homebrew/bin/pdfinfo", "-f", str(page), "-l", str(page), pdf], capture_output=True).stdout.decode()
    m = re.search(r"Page\s+%d size:\s+([\d.]+) x ([\d.]+)" % page, out)
    return float(m.group(2))


def locate(pdf, page, after, cache={}):
    """The x range and baseline of the visual line that contains the candidate line's glyphs."""
    if page not in cache:
        cache[page] = [(line, "".join(g["u"] for g in line["glyphs"] if g["u"].strip()))
                       for line in glyphs.visual_lines(glyphs.page_glyphs(pdf, page))]
    compact = "".join(after.split())
    for line, text in cache[page]:
        at = text.find(compact)
        if at >= 0:
            kept = [g for g in line["glyphs"] if g["u"].strip()]
            owner = []
            for g in kept:
                owner.extend([g] * len(g["u"]))
            first, last = owner[at], owner[at + len(compact) - 1]
            return first["x"], last["end"], line["y"], line["size"]
    return None


def main():
    rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1], encoding="utf-8")][1:]
    pdf, out = sys.argv[2], sys.argv[3]
    verdict = sys.argv[4] if len(sys.argv) > 4 else "all"
    limit = int(sys.argv[5]) if len(sys.argv) > 5 else 1000
    rows = [r for r in rows if len(r) >= 6 and (verdict == "all" or r[4] == verdict)][:limit]
    base = os.path.splitext(out)[0]
    files = []
    for n, (page, _, left, right, _, after) in enumerate(rows):
        page = int(page)
        where = locate(pdf, page, after)
        if not where:
            print("unlocated", page, after)
            continue
        x0, x1, baseline, size = where
        top = page_height(pdf, page) - baseline - size * 1.2
        scale = 2
        x = max(0, int((x0 - 4) * scale)); y = max(0, int(top * scale))
        name = f"{base}-{n:03d}"
        subprocess.run([PDFTOPPM, "-f", str(page), "-l", str(page), "-r", "144", "-x", str(x), "-y", str(y),
                        "-W", str(int(min(x1 - x0 + 8, 520) * scale)), "-H", str(int(size * 1.8 * scale)), "-png", "-singlefile", pdf, name])
        files.append((name + ".png", f"p{page}: {after[:90]}"))
    with open(base + "-index.txt", "w") as index:
        for name, label in files:
            index.write(f"{name}\t{label}\n")
    from PIL import Image, ImageDraw
    strips = []
    for name, label in files:
        image = Image.open(name).convert("RGB")
        canvas = Image.new("RGB", (image.width, image.height + 16), "white")
        canvas.paste(image, (0, 16))
        ImageDraw.Draw(canvas).text((2, 2), label, fill="red")
        strips.append(canvas)
        os.remove(name)
    if strips:
        sheet = Image.new("RGB", (max(i.width for i in strips), sum(i.height for i in strips)), "white")
        top = 0
        for strip in strips:
            sheet.paste(strip, (0, top)); top += strip.height
        sheet.save(out)
    print(len(files), "strips")


if __name__ == "__main__":
    main()
