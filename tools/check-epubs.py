#!/usr/bin/env python3
"""Convert the committed corpus and check its EPUB contracts independently of Swift code.

Uses only the Python standard library. Pass --epubcheck for full EPUB 3.3 conformance validation.
Output directories must be new, so evidence cannot be silently overwritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.parse
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests/PDFReflowLibTests/fixtures"
NS = {"opf": "http://www.idpf.org/2007/opf", "html": "http://www.w3.org/1999/xhtml"}
EXPECTED = {
    "prose": (3, 3, ["reliable conversion", "remains well-known", "losing the original sentence"]),
    "columns": (1, 1, ["LEFT FIRST", "LEFT LAST", "RIGHT FIRST", "RIGHT LAST"]),
    "graphics": (1, 1, ["Text before the illustrated region", "Text after the table"]),
    "lists-code": (1, 1, ["1. Keep the first item.", "2. Keep the second item.", "print(value)"]),
    "rotated": (1, 0, []),
    "scanned": (1, 1, ["clear scanned paragraph", "reflowable text"]),
}


XHTML = '{http://www.w3.org/1999/xhtml}'
HEADINGS = {XHTML + 'h' + str(level) for level in range(1, 7)}
# The writer keeps a heading run of at most a tenth of the body target with its following content.
KEPT_HEADING_BYTES = 6_000


def is_page_boundary(node):
    return (node.tag == XHTML + 'span'
            and 'pagebreak' in node.get('{http://www.idpf.org/2007/ops}type', '').split())


_MARKER = rb'<span epub:type="pagebreak"[^>]*/>'
# A heading's content cannot cross its own closing tag, so a match never spans other blocks.
_HEADING = rb'<h[1-6]\b[^>]*>(?:(?!</h[1-6]>).)*</h[1-6]>'
_LEADING_HEADINGS = re.compile(rb'(?:\s*' + _MARKER + rb')*((?:\s*(?:' + _HEADING + rb'|' + _MARKER + rb'))*)', re.S)
_TRAILING_RUN = re.compile(rb'(?:(?:' + _HEADING + rb'|' + _MARKER + rb')\s*)+\Z', re.S)


def body_bytes(data):
    """The exact emitted UTF-8 markup between the body tags."""
    assert data.count(b'<body>') == 1 and data.count(b'</body>') == 1
    return data.split(b'<body>', 1)[1].split(b'</body>', 1)[0]


def trailing_heading_bytes(encoded):
    """Serialized bytes of the headings (and markers among them) ending a body, or 0 without a heading."""
    match = _TRAILING_RUN.search(encoded)
    if not match or not re.search(_HEADING, match.group(0), re.S):
        return 0
    return len(match.group(0).rstrip())


def check_spine_document(data):
    """Check the converter's 60,000-byte body target, allowing one indivisible large block.

    Short headings the writer keeps with that block may precede it.
    """
    tree = ET.fromstring(data)
    body = tree.find('html:body', NS)
    assert body is not None, "missing spine body"
    # Count the exact emitted UTF-8/escaped markup, not ElementTree's reserialization.
    encoded = body_bytes(data)
    size = len(encoded)
    if size > 60_000:
        markers = [node for node in body if is_page_boundary(node)]
        content = [node for node in body if not is_page_boundary(node)]
        headings = 0
        while headings < len(content) - 1 and content[headings].tag in HEADINGS:
            headings += 1
        kept = _LEADING_HEADINGS.match(encoded).group(1).strip()
        assert headings == 0 or len(kept) <= KEPT_HEADING_BYTES, "spine body exceeds target with multiple blocks"
        content = content[headings:]
        assert len(content) == 1, "spine body exceeds target with multiple blocks"
        assert len(markers) <= 1, "oversized block includes unrelated page markers"
        assert content[0].tag in {'{http://www.w3.org/1999/xhtml}' + tag
                                  for tag in ('p', 'h2', 'pre', 'figure', 'table')}, "unexpected oversized block"
        assert not (body.text or '').strip() and all(not (n.tail or '').strip() for n in body), "unwrapped body text"
    return {'bodyBytes': size, 'oversizedAtomicBlock': size > 60_000}


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
        names_by_tree = {}
        for ref in opf.findall("opf:spine/opf:itemref", NS):
            name = "EPUB/" + manifest[ref.attrib["idref"]]["href"]
            check_spine_document(archive.read(name))
            chapters.append(documents[name])
            names_by_tree[id(documents[name])] = name
        for tree in chapters[:-1]:
            # A short heading must open the document holding its content, not end the previous one.
            kept = trailing_heading_bytes(body_bytes(archive.read(names_by_tree[id(tree)])))
            assert not 0 < kept <= KEPT_HEADING_BYTES, "spine document ends with a heading separated from its content"
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
