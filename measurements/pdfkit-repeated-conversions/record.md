# PDFKit attributed-text growth across repeated conversions (#4)

2026-09-18, macOS 27.0 (26A428), Xcode 27, Apple silicon, release builds; iOS 27.0 Simulator
(iPhone 17 Pro). Baseline is coordination tip `23b65c5`; candidate is `23b65c5` plus this change.
Six other agents shared the Mac (load average about 25), so seconds and peak RSS are not
comparable between runs; `leaks` counts are. No EPUB, trace or probe binary is committed.

## What grows

`harness.swift` (built by `measure.sh`) converts PDFs through the public `PDFConverter` API
repeatedly in one process, with pinned packaging, and runs `leaks` on itself after every round.
With `MallocStackLogging=1`, every leaked root on TechPort, Fed, Wallace, the magazine and FAA is
an `NSConcreteMutableAttributedString` allocated under `PDFSelection.attributedString` →
`CGPDFSelectionCreateAttributedString` → `PageLayout::CreateAttributedStringForStringRanges`,
called from `NativeTextReader.extractLines`. Nothing else leaks: no other reader (spacing,
font weight, maths, drawn bullets, graphics, structure) shows up, and the growth of the default
malloc zone per round matches the leaked bytes. Physical footprint after a conversion swings by
hundreds of MiB with the allocator's reclaim of freed pages (98% of the dirty malloc pages are
free), so it cannot measure the growth. On Our Flag a line's attributed string also carries an
`NSTextAttachment` whose JPEG data (about 270 KB each) leaks with it.

The iOS Simulator's PDFKit leaks the same way (the Simulator has no `leaks`; default-zone
growth stands in for it).

## Change

`NativeTextReader.attributedTexts` reads a page's styled lines with one attributed request on the
union of their selections and slices each line out of it, instead of one request per line. Each
line's text must align in order in both the union's plain and attributed text (`lineRanges`),
directly or after one newline; otherwise the page falls back to requests per line. On every
page of the 21 cached sources other than NOAA and Warren, a standalone probe found each
slice equal to the line's own attributed string (`isEqual`), except that attachments are new
`NSTextAttachment` instances, which the library never reads; the union failed to align on 140
Blue Book pages (invisible OCR text, never styled), 2 M-618 pages, 1 JRES and 1 Census page.

## Results, leaked per conversion (Mac, `leaks`)

| Input | Baseline objects | Baseline MiB | Candidate objects | Candidate MiB |
| --- | ---: | ---: | ---: | ---: |
| FAA (522 pages, 3–4 rounds) | 161,000 | 8.4 | 5,000 | 5.1 |
| Fed (135 pages, 3 rounds, `check_repeated_conversions.py`) | 22,937 | 1.46 | 1,781 | 1.10 |
| TechPort + Fed + magazine (10 rounds) | 34,900 | 2.06 | 5,500 | 1.63 |

iOS Simulator, TechPort + Fed + magazine, 10 rounds: default-zone growth per round after round 2
is 2.52 MiB baseline and 1.62 MiB candidate. PDFKit alone in the Simulator, one FAA pass: 9.3 MiB
retained with one request per line, 5.9 MiB with one per page.

So about a quarter to a third fewer leaked bytes and 90–97% fewer leaked objects. What is left is
the page text itself (about 3 bytes per character), which only Apple can release (FB24783799).

Output is byte-identical (pinned identifier and date) between baseline and candidate CLIs on
21 cached sources: the 19 lane documents other than NOAA and Warren (FAA, Fed, Wallace, 9/11,
Blue Book, Our Flag, CDC, DGA, the magazine, TechPort, SCOTUS, Census, JRES, arXiv, Pro Se, the
three other NTRS papers, USGS) plus M-618 and IRS p596. NOAA and Warren were not compared byte
for byte; their lanes pass. All 21
corpus lanes pass with the candidate; `swift test` (1,042) and the Python tests (258) pass.

## In-process determinism

One baseline run of four FAA conversions in one process produced a different EPUB in round 2
(`6c3ac124…` against `7630216c…` in rounds 1, 3 and 4). Nine later FAA conversions of the
candidate and an intermediate version, in five processes, and two more baseline conversions in
fresh processes all produced `7630216c…`. The cause was not investigated; the repeated-conversion
gate now fails on any round whose EPUB differs from the first.

## Gate

`tools/check_repeated_conversions.py` runs three Fed conversions in one process with `leaks` and
fails above 30 leaked objects per page per conversion (candidate about 13; baseline 170 fails) or
on differing EPUBs. `AttributedExtractionTests.swift` checks the union slices and the alignment.
