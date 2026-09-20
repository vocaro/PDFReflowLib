# PDFKit line rectangles for lines containing radicals are two to four times the line's height

Suggested area: macOS / PDFKit. Type: Incorrect/Unexpected Behavior.
Drafted 2026-09-20; not yet filed.

## Summary

On a mathematics textbook page set in TeX, `PDFSelection.selectionsByLine()` returns line
rectangles whose heights follow the tallest glyph on the line rather than the line's own extent.
A prose line carrying one inline radical is reported 20.46 points high where its neighbours are
11.98, so its rectangle overlaps the line below it; display lines reach 44.35 points. A caller
ordering or grouping lines by rectangle sees lines that overlap and cannot tell which printed row
a rectangle belongs to.

## Environment

macOS 27.0 (26A428), arm64, Xcode 27.0.

## Steps to reproduce

1. Download *Beginning and Intermediate Algebra* by Tyler Wallace (CC BY 3.0), SHA-256
   `856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678`, from
   <http://wallace.ccfaculty.org/book/book.html>.
2. Build the attached probe: `xcrun swiftc -O probe.swift -o pdfkit-text-probe`
3. `./pdfkit-text-probe Beginning_and_Intermediate_Algebra.pdf 290 lines`

## Expected

A line rectangle covers the line, so that consecutive lines of one paragraph do not overlap.

## Actual

Page 290, with the paragraph's own lines and the ones carrying radicals side by side:

| Line | Rect | Height | Text |
| ---: | --- | ---: | --- |
| 1 | y=695.98 | 11.98 | `The previous example could have been done in fewer steps…` |
| 2 | y=672.74 | **20.46** | `72= 36· 2, but often the time it takes to discover…` |
| 3 | y=666.58 | 11.98 | `than it would take to simplify in several steps.` |
| 18 | y=424.67 | **44.35** | `√ · y6` |

Line 2 is one line of running prose with a single inline radical. Its rectangle spans
y=672.74–693.20 and line 3's spans y=666.58–678.56, so the two overlap by 6.62 points although
they are consecutive printed rows 6 points apart.

The same shape appears on pages 293, 316 and 410 of the document.

Attachment: `probe.swift`, a single file using only Foundation, AppKit and PDFKit, which prints
each line selection's index, bounds and string.
