#!/usr/bin/env python3
"""Measure every image one conversion emits: its class, its PNG bytes, its JPEG bytes at
several qualities, and how far each JPEG is from the PNG.

    python3 survey.py --case dga-2025-2030 --pdf corpus/cache/DGA.pdf \
        --converter .build/release/pdf-reflow --scratch /private/tmp/claude-501/ienc \
        --rows measurements/image-encoding/rows/dga-2025-2030.jsonl

The conversion runs with library defaults except for the two byte budgets, which are removed so
that the whole book's images are emitted and can be counted; PNG stays the encoding, so the PNG
column is the bytes the converter actually wrote. JPEG bytes come from `reencode`, a compiled
ImageIO call identical to `PageRasterizer.write`, so both columns are the converter's own
encoders. Fidelity is measured between the written PNG and the decoded JPEG.

Nothing is kept: the EPUB, the extracted PNGs and the JPEGs are deleted before the process ends,
and only the JSONL row file and any requested crops survive.
"""
import argparse
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import zipfile

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import classifier

Image.MAX_IMAGE_PIXELS = None
QUALITIES = (0.95, 0.90, 0.85)


def free_gib(path="/System/Volumes/Data"):
    stat = os.statvfs(path)
    return stat.f_bavail * stat.f_frsize / 2 ** 30


def page_evidence(pdf, pages):
    """Per-page PDF-side evidence: native text, and the page's image XObjects.

    Both come from Poppler here because the survey is outside the library. In the library both
    are already at hand: `PDFPage.string` (or the text layer the extractor built) answers the
    first, and the page's resource dictionary answers the second.
    """
    evidence = {p: {"nativeTextCharacters": 0, "imageFilters": [], "imageCount": 0,
                    "largestImagePixels": 0} for p in range(1, pages + 1)}
    text = subprocess.run(["pdftotext", str(pdf), "-"], capture_output=True).stdout
    for index, chunk in enumerate(text.split(b"\x0c"), start=1):
        if index in evidence:
            evidence[index]["nativeTextCharacters"] = len(chunk.strip())
    listing = subprocess.run(["pdfimages", "-list", str(pdf)], capture_output=True).stdout.decode()
    for line in listing.splitlines()[2:]:
        parts = line.split()
        if len(parts) < 9 or not parts[0].isdigit():
            continue
        page, width, height, enc = int(parts[0]), parts[3], parts[4], parts[8]
        if page not in evidence:
            continue
        row = evidence[page]
        row["imageCount"] += 1
        if enc not in row["imageFilters"]:
            row["imageFilters"].append(enc)
        try:
            row["largestImagePixels"] = max(row["largestImagePixels"], int(width) * int(height))
        except ValueError:
            pass
    return evidence


def convert(converter, pdf, epub, extra):
    started = time.time()
    command = [str(converter), str(pdf), str(epub),
               "--maximum-output-bytes", "unlimited", "--maximum-epub-bytes", "unlimited"] + extra
    done = subprocess.run(command, capture_output=True)
    if done.returncode != 0:
        raise SystemExit(f"conversion failed ({done.returncode}): {done.stderr.decode()[:2000]}")
    report = json.loads(done.stdout.decode())
    report["seconds"] = round(time.time() - started, 2)
    return report


def read_index(epub):
    """Map each image asset to its kind (page reference or region crop), page and stored bytes."""
    with zipfile.ZipFile(epub) as z:
        sizes = {i.filename.split("/")[-1]: i.file_size for i in z.infolist()
                 if i.filename.lower().endswith((".png", ".jpg", ".jpeg"))}
        index = {}
        for name in z.namelist():
            if not name.endswith(".xhtml"):
                continue
            markup = z.read(name).decode("utf8", errors="replace")
            for tag in re.finditer(r"<img[^>]*>", markup):
                s = tag.group(0)
                src = re.search(r'src="([^"]+)"', s).group(1).split("/")[-1]
                alt = re.search(r'alt="([^"]*)"', s)
                alt = alt.group(1) if alt else ""
                page = re.search(r"page (\d+)", alt)
                index[src] = {
                    "asset": src,
                    "kind": "reference" if alt.startswith("Original page") else "region",
                    "page": int(page.group(1)) if page else None,
                    "alt": alt[:160],
                    "pngBytes": sizes.get(src, 0),
                }
        for name, size in sizes.items():
            index.setdefault(name, {"asset": name, "kind": "unreferenced", "page": None,
                                    "alt": "", "pngBytes": size})
    return index


def extract(epub, into):
    into.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(epub) as z:
        for info in z.infolist():
            if info.filename.lower().endswith(".png"):
                (into / info.filename.split("/")[-1]).write_bytes(z.read(info))


def dilate(mask):
    out = mask.copy()
    out[:, :-1] |= mask[:, 1:]
    out[:, 1:] |= mask[:, :-1]
    out[:-1, :] |= mask[1:, :]
    out[1:, :] |= mask[:-1, :]
    return out


def fidelity(reference, candidate, edges):
    """PSNR over the whole image, and the worst-case error concentrated on edges.

    `edges` is the dilated step-edge mask. The block figure is the largest mean absolute error
    over any 8x8 block that contains an edge: a single ringing artefact shows there even when it
    is invisible in a whole-image average.
    """
    difference = np.abs(reference.astype(np.int16) - candidate.astype(np.int16))
    mse = float((difference.astype(np.float64) ** 2).mean())
    psnr = float("inf") if mse == 0 else 10 * np.log10(255.0 ** 2 / mse)
    worst = difference.max(axis=2).astype(np.float32)

    height, width = worst.shape
    bh, bw = height // 8 * 8, width // 8 * 8
    row = column = 0
    block_mae = edge_block_mae = 0.0
    if bh and bw:
        blocks = worst[:bh, :bw].reshape(bh // 8, 8, bw // 8, 8).mean(axis=(1, 3))
        edge_blocks = edges[:bh, :bw].reshape(bh // 8, 8, bw // 8, 8).any(axis=(1, 3))
        block_mae = float(blocks.max())
        if edge_blocks.any():
            masked = np.where(edge_blocks, blocks, -1.0)
            flat = int(masked.argmax())
            row, column = divmod(flat, masked.shape[1])
            edge_block_mae = float(masked[row, column])
    on_edges = worst[edges] if edges.any() else np.zeros(1, dtype=np.float32)
    return {
        "psnr": round(psnr, 2) if np.isfinite(psnr) else None,
        "worstBlockMAE": round(block_mae, 2),
        "worstEdgeBlockMAE": round(edge_block_mae, 2),
        "worstEdgeBlockAt": [int(column) * 8, int(row) * 8],
        "edgeP999": round(float(np.percentile(on_edges, 99.9)), 1),
        "edgeMax": int(on_edges.max()),
        "maxError": int(worst.max()),
    }


def save_crop(destination, png, jpegs, centre, label):
    """A 256-pixel square of the PNG beside the same square of each JPEG, one strip."""
    size = 256
    x, y = centre
    left = max(0, min(png.width - size, x - size // 2))
    top = max(0, min(png.height - size, y - size // 2))
    box = (left, top, min(png.width, left + size), min(png.height, top + size))
    tiles = [png.crop(box)] + [j.crop(box) for j in jpegs]
    width = sum(t.width for t in tiles) + 4 * (len(tiles) - 1)
    strip = Image.new("RGB", (width, tiles[0].height), (255, 0, 0))
    offset = 0
    for tile in tiles:
        strip.paste(tile, (offset, 0))
        offset += tile.width + 4
    destination.parent.mkdir(parents=True, exist_ok=True)
    strip.save(destination, "PNG", optimize=True)
    (destination.with_suffix(".txt")).write_text(label + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", required=True)
    parser.add_argument("--pdf", required=True, type=Path)
    parser.add_argument("--converter", required=True, type=Path)
    parser.add_argument("--reencode", required=True, type=Path)
    parser.add_argument("--scratch", required=True, type=Path)
    parser.add_argument("--rows", required=True, type=Path)
    parser.add_argument("--summary", required=True, type=Path)
    parser.add_argument("--option", action="append", default=[],
                        help="extra converter argument, repeated (e.g. --option --ocr --option never)")
    parser.add_argument("--minimum-free-gib", type=float, default=8.0)
    parser.add_argument("--crops", type=Path, default=None,
                        help="write a worst-case crop strip per class into this directory. "
                             "Omit for documents whose rasters may not be committed.")
    arguments = parser.parse_args()

    if free_gib() < arguments.minimum_free_gib:
        raise SystemExit(f"only {free_gib():.1f} GiB free; refusing to convert")

    work = arguments.scratch / arguments.case
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    epub = work / f"{arguments.case}.epub"
    try:
        report = convert(arguments.converter, arguments.pdf, epub, arguments.option)
        index = read_index(epub)
        pages = report["pageCount"]
        evidence = page_evidence(arguments.pdf, pages)

        pngs, jpegs = work / "png", work / "jpeg"
        extract(epub, pngs)
        epub_bytes = epub.stat().st_size
        with zipfile.ZipFile(epub) as z:
            entry_bytes = sum(i.file_size for i in z.infolist())
        epub.unlink()

        sizes = json.loads(subprocess.run(
            [str(arguments.reencode), str(pngs), str(jpegs),
             ",".join(f"{q:.2f}" for q in QUALITIES)],
            capture_output=True, check=True).stdout)

        arguments.rows.parent.mkdir(parents=True, exist_ok=True)
        written = 0
        worst = {}
        with arguments.rows.open("w") as out:
            for asset in sorted(index):
                stem = asset.rsplit(".", 1)[0]
                if stem not in sizes:
                    continue
                row = dict(index[asset])
                row["case"] = arguments.case
                page_row = evidence.get(row["page"] or -1, {})
                row["pageNativeTextCharacters"] = page_row.get("nativeTextCharacters", 0)
                row["pageImageFilters"] = page_row.get("imageFilters", [])
                row["pageImageCount"] = page_row.get("imageCount", 0)

                rgb = np.asarray(Image.open(pngs / asset).convert("RGB"))
                f = classifier.features(rgb)
                row["features"] = f
                evidence_for_rule = {
                    "kind": row["kind"],
                    "pageHasText": page_row.get("nativeTextCharacters", 0) >= 200,
                    "pageImageFilters": page_row.get("imageFilters", []),
                }
                row["class"], row["classReason"] = classifier.classify(f, evidence_for_rule)

                gray = (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1]
                        + 0.114 * rgb[..., 2]).astype(np.float32)
                edges = dilate(classifier._gradient(gray) >= 48)

                row["bytes"] = {"png": sizes[stem]["png"]}
                row["fidelity"] = {}
                for quality in QUALITIES:
                    label = f"q{int(round(quality * 100))}"
                    row["bytes"][label] = sizes[stem][label]
                    decoded = np.asarray(Image.open(jpegs / f"{stem}.{label}.jpg").convert("RGB"))
                    row["fidelity"][label] = fidelity(rgb, decoded, edges)
                out.write(json.dumps(row) + "\n")
                written += 1

                if arguments.crops is not None:
                    score = row["fidelity"]["q90"]["worstEdgeBlockMAE"]
                    if score > worst.get(row["class"], (0,))[0]:
                        worst[row["class"]] = (score, asset, stem, row)

        for klass, (score, asset, stem, row) in sorted(worst.items()):
            centre = row["fidelity"]["q90"]["worstEdgeBlockAt"]
            centre = (centre[0] + 4, centre[1] + 4)
            png = Image.open(pngs / asset).convert("RGB")
            jpegs_open = [Image.open(jpegs / f"{stem}.q{int(round(q*100))}.jpg").convert("RGB")
                          for q in QUALITIES]
            slug = klass.replace(" ", "-").replace("(", "").replace(")", "")
            save_crop(arguments.crops / f"{arguments.case}-{slug}.png", png, jpegs_open, centre,
                      f"{arguments.case} page {row['page']} ({row['kind']}, {klass}); "
                      f"PNG | q95 | q90 | q85 at ({centre[0]}, {centre[1]}) of "
                      f"{png.width}x{png.height}; worst 8x8 edge-block MAE at q90 "
                      f"{score} levels; PNG {row['bytes']['png']} bytes, "
                      f"q90 {row['bytes']['q90']} bytes")

        arguments.summary.parent.mkdir(parents=True, exist_ok=True)
        arguments.summary.write_text(json.dumps({
            "case": arguments.case,
            "pdf": str(arguments.pdf),
            "conversionReport": {k: v for k, v in report.items()
                                 if k in ("imageCount", "pageCount", "recognizedPageCount",
                                          "reflowedPageCount", "seconds")},
            "warningCodes": sorted({w["code"] for w in report.get("warnings", [])}),
            "entryBytes": entry_bytes,
            "epubBytes": epub_bytes,
            "measuredImages": written,
            "options": arguments.option,
        }, indent=2))
        print(f"{arguments.case}: {written} images, entry {entry_bytes/2**20:.2f} MiB, "
              f"{report['seconds']}s, {free_gib():.1f} GiB free")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
