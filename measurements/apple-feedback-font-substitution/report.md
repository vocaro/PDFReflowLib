# PDFKit reports every embedded Type1 font as "Helvetica", losing family and weight

Suggested area: macOS / PDFKit. Type: Incorrect/Unexpected Behavior.
Drafted 2026-09-20; not yet filed.

## Summary

For a document whose pages embed four distinct Type1 fonts with `WinAnsiEncoding`, every
`.font` attribute in `PDFPage.attributedString` is `Helvetica`, and every run's symbolic traits
are the same value with no bold or italic bit set. The point sizes are correct. The consequence is
that a demi-weight sub-heading and the body text around it are indistinguishable in the attributed
string, although the page draws them in different fonts and weights.

## Environment

macOS 27.0 (26A428), arm64, Xcode 27.0.

## Steps to reproduce

1. Download *The Fed Explained: What the Central Bank Does* (public domain, Board of Governors of
   the Federal Reserve System), SHA-256
   `8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60`, from
   <https://www.federalreserve.gov/aboutthefed/files/the-fed-explained.pdf>.
2. `mutool info -F the-fed-explained.pdf 33` to see the fonts the page embeds.
3. Build the attached probe: `xcrun swiftc -O probe.swift -o pdfkit-text-probe`
4. `./pdfkit-text-probe the-fed-explained.pdf 33 fonts`

## Expected

The `.font` attribute names the embedded font, or a substitute whose traits reflect the embedded
font's weight and slant.

## Actual

Page 33 embeds these four fonts:

```
Type1 "NSVCRT+FranklinGothicLTPro-Bk"       WinAnsiEncoding
Type1 "PNWOTP+ITCFranklinGothicStd-Book"    WinAnsiEncoding
Type1 "CSBZTP+FranklinGothicLTPro-DmIt"     WinAnsiEncoding
Type1 "KGIFBZ+FranklinGothicLTPro-Dm"       WinAnsiEncoding
```

Every attribute run PDFKit reports on that page names `Helvetica`, with
`symbolicTraits` = `0x80000000` on all of them:

| Run | Reported font | Size | Traits | Text |
| --- | --- | ---: | --- | --- |
| 0 | Helvetica | 8.00 | 0x80000000 | `Conducting Monetary Policy 29` |
| 222 | Helvetica | 12.00 | 0x80000000 | `FOMC Statement and Chair's Press Conference` |
| 266 | Helvetica | 10.00 | 0x80000000 | body text |
| 1898 | Helvetica | 14.00 | 0x80000000 | `Communicating Policy Regularly and Clearly` |

The 12-point run is set in the demi (bold) face and the 10-point body in the book face; nothing in
the attributed string distinguishes them but the point size. No run anywhere in the document
reports a bold or italic trait, including the demi-italic face the page also embeds.

Attachment: `probe.swift`, a single file using only Foundation, AppKit and PDFKit, which prints
each attribute run's font name, point size and symbolic traits.
