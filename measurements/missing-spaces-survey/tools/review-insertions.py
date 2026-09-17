#!/usr/bin/env python3
"""usage: review-insertions.py <diff.tsv from diff-lines.sh> <pdf>

Lists every space the candidate inserts (a changed line must equal the baseline line plus spaces).
For each insertion, the whitespace tokens on either side in the candidate line are checked against
the page's pdftotext output (-layout lines and reading order): `split` when the left and right
tokens are adjacent tokens there (pdftotext also separates them), `joined` when pdftotext has the
fused token, `other` otherwise. Prints TSV: page, line, left token, right token, verdict, after.
"""
import subprocess
import sys

PDFTOTEXT = "/opt/homebrew/bin/pdftotext"


def pages(pdf, layout):
    args = [PDFTOTEXT] + (["-layout"] if layout else []) + ["-enc", "UTF-8", pdf, "-"]
    return subprocess.run(args, capture_output=True, check=True).stdout.decode("utf-8", "replace").split("\f")


def main():
    diff, pdf = sys.argv[1], sys.argv[2]
    layout, raw = pages(pdf, True), pages(pdf, False)
    cache = {}
    print("page\tline\tleft\tright\tverdict\tafter")
    for row in open(diff, encoding="utf-8"):
        if row.startswith("#"):
            print(row.rstrip("\n"))
            continue
        page, index, before, after = row.rstrip("\n").split("\t")
        page = int(page)
        if page not in cache:
            sequences = [l.split() for l in layout[page - 1].splitlines()] + [raw[page - 1].split()]
            pairs, tokens = set(), set()
            for seq in sequences:
                tokens.update(seq)
                pairs.update(zip(seq, seq[1:]))
            cache[page] = (pairs, tokens)
        pairs, tokens = cache[page]
        # Recover insertion offsets: after minus spaces must equal before.
        i = j = 0
        inserted = []
        while j < len(after):
            if i < len(before) and before[i] == after[j]:
                i += 1; j += 1
            elif after[j] == " ":
                inserted.append(j); j += 1
            else:
                break
        if i != len(before) or j != len(after) or not inserted:
            print(f"{page}\t{index}\t-\t-\tnot-an-insertion\t{after}")
            continue
        for offset in inserted:
            left = after[:offset].split(" ")[-1]
            right = after[offset + 1:].split(" ")[0]
            if (left, right) in pairs:
                verdict = "split"
            elif left + right in tokens:
                verdict = "joined"
            else:
                verdict = "other"
            print(f"{page}\t{index}\t{left}\t{right}\t{verdict}\t{after}")


if __name__ == "__main__":
    main()
