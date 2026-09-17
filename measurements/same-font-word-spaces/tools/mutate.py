#!/usr/bin/env python3
"""usage: mutate.py <file> <name>  applies one named negative-control mutation to a source or test file in
place (restore it from a backup afterwards). Mutations:
  baseline-tests   remove the three #119 tests that call new API (for a run against the baseline reader)
  no-gate          read in-show word spaces without character or word spacing
  no-overhang      use the letter threshold before overhanging capitals and opening quotes
  no-letterspace   drop the letter-spacing guard
  no-math          drop the mathematical-letter guard
  no-trailing      stop skipping a trailing source space
  no-note          never restore a note reference
Exits 1 when the mutation's anchor text is not found."""
import re
import sys

path, name = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
edits = {
    "no-gate": [("if decodable, !unicode.isEmpty, spacing.0 != 0 || spacing.1 != 0 {", "if decodable, !unicode.isEmpty {")],
    "no-overhang": [("return gap >= (narrow ? overhangWordSpaceGap : wordSpaceGap)", "return gap >= wordSpaceGap")],
    "no-letterspace": [("if !spaced { item.wordSpaces.insert(boundary.offset) }", "_ = spaced; item.wordSpaces.insert(boundary.offset)")],
    "no-math": [("!mathematical(left), !mathematical(right), ", "")],
    "no-trailing": [("while i < source.count, j == extracted.count, whitespace(source[i]) { i += 1 }", "")],
    "no-note": [("if let previous, let end = previous.end, noteReference(previous, before: show, end: end) {",
                 "if false, let previous, let end = previous.end, noteReference(previous, before: show, end: end) {")],
}
if name == "baseline-tests":
    count = 0
    for test in ["sameFontWordSpaceSeparatesTheMeasuredGapModes", "tjAdjustmentsInJustifiedShowsRestoreWordSpacesAndLetterSpacingStaysJoined",
                 "noteReferenceBeforeACapitalRestoresItsWordSpaceOnly"]:
        pattern = re.compile(r"@Test func " + test + r"\(\).*?\n}\n", re.S)
        text, n = pattern.subn("", text)
        count += n
    if count != 3:
        sys.exit(1)
else:
    for old, new in edits[name]:
        if old not in text:
            sys.exit(1)
        text = text.replace(old, new)
open(path, "w", encoding="utf-8").write(text)
