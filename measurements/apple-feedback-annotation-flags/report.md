# PDFAnnotation.shouldDisplay is true for an annotation whose Hidden flag is set

Suggested area: macOS / PDFKit. Type: Incorrect/Unexpected Behavior.
Drafted 2026-09-20; filed as FB24908760 on 2026-09-23.

## Summary

`PDFAnnotation.shouldDisplay` returns `true` for an annotation whose `/F` entry sets the Hidden
bit (bit 2, value 2), which PDF 32000-1:2008 table 165 defines as "Do not display the annotation".
The same property correctly returns `false` for the NoView bit (bit 6, value 32). PDFKit's own
rendering honours both flags and draws neither annotation, so the property disagrees with the
framework's own behaviour, and a caller that asks before drawing gets the wrong answer for Hidden.

## Environment

macOS 27.0 (26A428), arm64, Xcode 27.0.

## Steps to reproduce

The attached probe needs no input file: it writes the PDF it tests.

1. `xcrun swiftc -O probe.swift -o annotation-flags-probe`
2. `./annotation-flags-probe`

It builds one 200 × 200 page carrying four identical filled square annotations that differ only in
their `/F` flags, writes it with `PDFDocument.write(to:)`, reopens it, and for each annotation
prints `/F` as read back, `shouldDisplay`, and the number of dark pixels the annotation's own band
receives when the page is rendered with `PDFPage.draw(with:to:)` into a white bitmap context.

## Expected

`shouldDisplay` is `false` for an annotation with the Hidden flag set, as it is for NoView.

## Actual

```
flags            /F       shouldDisplay  dark pixels drawn
none             0        true           19200
Hidden (bit 2)   2        true           0
NoView (bit 6)   32       false          0
Print (bit 3)    4        true           19200
```

The Hidden row is the defect: the flag round-trips through the file correctly, the renderer
respects it, and only the property is wrong.

## Notes

The annotations here are created by PDFKit and have no explicit `/AP` appearance stream. We have
not tested a Hidden annotation carrying an appearance stream produced by another writer.

Attachment: `probe.swift`, a single file using only Foundation, AppKit, CoreGraphics and PDFKit.
