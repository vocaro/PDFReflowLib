#!/usr/bin/env python3
"""usage: fused.py <lines.tsv from survey-lines> <pdf> [pages-file]

Finds native line tokens (whitespace-separated) that pdftotext splits: the token does not occur
among the page's pdftotext tokens, but equals the concatenation of two or three tokens adjacent
on one `pdftotext -layout` line or adjacent in `pdftotext` (reading order) output of that page.
Prints TSV: page, line, token, pdftotext pieces, whether every split falls on a PDFKit
attributed-run boundary (font, size, traits or baseline change), and the marked native line.
class is `word` when a letter or digit is on both sides of every split, else `punct`.
With a pages-file (one page number per line) only those pages are reported.
"""
import re
import subprocess
import sys
from collections import defaultdict

PDFTOTEXT = "/opt/homebrew/bin/pdftotext"
MARK = "¦"


def pages_text(pdf, layout):
    args = [PDFTOTEXT] + (["-layout"] if layout else []) + ["-enc", "UTF-8", pdf, "-"]
    return subprocess.run(args, capture_output=True, check=True).stdout.decode("utf-8", "replace").split("\f")


def main():
    lines_path, pdf = sys.argv[1], sys.argv[2]
    only = None
    if len(sys.argv) > 3:
        only = {int(x) for x in open(sys.argv[3]).read().split()}
    layout, raw = pages_text(pdf, True), pages_text(pdf, False)
    native = defaultdict(list)
    for row in open(lines_path, encoding="utf-8"):
        parts = row.rstrip("\n").split("\t")
        if len(parts) < 4:
            continue
        native[int(parts[0])].append((int(parts[1]), parts[2].replace("\\t", " ").replace("\\n", " "),
                                      parts[3].replace("\\t", " ").replace("\\n", " ")))
    print("page\tline\ttoken\tpieces\tclass\tatRunBoundary\tmarked")
    for page in sorted(native):
        if only is not None and page not in only:
            continue
        if page - 1 >= len(layout):
            continue
        tokens, joins = set(), {}
        sequences = [l.split() for l in layout[page - 1].splitlines()] + [raw[page - 1].split()]
        for seq in sequences:
            tokens.update(seq)
            for i in range(len(seq)):
                for k in (2, 3):
                    if i + k <= len(seq):
                        joins.setdefault("".join(seq[i:i + k]), seq[i:i + k])
        for index, text, marked in native[page]:
            for token in text.split():
                if token in tokens or token not in joins:
                    continue
                pieces = joins[token]
                word = all(a[-1].isalnum() and b[0].isalnum() for a, b in zip(pieces, pieces[1:]))
                boundary = "?"
                if marked:
                    pattern = f"[{MARK}]?".join(re.escape(c) for c in token)
                    m = re.search(pattern, marked)
                    if m:
                        segment, offsets, count = m.group(0), set(), 0
                        for ch in segment:
                            if ch == MARK:
                                offsets.add(count)
                            else:
                                count += 1
                        splits, pos = [], 0
                        for piece in pieces[:-1]:
                            pos += len(piece)
                            splits.append(pos)
                        boundary = "yes" if all(s in offsets for s in splits) else "no"
                print(f"{page}\t{index}\t{token}\t{' + '.join(pieces)}\t{'word' if word else 'punct'}\t{boundary}\t{marked or text}")


if __name__ == "__main__":
    main()
