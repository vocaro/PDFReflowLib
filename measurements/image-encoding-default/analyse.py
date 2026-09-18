#!/usr/bin/env python3
"""Per-book tables: the survey's projection against what the automatic default wrote.

    python3 analyse.py --results DIR > tables.md

`DIR` holds `<case>-summary.json` and `<case>-rows.jsonl` from `remeasure.py`. The projection
is recomputed from the survey's stored rows (`../image-encoding/rows.jsonl.gz`) twice: with the
prototype's `lossy_is_safe`, and with the one tightening the library adopted (a coloured
continuous-tone crop at least 30% flat stays PNG). Either way an image is projected to JPEG when
the rule permits lossy and the survey's JPEG 0.90 is smaller than its PNG.
"""
import argparse
import gzip
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "image-encoding"))
import classifier  # noqa: E402

MIB = 2 ** 20


def adopted(klass, f, kind):
    if (kind != "reference" and klass == classifier.CONTINUOUS_TONE and f["chromaShare"] >= 0.02
            and f["flatShare"] >= 0.30):
        return False
    return classifier.lossy_is_safe(klass, f, kind)


def project(rows, rule):
    out = {}
    for r in rows:
        book = out.setdefault(r["case"], {"images": 0, "png": 0, "bytes": 0, "jpeg": 0, "damaged": 0,
                                          "worst": 0.0})
        b = r["bytes"]
        book["images"] += 1
        book["png"] += b["png"]
        if rule(r["class"], r["features"], r["kind"]) and b["q90"] < b["png"]:
            book["bytes"] += b["q90"]
            book["jpeg"] += 1
            error = r["fidelity"]["q90"]["worstEdgeBlockMAE"]
            book["damaged"] += error >= 30
            book["worst"] = max(book["worst"], error)
        else:
            book["bytes"] += b["png"]
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", required=True, type=Path)
    arguments = parser.parse_args()
    survey = [json.loads(line) for line in gzip.open(HERE.parent / "image-encoding" / "rows.jsonl.gz")]
    prototype, tightened = project(survey, classifier.lossy_is_safe), project(survey, adopted)

    print("| Document | Images | PNG MiB (0046fdd) | automatic MiB | vs PNG | projected MiB (survey rule / adopted) "
          "| JPEG written | projected JPEG (survey / adopted) | worst edge error | ≥ 30 levels |")
    print("| --- | ---: | ---: | ---: | ---: | --- | ---: | --- | ---: | ---: |")
    totals = {k: 0 for k in ("images", "base", "new", "jpeg", "damaged", "pp", "pa", "jp", "ja")}
    worst = 0.0
    for path in sorted(arguments.results.glob("*-summary.json")):
        s = json.loads(path.read_text())
        case = s["case"]
        p, a = prototype.get(case), tightened.get(case)
        change = (s["candidateImageBytes"] - s["baselineImageBytes"]) / s["baselineImageBytes"] * 100 \
            if s["baselineImageBytes"] else 0.0
        projected = f"{p['bytes'] / MIB:.2f} / {a['bytes'] / MIB:.2f}" if p else "not surveyed"
        projected_jpeg = f"{p['jpeg']} / {a['jpeg']}" if p else "—"
        edge = f"{s['worstEdgeBlockMAE']:.1f}" if s["worstEdgeBlockMAE"] is not None else "—"
        print(f"| {case} | {s['images']:,} | {s['baselineImageBytes'] / MIB:.2f} | {s['candidateImageBytes'] / MIB:.2f} "
              f"| {change:+.1f}% | {projected} | {s['jpegImages']:,} | {projected_jpeg} | {edge} "
              f"| {s['jpegWithEdgeErrorAtLeast30']} |")
        totals["images"] += s["images"]
        totals["base"] += s["baselineImageBytes"]
        totals["new"] += s["candidateImageBytes"]
        totals["jpeg"] += s["jpegImages"]
        totals["damaged"] += s["jpegWithEdgeErrorAtLeast30"]
        if p:
            totals["pp"] += p["bytes"]
            totals["pa"] += a["bytes"]
            totals["jp"] += p["jpeg"]
            totals["ja"] += a["jpeg"]
        worst = max(worst, s["worstEdgeBlockMAE"] or 0)
    change = (totals["new"] - totals["base"]) / totals["base"] * 100
    print(f"| **all measured** | **{totals['images']:,}** | **{totals['base'] / MIB:.2f}** | **{totals['new'] / MIB:.2f}** "
          f"| **{change:+.1f}%** | {totals['pp'] / MIB:.2f} / {totals['pa'] / MIB:.2f} | **{totals['jpeg']:,}** "
          f"| {totals['jp']:,} / {totals['ja']:,} | **{worst:.1f}** | **{totals['damaged']}** |")

    print()
    print("Survey projection over all 20 surveyed documents:")
    for name, table in (("survey rule", prototype), ("adopted rule", tightened)):
        size = sum(b["bytes"] for b in table.values())
        print(f"- {name}: {size / MIB:.2f} MiB, {sum(b['jpeg'] for b in table.values()):,} JPEG, "
              f"{sum(b['damaged'] for b in table.values())} with edge error ≥ 30, "
              f"worst {max(b['worst'] for b in table.values()):.1f}")

    print()
    print("Written JPEGs with a worst edge-block error of 30 levels or more:")
    for path in sorted(arguments.results.glob("*-rows.jsonl")):
        for line in path.open():
            r = json.loads(line)
            if r.get("fidelity") and r["fidelity"]["worstEdgeBlockMAE"] >= 30:
                print(f"- {r['case']} page {r['page']} {r['kind']} {r['asset']}: "
                      f"{r['fidelity']['worstEdgeBlockMAE']:.1f} ({r.get('class')}, chroma "
                      f"{r['chromaShare']:.3f}; {r['baselineBytes']:,} → {r['bytes']:,} bytes)")


if __name__ == "__main__":
    main()
