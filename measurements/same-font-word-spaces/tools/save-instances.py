#!/usr/bin/env python3
"""usage: save-instances.py <scratch-dir>  writes instances/911-insertions.tsv.gz (every inserted space,
insertions.py) and instances/911-reviewed-insertions.tsv (every row rendered by review.py, by review set,
with its verdict) from the scratch directory's final outputs."""
import gzip
import os
import shutil
import sys

scratch = sys.argv[1]
instances = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "instances")
os.makedirs(instances, exist_ok=True)
with open(os.path.join(scratch, "911-insertions.tsv"), "rb") as source, \
        gzip.GzipFile(os.path.join(instances, "911-insertions.tsv.gz"), "wb", mtime=0) as target:
    shutil.copyfileobj(source, target)
sets = [
    ("random-sample-125-seed-119", "sample"), ("initials-and-abbreviations-all", "initial"), ("ellipsis-all", "ellipsis"),
    ("digit-comma-digit-sample-50", "digits"), ("opening-quote-sample-50", "quote"), ("lowercase-capital-sample-50", "lowercase"),
    ("fixture-pages-all", "fixture"), ("before-parenthesis-all", "paren"), ("contract-rewrites", "contract"),
    ("contract-rewrites-9803329", "contract-new"), ("contract-rewrites-9803329", "povinelli"), ("zoom-500dpi", "zoom"),
    ("zoom-600dpi-initials", "hw"),
]
count = 0
with open(os.path.join(instances, "911-reviewed-insertions.tsv"), "w", encoding="utf-8") as out:
    out.write("set\tsheetRow\tbook\tpage\tline\tclass\tleft\tright\tpair\tverdict\n")
    for name, prefix in sets:
        for line in open(os.path.join(scratch, "review", prefix + "-rows.tsv"), encoding="utf-8"):
            fields = line.rstrip("\n").split("\t")
            out.write("\t".join([name, fields[0]] + fields[1:8] + ["space"]) + "\n")
            count += 1
print("reviewed rows", count)
