#!/usr/bin/env python3
"""usage: glyphs.py <fused.tsv> <pdf> [class]

For each candidate of the class (default `word`, or `all`), locates its native line (spaces removed)
as a unique substring of one visual line of the page's `mutool trace` glyphs (grouped into visual lines by baseline with superscript tolerance, sorted by
x, space glyphs dropped) and reports for every split: the fonts on each side, whether they differ,
the size of each side, the horizontal gap from the left glyph's advance end to the right glyph's
origin in em of the left glyph's size, the vertical offset of the right glyph, and whether a space
glyph (U+0020) is drawn between them. found=no when the native line is not a unique substring. Output TSV: page, native line index, token, pieces, split, left font, right font,
fontChange, gapEm, dy, spaceGlyph, found, native line.
"""
import csv
import re
import subprocess
import sys
from collections import defaultdict

MUTOOL = "/opt/homebrew/bin/mutool"
MARK = "\u00a6"
SPAN = re.compile(r'<span font="([^"]*)"[^>]*trm="([-\d.e]+) ([-\d.e]+) ([-\d.e]+) ([-\d.e]+)"')
GLYPH = re.compile(r'<g unicode="([^"]*)" glyph="[^"]*" x="([-\d.e]+)" y="([-\d.e]+)" adv="([-\d.e]+)"')


def unescape(value):
    return (value.replace("&quot;", '"').replace("&lt;", "<").replace("&gt;", ">")
            .replace("&apos;", "'").replace("&amp;", "&"))


def page_glyphs(pdf, page):
    trace = subprocess.run([MUTOOL, "trace", pdf, str(page)], capture_output=True).stdout.decode("utf-8", "replace")
    glyphs, font, size = [], "?", 0.0
    for line in trace.splitlines():
        m = SPAN.search(line)
        if m:
            font = m.group(1)
            a, b, c, d = (float(m.group(i)) for i in range(2, 6))
            size = abs(d) if abs(d) > 0 else (a * a + b * b) ** 0.5
            continue
        m = GLYPH.search(line)
        if m:
            text = unescape(m.group(1))
            x, y, adv = float(m.group(2)), float(m.group(3)), float(m.group(4))
            glyphs.append(dict(u=text, x=x, y=y, end=x + adv * size, font=font, size=size))
    return glyphs


def visual_lines(glyphs):
    lines = []
    for g in sorted(glyphs, key=lambda g: -g["y"]):
        for line in lines:
            if abs(line["y"] - g["y"]) <= 0.5 * max(line["size"], g["size"]):
                line["glyphs"].append(g)
                break
        else:
            lines.append(dict(y=g["y"], size=g["size"], glyphs=[g]))
    for line in lines:
        line["glyphs"].sort(key=lambda g: g["x"])
    return lines


def main():
    fused, pdf = sys.argv[1], sys.argv[2]
    wanted = sys.argv[3] if len(sys.argv) > 3 else "word"
    by_page = defaultdict(list)
    for row in csv.DictReader(open(fused, encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE):
        if wanted == "all" or row["class"] == wanted:
            by_page[int(row["page"])].append(row)
    print("page\tline\ttoken\tpieces\tsplit\tleftFont\trightFont\tfontChange\tgapEm\tdy\tspaceGlyph\tfound\tnative")
    for page in sorted(by_page):
        lines = visual_lines(page_glyphs(pdf, page))
        prepared = []
        for line in lines:
            all_glyphs = line["glyphs"]
            kept = [i for i, g in enumerate(all_glyphs) if g["u"].strip()]
            owner = []
            for i in kept:
                owner.extend([i] * len(all_glyphs[i]["u"]))
            prepared.append((all_glyphs, "".join(all_glyphs[i]["u"] for i in kept), owner))
        done = set()
        for row in by_page[page]:
            native = row["marked"].replace(MARK, "")
            words = native.split()
            if (row["line"], row["token"]) in done:
                continue
            done.add((row["line"], row["token"]))
            pieces = row["pieces"].split(" + ")
            compact = "".join(words)
            reported = False
            for w, word in enumerate(words):
                if word != row["token"]:
                    continue
                offset = sum(len(x) for x in words[:w])
                for all_glyphs, text, owner in prepared:
                    at = text.find(compact)
                    if at < 0 or text.find(compact, at + 1) >= 0:
                        continue
                    pos = at + offset
                    for piece in pieces[:-1]:
                        pos += len(piece)
                        li, ri = owner[pos - 1], owner[pos]
                        left, right = all_glyphs[li], all_glyphs[ri]
                        space = any(g["u"] == " " for g in all_glyphs[li + 1:ri])
                        gap = (right["x"] - left["end"]) / left["size"] if left["size"] else 0
                        change = left["font"] != right["font"] or abs(left["size"] - right["size"]) > 0.01
                        print(f"{page}\t{row['line']}\t{row['token']}\t{row['pieces']}\t{pos}\t{left['font']}\t{right['font']}\t"
                              f"{'yes' if change else 'no'}\t{gap:.3f}\t{right['y'] - left['y']:.2f}\t{'yes' if space else 'no'}\tyes\t{native}")
                        reported = True
                    break
            if not reported:
                print(f"{page}\t{row['line']}\t{row['token']}\t{row['pieces']}\t-\t-\t-\t-\t-\t-\t-\tno\t{native}")


if __name__ == "__main__":
    main()
