#!/usr/bin/env python3
"""usage: shows.py <pdf> <first> <last>  (1-based pages)

Simulates each page's text operators (no XObject forms) with `mutool show` and writes one TSV row per
glyph boundary inside or between text shows on the page:

page, showIndex, kind, left, right, font, size, tcEm, twEm, adjEm, gapEm, spaceGlyphEm, context

kind: `adj` a boundary inside one TJ array between two non-space glyphs that carries a number;
`kern0` the same with no number; `space` an explicit U+0020 glyph (gapEm is its effective advance
plus the gaps around it); `show` the gap between a show's advance end and the next show on the same
baseline (within 0.5 em). Em is the left glyph's size. adjEm = -number/1000; tcEm and twEm are the
state's Tc and Tw in em of the font size (Tw only counts on code 32).
"""
import re
import subprocess
import sys
from functools import lru_cache

MUTOOL = "/opt/homebrew/bin/mutool"
TOKEN = re.compile(rb"\s*(?:(%[^\r\n]*)|(\()|(<<|>>)|(<[0-9A-Fa-f\s]*>)|(\[)|(\])|(/[^\s/\[\]()<>{}%]*)|([-+]?(?:\d+\.?\d*|\.\d+))|([^\s/\[\]()<>{}%]+))")


def mutool(*args):
    return subprocess.run([MUTOOL, *args], capture_output=True).stdout


def read_string(data, i):
    depth, out = 1, bytearray()
    while i < len(data):
        c = data[i]
        if c == 0x5C:
            i += 1
            n = data[i]
            if n in b"01234567":
                j = i
                while j < len(data) and j < i + 3 and data[j] in b"01234567":
                    j += 1
                out.append(int(data[i:j], 8) & 255); i = j; continue
            out += {ord("n"): b"\n", ord("r"): b"\r", ord("t"): b"\t", ord("b"): b"\b", ord("f"): b"\f"}.get(n, bytes([n])) if n not in (10, 13) else b""
            i += 1; continue
        if c == 0x28:
            depth += 1
        elif c == 0x29:
            depth -= 1
            if depth == 0:
                return bytes(out), i + 1
        out.append(c); i += 1
    return bytes(out), i


def tokens(data):
    i, stack = 0, []
    while i < len(data):
        m = TOKEN.match(data, i)
        if not m or m.end() == i:
            i += 1; continue
        i = m.end()
        if m.group(1):
            continue
        if m.group(2):
            s, i = read_string(data, i); yield ("str", s); continue
        if m.group(3):
            yield ("dict", m.group(3)); continue
        if m.group(4):
            h = re.sub(rb"\s", b"", m.group(4)[1:-1])
            if len(h) % 2: h += b"0"
            yield ("str", bytes.fromhex(h.decode())); continue
        if m.group(5):
            yield ("[", None); continue
        if m.group(6):
            yield ("]", None); continue
        if m.group(7):
            yield ("name", m.group(7)[1:].decode("latin1")); continue
        if m.group(8):
            yield ("num", float(m.group(8))); continue
        op = m.group(9)
        if op == b"ID":
            j = data.find(b"EI", i)
            i = j + 2 if j >= 0 else len(data)
        yield ("op", op.decode("latin1"))


def parse_obj_text(text):
    return text.decode("latin1")


@lru_cache(None)
def font_info(pdf, ref):
    text = mutool("show", pdf, ref).decode("latin1")
    first = re.search(r"/FirstChar (\d+)", text)
    widths_m = re.search(r"/Widths\s*(\[[^\]]*\]|\d+ 0 R)", text)
    widths = {}
    if first and widths_m:
        w = widths_m.group(1)
        if w.endswith("R"):
            w = mutool("show", pdf, w.split()[0]).decode("latin1")
        nums = [float(x) for x in re.findall(r"[-\d.]+", w.strip().strip("[]"))]
        for k, v in enumerate(nums):
            widths[int(first.group(1)) + k] = v / 1000
    uni = {}
    tu = re.search(r"/ToUnicode (\d+) 0 R", text)
    if tu:
        cmap = mutool("show", "-b", pdf, tu.group(1)).decode("latin1")
        for block in re.findall(r"beginbfchar(.*?)endbfchar", cmap, re.S):
            for a, b in re.findall(r"<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>", block):
                uni[int(a, 16)] = bytes.fromhex(b).decode("utf-16-be", "replace")
        for block in re.findall(r"beginbfrange(.*?)endbfrange", cmap, re.S):
            for a, b, c in re.findall(r"<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>", block):
                base = bytes.fromhex(c).decode("utf-16-be", "replace")
                for k in range(int(a, 16), int(b, 16) + 1):
                    uni[k] = base[:-1] + chr(ord(base[-1]) + k - int(a, 16))
    name = re.search(r"/BaseFont /(\S+)", text)
    return (name.group(1) if name else ref, widths, uni)


def page_fonts(pdf, page):
    text = mutool("show", pdf, f"pages/{page}/Resources/Font").decode("latin1")
    return {n: r for n, r in re.findall(r"/(\S+) (\d+) 0 R", text)}


def mat(a, b):  # a then b, 6-tuples
    return (a[0]*b[0]+a[1]*b[2], a[0]*b[1]+a[1]*b[3], a[2]*b[0]+a[3]*b[2], a[2]*b[1]+a[3]*b[3],
            a[4]*b[0]+a[5]*b[2]+b[4], a[4]*b[1]+a[5]*b[3]+b[5])


def run(pdf, page, out):
    fonts = page_fonts(pdf, page)
    data = mutool("show", "-b", pdf, f"pages/{page}/Contents")
    ctm, gstack = (1, 0, 0, 1, 0, 0), []
    tm = tlm = (1, 0, 0, 1, 0, 0)
    tc = tw = 0.0; tl = 0.0; tz = 1.0; fontname = None; fsize = 0.0
    operands, arr = [], None
    shows = []  # each: dict(font, size, glyphs=[(u, x0, x1, y)], bounds=[(kind, tc, tw, adj)])
    for kind, value in tokens(data):
        if kind == "[":
            arr = []; continue
        if kind == "]":
            operands.append(("arr", arr)); arr = None; continue
        if kind != "op":
            (arr if arr is not None else operands).append((kind, value)); continue
        op = value
        nums = [v for k, v in operands if k == "num"]
        if op == "q": gstack.append(ctm)
        elif op == "Q" and gstack: ctm = gstack.pop()
        elif op == "cm" and len(nums) == 6: ctm = mat(tuple(nums), ctm)
        elif op == "BT": tm = tlm = (1, 0, 0, 1, 0, 0)
        elif op == "Tm" and len(nums) == 6: tm = tlm = tuple(nums)
        elif op in ("Td", "TD") and len(nums) == 2:
            if op == "TD": tl = -nums[1]
            tm = tlm = mat((1, 0, 0, 1, nums[0], nums[1]), tlm)
        elif op == "T*": tm = tlm = mat((1, 0, 0, 1, 0, -tl), tlm)
        elif op == "TL" and nums: tl = nums[0]
        elif op == "Tc" and nums: tc = nums[0]
        elif op == "Tw" and nums: tw = nums[0]
        elif op == "Tz" and nums: tz = nums[0] / 100
        elif op == "Tf" and nums:
            names = [v for k, v in operands if k == "name"]
            fontname = names[0] if names else None; fsize = nums[0]
        elif op in ("Tj", "TJ", "'", '"'):
            if op in ("'", '"'):
                if op == '"' and len(nums) == 2: tw, tc = nums
                tm = tlm = mat((1, 0, 0, 1, 0, -tl), tlm)
            items = operands[-1][1] if op == "TJ" and operands and operands[-1][0] == "arr" else [o for o in operands if o[0] == "str"][-1:]
            base, widths, uni = font_info(pdf, fonts.get(fontname, "0")) if fontname in fonts else ("?", {}, {})
            trm = mat(tm, ctm)
            scale = trm[0]  # upright only
            upright = abs(trm[1]) < 1e-6 and abs(trm[2]) < 1e-6 and trm[0] > 0
            show = dict(font=base, size=fsize * trm[3] if upright else 0, glyphs=[], bounds=[], tc=tc, tw=tw)
            pending = 0.0
            for k, v in items:
                if k == "num":
                    pending += v; continue
                if k != "str": continue
                for code in v:
                    if show["glyphs"]:
                        show["bounds"].append((pending,))
                    tm = mat((1, 0, 0, 1, -pending / 1000 * fsize * tz, 0), tm); pending = 0.0
                    trm = mat(tm, ctm)
                    w = widths.get(code, 0.0)
                    adv = (w * fsize + tc + (tw if code == 32 else 0)) * tz
                    show["glyphs"].append((uni.get(code, "�"), trm[4], trm[4] + w * fsize * trm[0] / (1 if not upright else 1), trm[5], code))
                    tm = mat((1, 0, 0, 1, adv, 0), tm)
            if upright and show["glyphs"]:
                show["unit"] = mat((1, 0, 0, 1, 0, 0), mat(tm, ctm))[0] / 1 if False else None
                show["em"] = fsize * trm[0]  # page-space em
                show["tcEm"] = tc / fsize if fsize else 0
                show["twEm"] = tw / fsize if fsize else 0
                shows.append(show)
        operands = []
    for si, show in enumerate(shows):
        g = show["glyphs"]; em = show["em"]
        ctx = "".join(x[0] for x in g)
        for i in range(len(g) - 1):
            a, b = g[i], g[i + 1]
            adj = -show["bounds"][i][0] / 1000
            if a[4] == 32 or b[4] == 32:
                continue
            kind = "adj" if show["bounds"][i][0] != 0 else "kern0"
            out.write(f"{page}\t{si}\t{kind}\t{a[0]}\t{b[0]}\t{show['font']}\t{em:.3f}\t{show['tcEm']:.4f}\t{show['twEm']:.4f}\t{adj:.4f}\t{(b[1]-a[2])/em:.4f}\t\t{ctx[max(0,i-20):i+1]}|{ctx[i+1:i+21]}\n")
        # explicit space glyphs: effective gap from the left glyph end to the right glyph start
        for i in range(1, len(g) - 1):
            if g[i][4] == 32 and g[i - 1][4] != 32 and g[i + 1][4] != 32:
                out.write(f"{page}\t{si}\tspace\t{g[i-1][0]}\t{g[i+1][0]}\t{show['font']}\t{em:.3f}\t{show['tcEm']:.4f}\t{show['twEm']:.4f}\t\t{(g[i+1][1]-g[i-1][2])/em:.4f}\t{(g[i][2]-g[i][1])/em:.4f}\t{ctx[max(0,i-20):i]}|{ctx[i+1:i+21]}\n")
        if si + 1 < len(shows):
            nxt = shows[si + 1]; last = g[-1]; first = nxt["glyphs"][0]
            if nxt["em"] and abs(first[3] - last[3]) <= 0.5 * max(em, nxt["em"]) and first[1] > last[1]:
                out.write(f"{page}\t{si}\tshow\t{last[0]}\t{first[0]}\t{show['font']}>{nxt['font']}\t{em:.3f}>{nxt['em']:.3f}\t{show['tcEm']:.4f}\t\t\t{(first[1]-last[2])/em:.4f}\t\t{ctx[-20:]}|{"".join(x[0] for x in nxt["glyphs"])[:20]}\n")


if __name__ == "__main__":
    pdf, first, last = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    for p in range(first, last + 1):
        run(pdf, p, sys.stdout)
