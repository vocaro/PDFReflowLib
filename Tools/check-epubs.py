#!/usr/bin/env python3
"""Convert the committed corpus and check its EPUB contracts independently of Swift code.

Uses only the Python standard library. Pass --epubcheck for full EPUB 3.3 conformance validation.
Output directories must be new, so evidence cannot be silently overwritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
import urllib.parse
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests/PDFReflowLibTests/Fixtures"
NS = {"opf": "http://www.idpf.org/2007/opf", "html": "http://www.w3.org/1999/xhtml"}
EXPECTED = {
    "prose": (3, 3, ["reliable conversion", "remains well-known", "losing the original sentence"]),
    "columns": (1, 1, ["LEFT FIRST", "LEFT LAST", "RIGHT FIRST", "RIGHT LAST"]),
    "graphics": (1, 1, ["Text before the illustrated region", "Text after the table"]),
    "lists-code": (1, 1, ["1. Keep the first item.", "2. Keep the second item.", "print(value)"]),
    "rotated": (1, 0, []),
    "scanned": (1, 1, ["clear scanned paragraph", "reflowable text"]),
}


def check(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        assert len(set(names)) == len(names), "duplicate archive entries"
        first = archive.infolist()[0]
        assert first.filename == "mimetype" and first.compress_type == zipfile.ZIP_STORED
        assert archive.read("mimetype") == b"application/epub+zip"
        documents = {name: ET.fromstring(archive.read(name)) for name in names
                     if name.endswith((".xhtml", ".xml", ".opf"))}
        opf = documents["EPUB/package.opf"]
        assert opf.attrib["version"] == "3.0"
        manifest = {item.attrib["id"]: item.attrib for item in opf.findall("opf:manifest/opf:item", NS)}
        for item in manifest.values():
            assert "EPUB/" + item["href"] in names
        assert any(item.get("properties") == "nav" for item in manifest.values())
        chapters = []
        for ref in opf.findall("opf:spine/opf:itemref", NS):
            chapters.append(documents["EPUB/" + manifest[ref.attrib["idref"]]["href"]])
        ids = {}
        for name, tree in documents.items():
            found = [node.attrib["id"] for node in tree.iter() if "id" in node.attrib]
            assert len(found) == len(set(found)), f"duplicate ID in {name}"
            ids[name] = set(found)
        for name, tree in documents.items():
            for node in tree.iter():
                assert node.tag != "{http://www.w3.org/1999/xhtml}script"
                for attr in ["src", "href"]:
                    if attr not in node.attrib:
                        continue
                    link = urllib.parse.urlsplit(node.attrib[attr])
                    assert not link.scheme and not link.netloc, "unexpected external resource"
                    target = str(Path(name).parent / link.path) if link.path else name
                    assert target in names, f"missing reference {target}"
                    if link.fragment:
                        assert link.fragment in ids[target], f"missing fragment {link.fragment}"
        text = " ".join(" ".join(tree.itertext()) for tree in chapters)
        return " ".join(text.split())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--converter", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--epubcheck", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    manifest = json.loads((FIXTURES / "manifest.json").read_text())
    records = []
    for fixture in manifest["fixtures"]:
        source = FIXTURES / fixture["file"]
        assert hashlib.sha256(source.read_bytes()).hexdigest() == fixture["sha256"]
        assert source.stat().st_size == fixture["bytes"]
        output = args.output / (source.stem + ".epub")
        start = time.monotonic()
        result = subprocess.run([str(args.converter.resolve()), str(source), str(output)],
                                capture_output=True, text=True, check=True)
        report = json.loads(result.stdout)
        text = check(output)
        pages, reflowed, phrases = EXPECTED[source.stem]
        assert report["pageCount"] == pages
        assert report["reflowedPageCount"] == reflowed, (source.stem, report)
        for phrase in phrases:
            assert phrase in text, (source.stem, phrase)
        if source.stem == "columns":
            assert text.index("LEFT LAST") < text.index("RIGHT FIRST")
        if source.stem == "graphics":
            assert report["imageCount"] == 3, report
        checker = None
        if args.epubcheck:
            validated = subprocess.run([str(args.epubcheck), str(output)], capture_output=True, text=True)
            checker = validated.stdout + validated.stderr
            (args.output / (source.stem + "-epubcheck.txt")).write_text(checker)
            assert validated.returncode == 0, checker
        records.append({"fixture": fixture, "report": report,
                        "elapsedSeconds": time.monotonic() - start,
                        "outputBytes": output.stat().st_size,
                        "epubcheck": "passed" if checker is not None else "not run"})
        print(f"PASS {source.name}", flush=True)
    (args.output / "results.json").write_text(json.dumps({"cases": records}, indent=2) + "\n")
    print(f"PASS {len(records)} fixture conversions; XML, spine, assets, anchors, source text and order")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, subprocess.CalledProcessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1) from error
