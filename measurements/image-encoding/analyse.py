#!/usr/bin/env python3
"""Aggregate the survey rows: per-class size and fidelity tables, and per-book totals under
each encoding policy.

    python3 analyse.py --rows /private/tmp/claude-501/ienc/rows \
        --summaries /private/tmp/claude-501/ienc/summary

Policies compared, all over the images one conversion emits, with the non-image entries of the
book held at their measured size:

    png                  every image PNG (today's default)
    jpeg:0.90            every image JPEG at 0.90
    smallest:0.90        per image, the smaller of PNG and JPEG 0.90 (today's best-bytes option)
    proposed             smallest, but only where `classifier.lossy_is_safe` allows lossy
    tonal classes only   the same without the "no chroma to lose" escape, to price that escape
    text-lossless        smallest:0.90 everywhere except text pages, which stay PNG

The classification is recomputed here from the stored features, so the rule can be changed
without reconverting anything.
"""
import argparse
import collections
import json
from pathlib import Path
import statistics as st
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import classifier

MIB = 1024 * 1024
QUALITIES = ("q95", "q90", "q85")
TONAL = set(classifier.TONAL_CLASSES)
TEXT = set(classifier.TEXT_CLASSES)


def policies(row):
    """Bytes this image would cost under each policy."""
    b = row["bytes"]
    png, jpeg = b["png"], b["q90"]
    klass, kind, f = row["class"], row["kind"], row["features"]
    tonal = klass in TONAL
    return {
        "png": png,
        "jpeg:0.90": jpeg,
        "smallest:0.90": min(png, jpeg),
        # The proposal: lossy where the classifier says lossy is safe, and only where it is
        # also smaller.
        "proposed": (min(png, jpeg) if classifier.lossy_is_safe(klass, f, kind) else png),
        # The same rule without the "no chroma to lose" escape, to price that escape.
        "tonal classes only": min(png, jpeg) if tonal else png,
        # What the owner's question asks about: bytes only, except text pages stay lossless.
        "text-lossless": png if klass in TEXT else min(png, jpeg),
    }


POLICY_NAMES = ("png", "jpeg:0.90", "smallest:0.90", "proposed", "tonal classes only",
                "text-lossless")


def load(rows_directory):
    rows = []
    for path in sorted(Path(rows_directory).glob("*.jsonl")):
        for line in path.open():
            row = json.loads(line)
            evidence = {
                "kind": row["kind"],
                "pageHasText": row.get("pageNativeTextCharacters", 0) >= 200,
                "pageImageFilters": row.get("pageImageFilters", []),
            }
            row["class"], row["classReason"] = classifier.classify(row["features"], evidence)
            rows.append(row)
    return rows


def quantiles(values):
    values = [v for v in values if v is not None]
    if not values:
        return None, None, None
    return min(values), st.median(values), max(values)


def table(rows, group, title, out):
    out(f"\n### {title}\n")
    out("| Class | Images | PNG | JPEG 0.95 | JPEG 0.90 | JPEG 0.85 | median q90 of PNG "
        "| worst q90 of PNG |")
    out("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for klass in sorted(group, key=lambda k: -sum(r["bytes"]["png"] for r in group[k])):
        sel = group[klass]
        png = sum(r["bytes"]["png"] for r in sel)
        cells = [f"{png/MIB:.2f}"]
        for q in QUALITIES:
            cells.append(f"{sum(r['bytes'][q] for r in sel)/MIB:.2f}")
        ratios = [r["bytes"]["q90"] / r["bytes"]["png"] for r in sel if r["bytes"]["png"]]
        out(f"| {klass} | {len(sel):,} | " + " | ".join(cells)
            + f" | {st.median(ratios):.0%} | {max(ratios):.0%} |")
    out(f"\n{title}: {sum(len(v) for v in group.values()):,} images, "
        f"{sum(r['bytes']['png'] for v in group.values() for r in v)/MIB:.2f} MiB of PNG.")


def fidelity_table(rows, group, title, out):
    out(f"\n### {title}\n")
    out("| Class | Images | Quality | JPEG of PNG median | PSNR median / worst "
        "| Worst edge-block MAE median / worst | Edge p99.9 median / worst |")
    out("| --- | ---: | --- | ---: | --- | --- | --- |")
    for klass in sorted(group, key=lambda k: -len(group[k])):
        sel = group[klass]
        for q in QUALITIES:
            psnr = [r["fidelity"][q]["psnr"] for r in sel]
            block = [r["fidelity"][q]["worstEdgeBlockMAE"] for r in sel]
            p999 = [r["fidelity"][q]["edgeP999"] for r in sel]
            ratios = [r["bytes"][q] / r["bytes"]["png"] for r in sel if r["bytes"]["png"]]
            _, mp, _ = quantiles(psnr)
            lo = min([v for v in psnr if v is not None], default=None)
            name = klass if q == QUALITIES[0] else ""
            count = f"{len(sel):,}" if q == QUALITIES[0] else ""
            out(f"| {name} | {count} | 0.{q[1:]} | {st.median(ratios):.0%} | "
                + (f"{mp:.1f} / {lo:.1f} dB" if mp else "—")
                + f" | {st.median(block):.1f} / {max(block):.1f}"
                + f" | {st.median(p999):.0f} / {max(p999):.0f} |")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rows", required=True, type=Path)
    parser.add_argument("--summaries", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=None)
    arguments = parser.parse_args()

    rows = load(arguments.rows)
    lines = []
    out = lines.append

    summaries = {}
    for path in sorted(arguments.summaries.glob("*.json")):
        s = json.loads(path.read_text())
        summaries[s["case"]] = s

    out(f"Images measured: {len(rows):,} over {len(summaries)} documents.\n")

    for kind, label in (("reference", "Full-page images (references and fallbacks)"),
                        ("region", "Region crops")):
        group = collections.defaultdict(list)
        for r in rows:
            if (r["kind"] == "region") == (kind == "region"):
                group[r["class"]].append(r)
        table(rows, group, label + " — size", out)
        fidelity_table(rows, group, label + " — fidelity at JPEG 0.90", out)

    # Per-book totals.
    out("\n### Per-document image bytes under each policy\n")
    header = "| Document | Images | " + " | ".join(POLICY_NAMES) + " |"
    out(header)
    out("| --- | ---: | " + " | ".join(["---:"] * len(POLICY_NAMES)) + " |")
    totals = collections.Counter()
    by_case = collections.defaultdict(list)
    for r in rows:
        by_case[r["case"]].append(r)
    for case in sorted(by_case):
        sel = by_case[case]
        book = collections.Counter()
        for r in sel:
            for name, value in policies(r).items():
                book[name] += value
        totals.update(book)
        cells = [f"{book[name]/MIB:.2f}" for name in POLICY_NAMES]
        out(f"| {case} | {len(sel):,} | " + " | ".join(cells) + " |")
    out(f"| **all** | **{len(rows):,}** | "
        + " | ".join(f"**{totals[n]/MIB:.2f}**" for n in POLICY_NAMES) + " |")

    out("\n### Saving against PNG and against smallest:0.90\n")
    out("| Document | PNG MiB | proposed MiB | vs PNG | vs smallest:0.90 |")
    out("| --- | ---: | ---: | ---: | ---: |")
    for case in sorted(by_case):
        book = collections.Counter()
        for r in by_case[case]:
            for name, value in policies(r).items():
                book[name] += value
        png, aware, small = book["png"], book["proposed"], book["smallest:0.90"]
        out(f"| {case} | {png/MIB:.2f} | {aware/MIB:.2f} | "
            f"{(aware-png)/png:+.1%} | {(aware-small)/small:+.1%} |")
    png, aware, small = totals["png"], totals["proposed"], totals["smallest:0.90"]
    out(f"| **all** | **{png/MIB:.2f}** | **{aware/MIB:.2f}** | **{(aware-png)/png:+.1%}** | "
        f"**{(aware-small)/small:+.1%}** |")

    # Entry budget: the non-image entries of each book, plus images under each policy.
    out("\n### Uncompressed entry bytes against the 512 MiB default\n")
    out("| Document | Non-image entries MiB | " + " | ".join(POLICY_NAMES) + " |")
    out("| --- | ---: | " + " | ".join(["---:"] * len(POLICY_NAMES)) + " |")
    budget = 512 * MIB
    headroom = {}
    for case in sorted(by_case):
        summary = summaries.get(case)
        if not summary:
            continue
        images = sum(r["bytes"]["png"] for r in by_case[case])
        other = summary["entryBytes"] - images
        book = collections.Counter()
        for r in by_case[case]:
            for name, value in policies(r).items():
                book[name] += value
        cells = [f"{(other+book[n])/MIB:.2f}" for n in POLICY_NAMES]
        headroom[case] = {n: budget - (other + book[n]) for n in POLICY_NAMES}
        out(f"| {case} | {other/MIB:.2f} | " + " | ".join(cells) + " |")

    out("\n### Headroom under the 512 MiB entry budget, in bytes (negative is over)\n")
    out("| Document | " + " | ".join(POLICY_NAMES) + " |")
    out("| --- | " + " | ".join(["---:"] * len(POLICY_NAMES)) + " |")
    for case in sorted(headroom):
        row = headroom[case]
        if min(row.values()) > 64 * MIB:
            continue  # books with more than 64 MiB of slack under every policy
        out(f"| {case} | " + " | ".join(f"{row[n]:,}" for n in POLICY_NAMES) + " |")
    out("\nDocuments with more than 64 MiB of headroom under every policy are omitted.")

    # Where a class splits: a scanned page's encoding depends on whether the scan is two-tone.
    out("\n### Bilevel share against what JPEG 0.90 costs, for full-page scans\n")
    out("| bilevelShare | Pages | median JPEG 0.90 of PNG | median PNG MiB |")
    out("| --- | ---: | ---: | ---: |")
    scans = [r for r in rows if r["kind"] == "reference"
             and r["class"] in (classifier.TEXT_SCAN_BILEVEL, classifier.TEXT_SCAN_TONAL)]
    buckets = collections.defaultdict(list)
    for r in scans:
        share = r["features"].get("bilevelShare", 0.0)
        buckets[min(9, int(share * 10))].append(r)
    for bucket in sorted(buckets):
        sel = buckets[bucket]
        ratios = [r["bytes"]["q90"] / r["bytes"]["png"] for r in sel if r["bytes"]["png"]]
        out(f"| {bucket/10:.1f}–{bucket/10+0.1:.1f} | {len(sel):,} | {st.median(ratios):.0%} | "
            f"{st.median([r['bytes']['png'] for r in sel])/MIB:.2f} |")

    text = "\n".join(lines)
    if arguments.output:
        arguments.output.write_text(text + "\n")
    print(text)


if __name__ == "__main__":
    main()
