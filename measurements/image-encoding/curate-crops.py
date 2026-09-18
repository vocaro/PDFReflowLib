#!/usr/bin/env python3
"""Assemble the worst-case crops the record cites from the strips `survey.py` wrote.

`survey.py --crops` writes one strip per document and class: the worst image of that class in
that document, as four 256-pixel tiles (PNG, JPEG 0.95, 0.90, 0.85) centred on its worst 8x8
edge block. This keeps the named stems and gives each a second row, the middle of the same four
tiles at 4x, because at 1:1 a chroma artefact on 10-pixel type is real and invisible.

    python3 curate-crops.py --source /private/tmp/claude-501/ienc/strips \
        --destination measurements/image-encoding/crops

Documents whose rights forbid committing a raster never have a strip written for them, so none
can be selected here.
"""
import argparse
from pathlib import Path

from PIL import Image

KEEP = (
    "faa-phak-8083-25c-mixed",
    "faa-phak-8083-25c-line-art-or-chart",
    "faa-phak-8083-25c-continuous-tone-art",
    "noaa-nca5-2023-line-art-or-chart",
    "gpo-our-flag-2003-line-art-or-chart",
    "fed-explained-2021-line-art-or-chart",
    "noaa-nca5-2023-photograph",
    "cdc-zombie-pandemic-2011-mixed",
    "gpo-warren-1964-text-page-tonal-scan",
    "noaa-nca5-2023-text-page-tonal-scan",
    "cia-blue-book-14-1955-text-page-bilevel-scan",
)
TILE, GAP, ZOOM, WINDOW = 256, 4, 4, 64


def assemble(source, destination):
    strip = Image.open(source).convert("RGB")
    left = (TILE - WINDOW) // 2
    zoomed = [strip.crop((k * (TILE + GAP) + left, left,
                          k * (TILE + GAP) + left + WINDOW, left + WINDOW))
              .resize((WINDOW * ZOOM, WINDOW * ZOOM), Image.NEAREST) for k in range(4)]
    bottom = WINDOW * ZOOM * 4 + GAP * 3
    out = Image.new("RGB", (max(strip.width, bottom), strip.height + GAP + WINDOW * ZOOM),
                    (255, 0, 0))
    out.paste(strip, (0, 0))
    for k, tile in enumerate(zoomed):
        out.paste(tile, (k * (WINDOW * ZOOM + GAP), strip.height + GAP))
    out.save(destination, "PNG", optimize=True)
    label = source.with_suffix(".txt").read_text().rstrip("\n")
    destination.with_suffix(".txt").write_text(
        label + f"; lower row is the middle {WINDOW}x{WINDOW} pixels at {ZOOM}x\n")
    return out.size, destination.stat().st_size


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    arguments = parser.parse_args()
    if arguments.source.resolve() == arguments.destination.resolve():
        raise SystemExit("source and destination must differ; this rewrites each picture")
    arguments.destination.mkdir(parents=True, exist_ok=True)
    for path in sorted(arguments.source.glob("*.png")):
        if path.stem not in KEEP:
            continue
        size, written = assemble(path, arguments.destination / path.name)
        print(path.name, size, written)


if __name__ == "__main__":
    main()
