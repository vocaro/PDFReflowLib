"""Retain the rejected experiment, including differences that prevent an identity claim."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from check_corpus_content import read_pages

parser = argparse.ArgumentParser()
for name in ("before", "after", "capture", "source_output", "output"):
    parser.add_argument("--" + name.replace("_", "-"), type=Path, required=True)
parser.add_argument("--control", action="append", default=[], help="Retain NAME=directory repeat/clean-build controls")
parser.add_argument("--logs", type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
args.source_output.mkdir(parents=True, exist_ok=True)


def save(name, value):
    data = (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()
    if name.endswith(".gz"):
        data = gzip.compress(data, mtime=0)
    (args.output / name).write_bytes(data)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def letters(text):
    # The established join policy may remove spaces and line-ending hard/soft hyphens.
    return re.sub(r"[\s\-\u00ad]", "", text)


def images(path):
    with zipfile.ZipFile(path) as archive:
        return {n: hashlib.sha256(archive.read(n)).hexdigest()
                for n in archive.namelist() if n.startswith("EPUB/images/")}


summary = json.loads((args.after / "summary.json").read_text())
assert summary["passed"] and len(summary["results"]) == 8 and not summary["notRun"]
rows, changes, sources = [], {}, {}
for candidate in sorted(args.after.glob("*/*.epub")):
    case = candidate.parent.name
    baseline = args.before / case / candidate.name
    left, lm = read_pages(baseline)
    right, rm = read_pages(candidate)
    assert lm == rm
    li, ri = images(baseline), images(candidate)
    assert li.keys() == ri.keys(), (case, "image inventory")
    changed_images = [name for name in li if li[name] != ri[name]]
    changed = []
    for page in left:
        before, after = left[page], right[page]
        if before == after:
            continue
        if case != "gpo-911-2004":
            changed.append(page)
            changes[f"{case}/{page}"] = {"before": before, "after": after}
            continue
        assert letters(before["text"]) == letters(after["text"]), (case, page, "text or order")
        assert before["headings"] == after["headings"] and before["images"] == after["images"]
        assert [(s["tag"], s["text"]) for s in before["scripts"]] == [(s["tag"], s["text"]) for s in after["scripts"]]
        source_path = args.source_output / f"911-{page}-layout.json"
        with (args.source_output / f"911-{page}-capture.log").open("wb") as log:
            subprocess.run([str(args.capture), case, str(page), str(source_path)],
                           cwd=ROOT, stdout=log, stderr=log, check=True)
        source = json.loads(source_path.read_text())
        assert source["sourceSHA256"] == "657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b"
        assert any("NOTES TO CHAPTER" in line["text"] for line in source["lines"])
        checked, ownership_failures = [], []
        for paragraph in after["paragraphs"]:
            marker = re.match(r"^([1-9][0-9]{0,3})\.", paragraph)
            if not marker:
                continue
            number = int(marker[1])
            starts = [i for i, line in enumerate(source["lines"]) if line["text"].startswith(f"{number}.")]
            if len(starts) != 1:
                ownership_failures.append({"number": number, "reason": "ambiguous source number", "matches": starts})
                continue
            start = starts[0]
            end = next((i for i in range(start + 1, len(source["lines"]))
                        if source["lines"][i]["text"].startswith(f"{number + 1}.")), len(source["lines"]))
            native = " ".join(line["text"] for line in source["lines"][start:end])
            if letters(paragraph) != letters(native):
                ownership_failures.append({"number": number, "reason": "source lines differ", "source": native, "paragraph": paragraph})
                continue
            checked.append(number)
        changed.append(page)
        changes[f"{case}/{page}"] = {"checkedNoteNumbers": checked, "ownershipCheckFailures": ownership_failures,
                                     "before": before, "after": after}
        sources[str(page)] = source
    folder = args.output / "candidate" / case
    folder.mkdir(parents=True, exist_ok=True)
    for name in ("result.json", "conversion-report.json", "content-assessment.json", "progress.log", "memory-samples.json", "epubcheck.log"):
        (folder / (name + ".gz")).write_bytes(gzip.compress((candidate.parent / name).read_bytes(), mtime=0))
    baseline_folder = args.output / "baseline" / case
    baseline_folder.mkdir(parents=True, exist_ok=True)
    for name in ("result.json", "conversion-report.json", "content-assessment.json", "progress.log", "memory-samples.json", "epubcheck.log"):
        (baseline_folder / (name + ".gz")).write_bytes(gzip.compress((baseline.parent / name).read_bytes(), mtime=0))
    rows.append({"case": case, "pages": len(left), "changedPages": changed,
                 "unchangedImageCount": len(li) - len(changed_images), "changedImageNames": changed_images,
                 "sourcePageOrderUnchanged": True,
                 "beforeEPUBSHA256": digest(baseline), "afterEPUBSHA256": digest(candidate)})
save("comparison-summary.json", rows)
save("changed-pages.json.gz", changes)
save("source-layouts.json.gz", sources)
save("corpus-summary.json", summary)
control_rows = []
for item in args.control:
    label, directory = item.split("=", 1)
    assert re.fullmatch(r"[a-z-]+", label)
    for path in sorted(Path(directory).glob("*/*.epub")):
        case = path.parent.name
        original = args.before / case / path.name
        candidate = args.after / case / path.name
        baseline_pages, _ = read_pages(original)
        control_pages, _ = read_pages(path)
        candidate_pages, _ = read_pages(candidate)
        bi, ci, ni = images(original), images(path), images(candidate)
        control_rows.append({"control": label, "case": case,
            "changedPagesFromBaseline": [n for n in baseline_pages if baseline_pages[n] != control_pages[n]],
            "changedImagesFromBaseline": [n for n in bi if bi[n] != ci[n]],
            "changedPagesFromCandidate": [n for n in candidate_pages if candidate_pages[n] != control_pages[n]],
            "changedImagesFromCandidate": [n for n in ni if ni[n] != ci[n]]})
        folder = args.output / label / case
        folder.mkdir(parents=True, exist_ok=True)
        for name in ("result.json", "conversion-report.json", "content-assessment.json", "progress.log", "memory-samples.json", "epubcheck.log"):
            (folder / (name + ".gz")).write_bytes(gzip.compress((path.parent / name).read_bytes(), mtime=0))
save("control-comparison.json", control_rows)
if args.logs:
    for name in ("before-tests.log", "before-content.json", "final-gate.log", "ios-tests.log",
                 "retained-tests.log", "retained-python.log", "retained-ios-tests.log", "retained-content.json"):
        source = args.logs / ("endnotes-" + name)
        if source.exists():
            (args.output / (name + ".gz")).write_bytes(gzip.compress(source.read_bytes(), mtime=0))
save("identity.json", {"baselineRevision": "0eba8d4", "collectorSHA256": digest(Path(__file__)),
    "rejectedRefinementPatchSHA256": digest(args.output / "rejected-runtime.patch"),
    "rejectedTestsSHA256": digest(args.output / "rejected-tests.swift"),
    "captureToolSourceSHA256": digest(ROOT / "tools/capture-layout-fixture.swift"),
    "retainedContractSHA256": digest(ROOT / "corpus/regressions.json"),
    "note": "Candidate receipts predate the runtime revert; the rejected-runtime patch is the subsequent extraction-untouched refinement."})
print(json.dumps(rows, indent=2))
