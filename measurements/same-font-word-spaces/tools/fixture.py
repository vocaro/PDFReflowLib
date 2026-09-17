#!/usr/bin/env python3
"""usage: fixture.py <pdf> <native-lines.json> <out.json> <page>...

Writes the #119 source fixture: for each page, its font resources (Subtype, BaseFont, FirstChar,
Widths and the decoded ToUnicode stream), its ExtGState resources (their key/value pairs), the
decoded page content stream, and PDFKit's native lines with their rectangles (native-lines.swift).
Streams are read with `mutool show -b` from the checksum-pinned original."""
import hashlib
import json
import re
import subprocess
import sys

MUTOOL = "/opt/homebrew/bin/mutool"


def show(pdf, *args):
    """`mutool show [options] <pdf> <path>`: the last argument is the object path."""
    options, path = args[:-1], args[-1]
    return subprocess.run([MUTOOL, "show", *options, pdf, path], capture_output=True, check=True).stdout.decode("latin1")


def references(text):
    return dict(re.findall(r"/(\S+) (\d+) 0 R", text))


pdf, native_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
pages = sys.argv[4:]
native = json.load(open(native_path, encoding="utf-8"))
result = {
    "caseID": "gpo-911-2004",
    "sourceTitle": "The 9/11 Commission Report",
    "sourceURL": "https://www.govinfo.gov/content/pkg/GPO-911REPORT/pdf/GPO-911REPORT.pdf",
    "sourceSHA256": hashlib.sha256(open(pdf, "rb").read()).hexdigest(),
    "rightsBasis": "Official U.S. Government commission report, retained as external development material. "
                   "Source PDF is not bundled or relicensed under MIT.",
    "provenance": "Unmodified page font dictionaries (Subtype, BaseFont, FirstChar, Widths, decoded ToUnicode "
                  "streams), ExtGState entries and complete decoded page content streams, read with mutool show "
                  "from the checksum-pinned original; Encoding Differences and font programs are excluded. Native "
                  "lines are PDFKit selectionsByLine strings and bounds on macOS 27.0.",
    "pages": [],
}
for page in pages:
    fonts = []
    for name, number in sorted(references(show(pdf, f"pages/{page}/Resources/Font")).items()):
        text = show(pdf, number)
        widths = re.search(r"/Widths\s*\[([^\]]*)\]", text)
        first = re.search(r"/FirstChar (\d+)", text)
        unicode = re.search(r"/ToUnicode (\d+) 0 R", text)
        fonts.append({
            "resourceName": name,
            "sourceObject": number,
            "subtype": re.search(r"/Subtype /(\S+)", text).group(1),
            "baseFont": re.search(r"/BaseFont /(\S+)", text).group(1),
            "firstChar": int(first.group(1)) if first else None,
            "widths": [float(x) for x in widths.group(1).split()] if widths else None,
            "toUnicode": show(pdf, "-b", unicode.group(1)) if unicode else None,
        })
    states = {}
    for name, number in sorted(references(show(pdf, f"pages/{page}/Resources/ExtGState")).items()):
        body = show(pdf, number)
        states[name] = re.sub(r"\s+", " ", body[body.index("<<"):body.rindex(">>") + 2])
    result["pages"].append({
        "page": int(page),
        "fonts": fonts,
        "extGStates": states,
        # Bytes above 127 occur only inside string operands here; octal escapes keep them one byte
        # when the tests write the stream as UTF-8.
        "operators": re.sub(r"[\x80-\xff]", lambda m: "\\%03o" % ord(m.group(0)), show(pdf, "-b", f"pages/{page}/Contents")),
        "lines": native[page],
    })
with open(out, "w", encoding="utf-8") as handle:
    json.dump(result, handle, ensure_ascii=False, indent=1, sort_keys=True)
    handle.write("\n")
