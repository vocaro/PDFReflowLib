"""Audit the bounded note repair against capability-compatible complete evaluations.

Run from the repository root after capturing baseline/candidate under
.build/numbered-notes-recheck with the same probe. Never rewrites historical evidence.
"""
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from check_corpus_content import check_evaluation, read_pages
from compare_conversion_runs import compare

WORK = ROOT / ".build/numbered-notes-recheck"
OUT = Path(__file__).resolve().parent
sources = json.loads(gzip.decompress((OUT.parent / "source-layouts.json.gz").read_bytes()))
manifest = {c["id"]: c for c in json.loads((ROOT / "corpus/manifest.json").read_text())["documents"]}
contracts = json.loads((ROOT / "corpus/regressions.json").read_text())["cases"]


def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def letters(value):
    return re.sub(r"[\s\-\u00ad]", "", value)


def number(line):
    match = re.match(r"^([1-9][0-9]{0,3})\.\s*[^\W\d_]", line["text"])
    return int(match[1]) if match else None


comparisons, assessments, ownership = [], [], []
for contract in contracts:
    case = contract["id"]
    baseline, candidate = [WORK / mode / case for mode in ("baseline", "candidate")]
    result = compare(baseline, candidate, allow_different_converters=True)
    assert not result.get("provenanceErrors"), result
    assert not result.get("inspectionError"), result
    assessment = check_evaluation(manifest[case], contract, candidate)
    assert assessment["passed"], assessment
    comparisons.append(result)
    assessments.append(assessment)
    if case != "gpo-911-2004":
        assert result["passed"], result
    else:
        assert not result["changedImages"] and result["pageMarkersEqual"], result
        assert not result["changedReportFields"], result
        left, _ = read_pages(baseline / (case + ".epub"))
        right, _ = read_pages(candidate / (case + ".epub"))
        assert result["changedPages"], "No note repair observed"
        for page in result["changedPages"]:
            before, after = left[page], right[page]
            assert letters(before["text"]) == letters(after["text"]), (page, "text/order")
            assert before["headings"] == after["headings"], (page, "headings")
            assert before["images"] == after["images"], (page, "images")
            assert [(s["tag"], s["text"]) for s in before["scripts"]] == [
                (s["tag"], s["text"]) for s in after["scripts"]], (page, "scripts")
            source = sources[str(page)]
            assert source["sourceSHA256"] == manifest[case]["sha256"]
            lines = source["lines"]
            assert any("NOTES TO CHAPTER" in line["text"] for line in lines)
            first = next(i for i, line in enumerate(lines) if number(line) is not None)
            x, size = lines[first]["rect"][0], lines[first]["fontSize"]
            starts = [i for i in range(first, len(lines)) if number(lines[i]) is not None
                      and abs(lines[i]["rect"][0] - x) <= size * 0.25]
            numbers = [number(lines[i]) for i in starts]
            assert len(numbers) >= 3 and numbers == list(range(numbers[0], numbers[0] + len(numbers)))
            for offset, start in enumerate(starts):
                end = starts[offset + 1] if offset + 1 < len(starts) else len(lines)
                native = " ".join(line["text"] for line in lines[start:end])
                matches = [p for p in after["paragraphs"] if p.startswith(str(numbers[offset]) + ".")]
                assert len(matches) == 1 and letters(matches[0]) == letters(native), (page, numbers[offset])
            ownership.append({"page": page, "checkedNoteNumbers": numbers})
    for mode, directory in (("baseline", baseline), ("candidate", candidate)):
        target = OUT / mode / case
        target.mkdir(parents=True, exist_ok=True)
        for name in ("result.json", "conversion-report.json", "environment-probe.json",
                     "environment-probe.log", "content-assessment.json", "progress.log",
                     "memory-samples.json", "epubcheck.log"):
            (target / (name + ".gz")).write_bytes(gzip.compress((directory / name).read_bytes(), mtime=0))
    (OUT / "candidate" / case / "final-content-assessment.json.gz").write_bytes(
        gzip.compress((json.dumps(assessment, indent=2) + "\n").encode(), mtime=0))

save("comparisons.json", comparisons)
save("source-ownership.json", ownership)
save("content-assessments.json", assessments)
save("summary.json", {
    "passed": True, "cases": len(comparisons),
    "changedNotePages": len(ownership),
    "sourceMatchedPageLocalNoteParagraphs": sum(len(row["checkedNoteNumbers"]) for row in ownership),
    "contentChecks": sum(row["contentChecks"] for row in assessments),
    "scope": "All eight complete conversion/resource/EPUB/capability receipts and current content contracts pass; seven controls are identical, and 9/11 differences pass the source-line audit.",
    "knownUnsupportedFullConversions": json.loads((ROOT / "corpus/regressions.json").read_text())["excludedFullConversions"]
})
for name in ("before-tests.log", "before-content.json", "focused-tests.log", "fast-gate.log", "ios-tests.log", "structure-memory.log"):
    path = WORK / name
    if path.exists():
        (OUT / (name + ".gz")).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
save("identity.json", {
    "baselineRevision": "b82dbe7",
    "baselineConverterSHA256": comparisons[0]["baselineConverterSHA256"],
    "candidateConverterSHA256": comparisons[0]["candidateConverterSHA256"],
    "collectorSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "files": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in [
        "Sources/PDFReflowLib/NumberedNoteDetector.swift", "Sources/PDFReflowLib/LayoutReconstructor.swift",
        "Sources/PDFReflowLib/PDFReflowLibPipeline.swift", "Tests/PDFReflowLibTests/NumberedNoteTests.swift",
        "Tests/PDFReflowLibTests/fixtures/911-532-layout.json", "corpus/regressions.json"]},
    "scope": "Same-page source-line ownership for admitted numbered paragraphs; no reference-to-note links or general cross-page/multi-paragraph identity."
})
print(json.dumps({"cases": len(comparisons), "changedNotePages": len(ownership),
                  "sourceMatchedNoteParagraphs": sum(len(row["checkedNoteNumbers"]) for row in ownership),
                  "contentChecks": sum(row["contentChecks"] for row in assessments)}, indent=2))
