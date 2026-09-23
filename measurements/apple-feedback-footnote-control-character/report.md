# PDFKit returns U+0007 (BEL) for a drawn footnote marker glyph

Suggested area: macOS / PDFKit. Type: Incorrect/Unexpected Behavior.
Drafted 2026-09-20; filed as FB24908772 on 2026-09-23.

## Summary

On a page that prints four numbered footnotes, PDFKit's extracted text carries U+0007 (BEL)
directly after each note's number, where the page draws an ordinary glyph. The character is not a
placeholder for something unrenderable: `characterBounds(at:)` returns a real, plausible box for
it, about 2 × 4 points at the position the glyph occupies. A control character in the middle of
prose stops any consumer that treats the text as text.

## Environment

macOS 27.0 (26A428), arm64, Xcode 27.0.

## Steps to reproduce

1. Download the *Dietary Guidelines for Americans, 2025–2030* executive summary (public domain,
   U.S. Departments of Agriculture and Health and Human Services), SHA-256
   `c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472`, from
   <https://realfood.gov/>.
2. Build the attached probe: `xcrun swiftc -O probe.swift -o pdfkit-text-probe`
3. `./pdfkit-text-probe DGA.pdf 2 chars | grep -B2 -A2 'U+0007'`

## Expected

The extracted text holds the character the page draws, or, if PDFKit cannot map the glyph, U+FFFD
or nothing — not a C0 control character with a glyph box.

## Actual

Page 2 contains exactly four U+0007, one per footnote, and pages 1, 3 and 4 contain none. Each
sits between the note's number and the first letter of its text:

```
char 2979	U+0031	1	x=147.91 y=89.56 w=2.90 h=4.56
char 2980	U+0020	 	x=150.81 y=89.56 w=2.79 h=3.29
char 2981	U+0007	\u{0007}	x=153.59 y=89.56 w=1.95 h=4.00
char 2982	U+0068	h	x=155.54 y=89.56 w=2.73 h=3.29
```

and likewise at characters 3057, 3116 and 3183. The boxes are consistent with the surrounding
glyphs' baselines and sizes, so PDFKit has located the glyph and mapped it to U+0007.

Attachment: `probe.swift`, a single file using only Foundation, AppKit and PDFKit, which prints
every character with its scalar value and `characterBounds`.
