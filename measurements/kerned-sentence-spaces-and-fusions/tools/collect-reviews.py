#!/usr/bin/env python3
"""usage: collect-reviews.py <scratch> <out.tsv>

Merges the review.py row listings (<scratch>/review/<set>-rows.tsv) into one TSV with the set, the verdict read on
the rendered strips, and whether the insertion is still in the final survey (<scratch>/<book>-insertions.tsv)."""
import sys

scratch, out = sys.argv[1], sys.argv[2]
SETS = [  # set name, rows file, book survey, verdict
    ("911-random-period-sample-125-seed-128", "period", "911", "space"),
    ("911-every-non-period-insertion", "nonperiod", "911", "space"),
    ("911-every-show-edge-insertion", "edge", "911", "space"),
    ("911-every-new-insertion-on-fixture-pages", "fixture", "911", "space"),
    ("faa-every-insertion", "faa", "faa", "space"),
    ("replay-every-font-change-insertion", "replay", "replay", "space"),
    ("replay-every-math-punctuation-insertion", "replay-punct", "replay", "space"),
    ("wallace-math-punctuation-sample-50-seed-120", "wallace-punct", "wallace", "space"),
    ("ourflag-first-candidate", "ourflag", "ourflag", "closed in source (H.Doc.): spurious, removed by the abbreviation exclusion"),
]
final = {}
for book in {s[2] for s in SETS}:
    try:
        final[book] = {tuple(l.rstrip("\n").split("\t")[1:3] + [l.split("\t")[6]]) for l in open(f"{scratch}/{book}-insertions.tsv", encoding="utf-8")}
    except FileNotFoundError:
        final[book] = set()
with open(out, "w", encoding="utf-8") as o:
    o.write("set\tsheetRow\tbook\tpage\tline\tclass\tleft\tright\tpair\tverdict\tinFinal\n")
    for name, rows, book, verdict in SETS:
        for line in open(f"{scratch}/review/{rows}-rows.tsv", encoding="utf-8"):
            f = line.rstrip("\n").split("\t")
            key = (f[2], f[3], f[7])
            note = verdict
            if book == "911" and f[7] == "U.S. VISIT":
                note = "space (source closed; the book writes US VISIT elsewhere)"
            o.write("\t".join([name, f[0], book, f[2], f[3], f[4], f[5], f[6], f[7], note, "yes" if key in final[book] else "no"]) + "\n")
