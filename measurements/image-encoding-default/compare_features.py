#!/usr/bin/env python3
"""Compare the Swift classifier's features and verdicts with the survey's Python prototype.

    python3 compare_features.py --features /path/to/features --scratch DIR \
        --rows out.jsonl --per-book 40 book-a.epub book-b.epub ...

Reads the PNG images of PNG-default EPUBs (the 0046fdd baseline), picks up to `--per-book`
images per book spread evenly over its assets (every one when the book has fewer), and runs
`classifier.features`/`classify`/`lossy_is_safe` from `measurements/image-encoding` and the
compiled `features` tool (the library's `ImageContentClassifier.swift`) on the same file with
the same role and page evidence. Page evidence is fixed at "drawn from an image" for full pages
on both sides, so only the port is compared here, not the page signal.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "image-encoding"))
import classifier  # noqa: E402
from survey import read_index  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
FEATURES = ("backgroundShare", "chromaShare", "bilevelShare", "distinctColours", "flatShare",
            "hardEdgeShare", "softEdgeShare")


def lossy_is_safe(klass, f, kind):
    """The survey's rule with the one tightening the library adopts (#193): a coloured
    continuous-tone crop that is at least 30% flat is drawn illustration and stays PNG."""
    if (kind != "reference" and klass == classifier.CONTINUOUS_TONE and f["chromaShare"] >= 0.02
            and f["flatShare"] >= 0.30):
        return False
    return classifier.lossy_is_safe(klass, f, kind)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--features", required=True, type=Path)
    parser.add_argument("--scratch", required=True, type=Path)
    parser.add_argument("--rows", required=True, type=Path)
    parser.add_argument("--per-book", type=int, default=40)
    parser.add_argument("epubs", nargs="+", type=Path)
    arguments = parser.parse_args()
    arguments.rows.parent.mkdir(parents=True, exist_ok=True)
    with arguments.rows.open("w") as out:
        for epub in arguments.epubs:
            work = arguments.scratch / epub.stem
            shutil.rmtree(work, ignore_errors=True)
            work.mkdir(parents=True)
            try:
                index = read_index(epub)
                names = sorted((n for n in index if n.endswith(".png") and index[n]["kind"] != "unreferenced"),
                               key=lambda n: int(n.split("-")[1].split(".")[0]))
                if len(names) > arguments.per_book:
                    step = len(names) / arguments.per_book
                    names = [names[int(i * step)] for i in range(arguments.per_book)]
                with zipfile.ZipFile(epub) as z:
                    members = {i.filename.split("/")[-1]: i.filename for i in z.infolist()}
                    for name in names:
                        (work / name).write_bytes(z.read(members[name]))
                for name in names:
                    kind = index[name]["kind"]
                    role = "page" if kind == "reference" else "region"
                    swift = json.loads(subprocess.run(
                        [str(arguments.features), role, "1", str(work / name)],
                        capture_output=True, check=True, text=True).stdout.splitlines()[0])
                    rgb = np.asarray(Image.open(work / name).convert("RGB"))
                    f = classifier.features(rgb)
                    evidence = {"kind": kind, "pageHasText": False, "pageImageFilters": ["image"]}
                    klass, _ = classifier.classify(f, evidence)
                    row = {"book": epub.stem, "asset": name, "kind": kind,
                           "pixels": int(rgb.shape[0] * rgb.shape[1]),
                           "python": {k: f[k] for k in FEATURES} | {
                               "backgroundColour": f["backgroundColour"], "class": klass,
                               "lossy": lossy_is_safe(klass, f, kind)},
                           "swift": {k: swift[k] for k in FEATURES} | {
                               "backgroundColour": swift["backgroundColour"], "class": swift["class"],
                               "lossy": swift["lossy"], "seconds": swift["seconds"]}}
                    out.write(json.dumps(row) + "\n")
            finally:
                shutil.rmtree(work, ignore_errors=True)

    rows = [json.loads(line) for line in arguments.rows.open()]
    same_class = sum(r["python"]["class"] == r["swift"]["class"] for r in rows)
    same_lossy = sum(r["python"]["lossy"] == r["swift"]["lossy"] for r in rows)
    same_ground = sum(r["python"]["backgroundColour"] == r["swift"]["backgroundColour"] for r in rows)
    print(f"{len(rows)} images from {len(arguments.epubs)} books: class agrees on {same_class}, "
          f"lossy verdict on {same_lossy}, modal colour on {same_ground}")
    for key in FEATURES:
        worst = max(abs(r["python"][key] - r["swift"][key]) for r in rows)
        print(f"  {key}: largest absolute difference {worst:.3g}")
    for r in rows:
        if r["python"]["class"] != r["swift"]["class"] or r["python"]["lossy"] != r["swift"]["lossy"]:
            print("  DISAGREES", r["book"], r["asset"], r["python"]["class"], r["swift"]["class"])


if __name__ == "__main__":
    main()
