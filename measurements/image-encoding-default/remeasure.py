#!/usr/bin/env python3
"""Measure what the automatic default wrote, against a PNG-default conversion of the same book.

    python3 remeasure.py --case faa-phak-8083-25c --baseline base.epub --candidate new.epub \
        --scratch DIR --rows out.jsonl --summary out.json [--strips DIR]

Both EPUBs come from the same source with the same options except the encoding default: the
baseline is 0046fdd (PNG everywhere), the candidate this branch (`.automatic(jpegQuality: 0.90)`).
The converter emits the same rasters in the same order either way, so `image-N` names the same
raster in both; each pair is checked for equal pixel dimensions and any mismatch is reported.

For each candidate asset the row records its format and bytes and the baseline PNG bytes. For
every asset the candidate wrote as JPEG it also records the survey's fidelity measures
(`survey.fidelity`: PSNR and the worst mean absolute error over an 8x8 block holding a step
edge) of the decoded JPEG against the baseline PNG, which is the lossless picture of the same
raster, and the survey prototype's class for it. Nothing is kept but the rows and the summary;
`--strips` writes PNG | JPEG comparison strips of the worst images for review.
"""
import argparse
import json
import re
from pathlib import Path
import shutil
import sys
import zipfile

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "image-encoding"))
import classifier  # noqa: E402
from survey import dilate, fidelity, read_index  # noqa: E402

Image.MAX_IMAGE_PIXELS = None


def images(epub):
    with zipfile.ZipFile(epub) as z:
        return {Path(i.filename).stem: (i.filename, i.file_size) for i in z.infolist()
                if i.filename.lower().endswith((".png", ".jpg", ".jpeg"))}, \
            sum(i.file_size for i in z.infolist())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", required=True)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--scratch", required=True, type=Path)
    parser.add_argument("--rows", required=True, type=Path)
    parser.add_argument("--summary", required=True, type=Path)
    parser.add_argument("--strips", type=Path, default=None)
    parser.add_argument("--strip-count", type=int, default=3)
    arguments = parser.parse_args()

    base, base_entries = images(arguments.baseline)
    new, new_entries = images(arguments.candidate)
    index = read_index(arguments.candidate)
    work = arguments.scratch / arguments.case
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    rows, mismatched = [], []
    try:
        zb, zn = zipfile.ZipFile(arguments.baseline), zipfile.ZipFile(arguments.candidate)
        for stem in sorted(new, key=lambda s: int(s.split("-")[-1]) if s.split("-")[-1].isdigit() else 0):
            name, size = new[stem]
            meta = index.get(Path(name).name, {})
            row = {"case": arguments.case, "asset": stem, "kind": meta.get("kind"), "page": meta.get("page"),
                   "format": "jpeg" if name.lower().endswith((".jpg", ".jpeg")) else "png",
                   "bytes": size, "baselineBytes": base.get(stem, (None, None))[1]}
            if row["format"] == "jpeg" and stem in base:
                (work / "a.png").write_bytes(zb.read(base[stem][0]))
                (work / "b.jpg").write_bytes(zn.read(name))
                reference = np.asarray(Image.open(work / "a.png").convert("RGB"))
                decoded = np.asarray(Image.open(work / "b.jpg").convert("RGB"))
                if reference.shape != decoded.shape:
                    mismatched.append(stem)
                    row["mismatch"] = True
                else:
                    gray = (0.299 * reference[..., 0] + 0.587 * reference[..., 1]
                            + 0.114 * reference[..., 2]).astype(np.float32)
                    row["fidelity"] = fidelity(reference, decoded, dilate(classifier._gradient(gray) >= 48))
                    f = classifier.features(reference)
                    row["class"] = classifier.classify(f, {"kind": row["kind"] or "region",
                                                           "pageHasText": False,
                                                           "pageImageFilters": ["image"]})[0]
                    row["chromaShare"] = f["chromaShare"]
                    if arguments.strips is not None:
                        row["_strip"] = True
            rows.append(row)
        jpegs = [r for r in rows if "fidelity" in r]
        jpegs.sort(key=lambda r: -r["fidelity"]["worstEdgeBlockMAE"])
        if arguments.strips is not None:
            arguments.strips.mkdir(parents=True, exist_ok=True)
            for r in jpegs[:arguments.strip_count]:
                (work / "a.png").write_bytes(zb.read(base[r["asset"]][0]))
                (work / "b.jpg").write_bytes(zn.read(new[r["asset"]][0]))
                reference, decoded = Image.open(work / "a.png").convert("RGB"), Image.open(work / "b.jpg").convert("RGB")
                x, y = r["fidelity"]["worstEdgeBlockAt"]
                x, y = x + 4, y + 4
                tiles = []
                for im in (reference, decoded):
                    s = min(256, im.width, im.height)
                    left, top = max(0, min(im.width - s, x - s // 2)), max(0, min(im.height - s, y - s // 2))
                    tiles.append(im.crop((left, top, left + s, top + s)).resize((256, 256), Image.NEAREST))
                    z = min(64, im.width, im.height)
                    left, top = max(0, min(im.width - z, x - z // 2)), max(0, min(im.height - z, y - z // 2))
                    tiles.append(im.crop((left, top, left + z, top + z)).resize((256, 256), Image.NEAREST))
                strip = Image.new("RGB", (4 * 256 + 12, 256), (255, 0, 0))
                for i, tile in enumerate((tiles[0], tiles[2], tiles[1], tiles[3])):
                    strip.paste(tile, (i * 260, 0))
                strip.save(arguments.strips / f"{arguments.case}-p{r['page']}-{r['asset']}.png")
        zb.close()
        zn.close()
    finally:
        shutil.rmtree(work, ignore_errors=True)

    for r in rows:
        r.pop("_strip", None)

    # Everything but the images must be the same book: markup, navigation and package agree once
    # image names, media types and the per-run identifier and date are normalized.
    def normalized(text):
        text = re.sub(r"image-(\d+)\.(png|jpg)", r"image-\1.IMAGE", text)
        text = re.sub(r"image/(png|jpeg)", "image/IMAGE", text)
        text = re.sub(r"<dc:identifier[^>]*>[^<]*</dc:identifier>", "", text)
        return re.sub(r'<meta property="dcterms:modified">[^<]*</meta>', "", text)
    with zipfile.ZipFile(arguments.baseline) as zb, zipfile.ZipFile(arguments.candidate) as zn:
        names = sorted(n for n in zb.namelist() if not n.startswith("EPUB/images/"))
        other = sorted(n for n in zn.namelist() if not n.startswith("EPUB/images/"))
        differing = [n for n in names if n not in other
                     or normalized(zb.read(n).decode("utf8", "replace"))
                     != normalized(zn.read(n).decode("utf8", "replace"))]
        differing += [n for n in other if n not in names]
    arguments.rows.parent.mkdir(parents=True, exist_ok=True)
    with arguments.rows.open("w") as out:
        for r in rows:
            out.write(json.dumps(r) + "\n")
    errors = [r["fidelity"]["worstEdgeBlockMAE"] for r in rows if "fidelity" in r]
    summary = {
        "case": arguments.case,
        "images": len(rows),
        "jpegImages": sum(r["format"] == "jpeg" for r in rows),
        "baselineImageBytes": sum(size for _, size in base.values()),
        "candidateImageBytes": sum(r["bytes"] for r in rows),
        "baselineEntryBytes": base_entries,
        "candidateEntryBytes": new_entries,
        "worstEdgeBlockMAE": max(errors) if errors else None,
        "jpegWithEdgeErrorAtLeast30": sum(e >= 30 for e in errors),
        "missingFromBaseline": [r["asset"] for r in rows if r["baselineBytes"] is None],
        "dimensionMismatches": mismatched,
        "sameImageCount": len(base) == len(new),
        "nonImageEntriesDifferingBeyondImageNames": differing,
    }
    arguments.summary.parent.mkdir(parents=True, exist_ok=True)
    arguments.summary.write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
