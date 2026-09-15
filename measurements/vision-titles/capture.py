#!/usr/bin/env python3
"""Recreate issue #24 captures from the pinned local corpus; performs no downloads."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from analyze_vision_titles import analyze


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="New output directory")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    captures = output / "captures"
    captures.mkdir()
    sources = ["Sources/PDFReflowLib/PageRasterizer.swift", "Sources/PDFReflowLib/ConversionTypes.swift",
               "Sources/PDFReflowLib/DocumentModel.swift", "Sources/PDFReflowLib/ReflowDocument.swift",
               "tools/probe-vision-titles.swift"]
    executable = output / "probe-vision-titles"
    commands = [["xcrun", "swiftc", "-module-cache-path", str(output / "module-cache"),
                 "-parse-as-library", *sources, "-o", str(executable)]]
    review_path = ROOT / "measurements/vision-titles/review.json"
    for review in json.loads(review_path.read_text())["pages"]:
        commands.append([str(executable), review["caseID"], str(review["page"]),
                         str(captures / review["capture"])])
    with (output / "capture.log").open("w") as log:
        for command in commands:
            print(" ".join(command), flush=True)
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    report = analyze(captures, review_path)
    (output / "results.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    receipt = {"commands": commands,
               "sourceHashes": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
                                for p in sources + ["measurements/vision-titles/review.json",
                                                    "tools/analyze_vision_titles.py"]},
               "os": subprocess.check_output(["sw_vers"], text=True),
               "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True)}
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report["summary"], indent=2))


if __name__ == "__main__":
    main()
