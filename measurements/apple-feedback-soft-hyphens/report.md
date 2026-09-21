# PDFKit omits soft hyphens (U+00AD) from extracted text

Suggested area: macOS / PDFKit. Type: Incorrect/Unexpected Behavior.
Drafted 2026-09-20; not yet filed.

## Summary

A page whose content stream draws a soft hyphen (U+00AD) at a line end returns text from PDFKit
with no hyphen character of any kind at that position. The two halves of the broken word arrive
adjacent with nothing between them, so a consumer joining the lines cannot tell a hyphenated
break from two separate words, and produces `PEO PLE` for a page that prints `PEO-` / `PLE,`.

Poppler reads the same page and returns U+00AD at each of those positions, so the character is in
the file and is mapped.

## Environment

macOS 27.0 (26A428), arm64, Xcode 27.0.

## Steps to reproduce

1. Download *Our Flag* (House Document 108-97, public domain, U.S. Government Publishing Office),
   SHA-256 `a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8`, from
   <https://www.govinfo.gov/app/details/CDOC-108hdoc97>.
2. Build the attached probe: `xcrun swiftc -O probe.swift -o pdfkit-text-probe`
3. `./pdfkit-text-probe CDOC-108hdoc97.pdf 52 chars | grep -c 'U+00AD'`
4. Compare with `pdftotext -f 52 -l 52 CDOC-108hdoc97.pdf -` (Poppler), or open page 52 and look
   at the hyphens at the ends of lines 2 and 6.

## Expected

The extracted text carries the soft hyphen the page draws, as it carries every other character,
so that a caller can tell a line-end break from a word boundary.

## Actual

Page 52 of that document, which prints three soft-hyphenated line breaks:

| Reader | U+00AD characters on page 52 |
| --- | ---: |
| Poppler 25.09 (`pdftotext`) | 3 |
| PDFKit (`PDFPage.string`) | 0 |

The three lines Poppler returns are `…BY THE PEO\u{00AD}`, `…TO SUPPORT ITS CONSTITU\u{00AD}` and
`…was then created for him which he occu\u{00AD}`. PDFKit returns the same three lines ending
`…BY THE PEO`, `…TO SUPPORT ITS CONSTITU` and `…which he occu`, with the next line following as
a separate line beginning `PLE,`, `TION`, `pied`.

No other character is lost: the lines agree with Poppler's in every other position.

## Notes

`PDFSelection.string`, `PDFPage.string` and `PDFPage.attributedString` all omit it. A hard hyphen
(U+002D) at a line end is returned normally on other pages of the same document, so this is
specific to the soft hyphen.

Attachment: `probe.swift`, a single file using only Foundation, AppKit and PDFKit, which prints
every character PDFKit returns for a page with its scalar value and `characterBounds`.
