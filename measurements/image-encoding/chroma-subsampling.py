#!/usr/bin/env python3
"""Why JPEG quality barely moves the error on coloured line art: ImageIO halves the chroma
planes at every quality below 1.0.

Converts one document, re-encodes its images at 1.00, 0.95, 0.90 and 0.85, and reports the
JPEG sampling factors, the quantisation tables' first coefficients, the bytes and the error
against the PNG. Deletes everything it made.

    python3 chroma-subsampling.py --case dga-2025-2030 --pdf corpus/cache/DGA.pdf \
        --converter .build/release/pdf-reflow --reencode /private/tmp/claude-501/ienc/reencode \
        --scratch /private/tmp/claude-501/ienc/chroma
"""
import argparse
import json
from pathlib import Path
import shutil
import statistics as st
import subprocess
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import classifier
import survey

QUALITIES = (1.00, 0.95, 0.90, 0.85)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--case", required=True)
    parser.add_argument("--pdf", required=True, type=Path)
    parser.add_argument("--converter", required=True, type=Path)
    parser.add_argument("--reencode", required=True, type=Path)
    parser.add_argument("--scratch", required=True, type=Path)
    arguments = parser.parse_args()

    work = arguments.scratch / arguments.case
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    try:
        epub = work / "book.epub"
        survey.convert(arguments.converter, arguments.pdf, epub, [])
        pngs, jpegs = work / "png", work / "jpeg"
        survey.extract(epub, pngs)
        epub.unlink()
        sizes = json.loads(subprocess.run(
            [str(arguments.reencode), str(pngs), str(jpegs),
             ",".join(f"{q:.2f}" for q in QUALITIES)], capture_output=True, check=True).stdout)

        print(f"{arguments.case}: {len(sizes)} images\n")
        print("| Quality | Luma sampling | Chroma sampling | Luma quant [0:3] "
              "| Chroma quant [0:3] | JPEG of PNG median | PSNR median | Worst edge-block MAE "
              "median / worst |")
        print("| --- | --- | --- | --- | --- | ---: | ---: | --- |")
        decoded_png = {}
        for stem in sizes:
            decoded_png[stem] = np.asarray(Image.open(pngs / f"{stem}.png").convert("RGB"))
        for quality in QUALITIES:
            label = f"q{int(round(quality * 100))}"
            ratios, psnrs, blocks, layers, quant = [], [], [], None, None
            for stem, row in sizes.items():
                path = jpegs / f"{stem}.{label}.jpg"
                image = Image.open(path)
                image.load()
                if layers is None:
                    layers = image.layer
                    quant = (list(image.quantization[0][:3]),
                             list(image.quantization[1][:3]) if 1 in image.quantization else None)
                reference = decoded_png[stem]
                gray = (0.299 * reference[..., 0] + 0.587 * reference[..., 1]
                        + 0.114 * reference[..., 2]).astype(np.float32)
                edges = survey.dilate(classifier._gradient(gray) >= 48)
                f = survey.fidelity(reference, np.asarray(image.convert("RGB")), edges)
                ratios.append(row[label] / row["png"])
                if f["psnr"] is not None:
                    psnrs.append(f["psnr"])
                blocks.append(f["worstEdgeBlockMAE"])
            luma = f"{layers[0][1]}x{layers[0][2]}"
            chroma = f"{layers[1][1]}x{layers[1][2]}"
            print(f"| {quality:.2f} | {luma} | {chroma} | {quant[0]} | {quant[1]} | "
                  f"{st.median(ratios):.0%} | {st.median(psnrs):.1f} dB | "
                  f"{st.median(blocks):.1f} / {max(blocks):.1f} |")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
