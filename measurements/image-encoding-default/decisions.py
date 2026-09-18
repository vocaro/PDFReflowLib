#!/usr/bin/env python3
"""Per image, did the converter do what the survey's rows project?

    python3 decisions.py --results DIR

Pairs each image `remeasure.py` recorded with the survey row for the same raster: same document,
page and role, and the same PNG bytes (the baseline's PNG is byte-identical to the survey's when
the raster is). Asset numbers are not used, because crops added or removed since the survey
(88803ac) renumber every later asset. For each pair it compares the written format with the
survey's projection under the adopted rule (`analyse.adopted`: permitted, and JPEG 0.90 smaller
than PNG) and lists every disagreement with the survey's class and page evidence.
"""
import argparse
import gzip
import importlib.util
import json
from pathlib import Path
from collections import Counter

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("adopted_rule", HERE / "analyse.py")
rule = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rule)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True, type=Path)
    arguments = parser.parse_args()
    survey = {}
    for line in gzip.open(HERE.parent / "image-encoding" / "rows.jsonl.gz"):
        r = json.loads(line)
        key = (r["case"], r["page"], r["kind"], r["bytes"]["png"])
        survey.setdefault(key, []).append(r)
    counts, disagreements = Counter(), []
    for path in sorted(arguments.results.glob("*-rows.jsonl")):
        for line in path.open():
            w = json.loads(line)
            candidates = survey.get((w["case"], w["page"], w["kind"], w["baselineBytes"]))
            if not candidates:
                counts["unpaired"] += 1
                continue
            s = candidates[0]
            projected = rule.adopted(s["class"], s["features"], s["kind"]) and s["bytes"]["q90"] < s["bytes"]["png"]
            written = w["format"] == "jpeg"
            counts["paired"] += 1
            if projected == written:
                counts["agree"] += 1
                if written and w["bytes"] != s["bytes"]["q90"]:
                    counts["jpegBytesDiffer"] += 1
            else:
                disagreements.append((w["case"], w["page"], w["kind"], w["asset"], s["class"],
                                      round(s["features"]["chromaShare"], 3), s["pageNativeTextCharacters"],
                                      s["pageImageFilters"], "written " + w["format"],
                                      f"PNG {s['bytes']['png']:,} / q90 {s['bytes']['q90']:,}"))
    print(dict(counts))
    for d in disagreements:
        print(" ", *d)


if __name__ == "__main__":
    main()
