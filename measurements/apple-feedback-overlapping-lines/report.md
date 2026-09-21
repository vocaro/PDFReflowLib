# PDFKit returns one printed line as four overlapping lines with duplicated characters

Suggested area: macOS / PDFKit. Type: Incorrect/Unexpected Behavior.
Drafted 2026-09-20; not yet filed.

## Summary

`PDFSelection.selectionsByLine()` returns, for one printed row, four separate line selections that
all report the *same* bounding rectangle. One holds the row's text, two hold a single duplicated
character each, and the fourth holds that character again followed by a newline and the *next*
row's text. A caller laying out by line rectangle cannot order or de-duplicate these, because
their geometry is identical.

## Environment

macOS 27.0 (26A428), arm64, Xcode 27.0.

## Steps to reproduce

1. Download *Record Linkage and Privacy* (Census Bureau RRS2002-01, public domain), SHA-256
   `0f97380ae4308581bd70013b7317faafd7c217654236bd31d1448f26eae56905`, from
   <https://www.census.gov/library/working-papers/2002/adrm/rrs2002-01.html>.
2. Build the attached probe: `xcrun swiftc -O probe.swift -o pdfkit-text-probe`
3. `./pdfkit-text-probe rrs2002-01.pdf 16 lines`

## Expected

One printed row yields one line selection, or, where PDFKit splits a row, line selections with
distinct rectangles covering distinct parts of it.

## Actual

Lines 26 to 29 of page 16, verbatim from the probe (the document's text layer is also encoded
with a custom `Differences` map that shifts every letter, which is why the words read as they do;
that is not the subject of this report and does not affect the geometry):

```
line 26	x=134.81 y=399.27 w=345.92 h=23.56	pdvnlqj phwkrgv1 Wkh uvw lv wkdw wkh vxlwdeoh whvw ohv duh qhhghg1 Wkh whvw
line 27	x=134.81 y=399.27 w=345.92 h=23.56	w
line 28	x=134.81 y=399.27 w=345.92 h=23.56	w
line 29	x=134.81 y=399.27 w=345.92 h=23.56	w\nohv vkrxog kdyh yduldeohv lq zklfk wkh glvwulexwlrqv duh uhsuhvhqwdwlyh ri dfwxdo
```

All four rectangles are identical to the hundredth of a point. The character `w` appears as a
whole line three times, and line 29 carries both that character and the following printed row,
separated by a newline, so the same rectangle is claimed by two printed rows at once.

Every other line on the page has a distinct rectangle 11 to 12 points high; these four are 23.56
points, which is two rows.

Attachment: `probe.swift`, a single file using only Foundation, AppKit and PDFKit, which prints
each line selection's index, bounds and string.
