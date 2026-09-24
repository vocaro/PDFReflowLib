#!/usr/bin/env python3
"""Measure the two-page #44 source against a baseline EPUB without changing either."""

import collections
import hashlib
import json
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

SOURCE_SHA256 = "387b3e178eb50b4990df9396728623781950dfc589f956250efc509bb1c417fa"
XHTML = "{http://www.w3.org/1999/xhtml}"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def japanese(text):
    return "".join(char for char in text if "\u3040" <= char <= "\u30ff" or "\u3400" <= char <= "\u9fff")


def column(block, page):
    x0, y0, x1, y1 = (float(number) for number in block.attrib["bbox"].split())
    text = "".join(line.attrib["text"] for line in block.findall("line"))
    # This source's title, author, folios, arrow and URL are not prose columns.
    body = (page == 1 and 40 < x0 < 230 and len(text) >= 15) or (
        page == 2 and 149 < x0 < 377 and len(text) >= 8
    )
    return body, {"xMin": round(x0, 3), "yMin": round(y0, 3),
                  "xMax": round(x1, 3), "yMax": round(y1, 3),
                  "characters": len(text), "opening": text[:16], "closing": text[-12:],
                  "textSHA256": hashlib.sha256(text.encode()).hexdigest()}, text


def main(source, epub):
    if digest(source) != SOURCE_SHA256:
        raise SystemExit("Source PDF SHA-256 does not match the reviewed Overleaf download")
    with tempfile.TemporaryDirectory() as scratch:
        xml = Path(scratch) / "source.xml"
        subprocess.run(["mutool", "draw", "-F", "stext", "-o", str(xml), str(source)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        pages = ET.parse(xml).getroot().findall("page")
    if len(pages) != 2:
        raise SystemExit("Expected the two-page source PDF")
    source_pages = []
    all_source = ""
    source_body = ""
    for number, page in enumerate(pages, 1):
        columns = []
        for block in page.findall("block"):
            is_body, evidence, text = column(block, number)
            all_source += text
            if is_body:
                columns.append((evidence["xMin"], evidence, text))
        columns.sort(key=lambda entry: entry[0], reverse=True)
        source_body += "".join(entry[2] for entry in columns)
        source_pages.append({"page": number, "bodyColumnCount": len(columns),
                             "bodyColumnsRightToLeft": [entry[1] for entry in columns],
                             "bodyOpening": "".join(entry[2] for entry in columns)[:48]})

    with zipfile.ZipFile(epub) as archive:
        chapter = ET.fromstring(archive.read("EPUB/chapter-1.xhtml"))
    body = chapter.find(XHTML + "body")
    output_pages = []
    output_text = ""
    for element in body:
        tag = element.tag.removeprefix(XHTML)
        if tag == "span" and element.attrib.get("role") == "doc-pagebreak":
            output_pages.append({"page": len(output_pages) + 1, "blocks": []})
            continue
        text = "".join(element.itertext()).strip()
        output_text += text
        if text:
            output_pages[-1]["blocks"].append({"tag": tag, "text": text[:80]})
    if len(output_pages) != 2:
        raise SystemExit("Expected two pagebreaks in the EPUB chapter")

    source_chars = japanese(source_body)
    output_chars = japanese(output_text)
    all_source_chars = japanese(all_source)
    source_grams = collections.Counter(source_chars[i:i + 3] for i in range(len(source_chars) - 2))
    output_grams = collections.Counter(output_chars[i:i + 3] for i in range(len(output_chars) - 2))
    source_multiset = collections.Counter(all_source_chars)
    output_multiset = collections.Counter(output_chars)
    result = {
        "schemaVersion": 1,
        "source": {"sha256": digest(source), "bytes": source.stat().st_size, "pages": 2,
                   "url": "https://www.overleaf.com/latex/examples/ri-ben-yu-zong-shu-kitenpureto-slash-japanese-tategaki-templete/wgpxjxbbbhyh",
                   "licenseListedByHost": "Creative Commons CC BY 4.0"},
        "baselineEPUB": {"sha256": digest(epub), "bytes": epub.stat().st_size,
                         "pages": [{"page": page["page"], "blockCount": len(page["blocks"]),
                                    "firstBlocks": page["blocks"][:6],
                                    "headings": [dict(index=index, text=block["text"])
                                                 for index, block in enumerate(page["blocks"])
                                                 if block["tag"].startswith("h")]}
                                   for page in output_pages],
                         "imageCount": sum(block["tag"] == "img" for page in output_pages for block in page["blocks"])},
        "sourcePages": source_pages,
        "orderDiagnostic": {"sourceBodyJapaneseCharacters": len(source_chars),
                            "epubJapaneseCharacters": len(output_chars),
                            "allSourceJapaneseCharacters": len(all_source_chars),
                            "sameJapaneseCharacterMultiset": source_multiset == output_multiset,
                            "sourceBodyTrigrams": sum(source_grams.values()),
                            "trigramsAlsoInEPUB": sum((source_grams & output_grams).values()),
                            "sourceBodyOpening": source_chars[:48], "epubOpening": output_chars[:48]},
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: measure.py SOURCE.pdf BASELINE.epub")
    main(Path(sys.argv[1]), Path(sys.argv[2]))
