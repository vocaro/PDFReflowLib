# Source-verified chapters inside part hierarchies

Issue #15, measured 2026-09-23 on macOS 27 arm64. Implemented in `a168081`, reviewed in
`b02ce56`, with standalone-probe compatibility in `29e3029`. The comparison is against the
integrated parent implementation at `be89f8c`; its runtime matches this branch's `6471fac`
base. `results.json` records the exact final release hash and checksum-pinned NOAA source.

The reader now admits consecutive Arabic or canonical Roman chapter numbers at the root or
inside explicit Part containers. A colon, period or spaced dash can separate number and title.
Destinations must remain local, unique and increasing. Traversal stops at four levels and
10,000 entries. An unrelated outline subtree cannot invalidate valid root chapters, and a
chapter's children remain section navigation. Each candidate still needs the complete printed
number and title on adjacent native lines at the opening; body mentions, OCR and synthetic text
styles do not establish chapter boundaries. Other-language and unnumbered schemes retain safe
ordinary packing rather than guessing chapter semantics.

Three new tests exercise a real two-page PDF with a Part/Chapter I/Chapter II outline and
reciprocal local links, numeral/punctuation matching and rejected prose/invalid numeral cases,
and an unrelated remote nested outline alongside valid root chapters. The public conversion
creates two spine documents with working reciprocal links and preserves nested navigation.
All 742 Swift tests pass, including the existing atomic-block, subdivision, streaming,
page-anchor, cancellation and output-budget tests. The standalone chapter probe compiles and
matches all 32 NOAA candidates against their complete native opening lines.

The final full 1,834-page NOAA conversion passes EPUBCheck, structural/link/spine checks,
59 source content assertions, the unchanged 1,280 MiB Mac RSS ceiling and all 5,417 monotonic
progress events. It completes with library defaults in 114.38 seconds, at 1,003,159,552 bytes
peak process RSS and 393,709,248 bytes sampled physical footprint. Its EPUB is 269,761,343 bytes.
These are one shared-host observation, not performance claims or physical-device budgets.

All parsed pages, page markers and spine document contents equal the parent. All 1,609 images
and navigation are byte-identical. Every one of the 32 verified chapter pages starts a spine
document; large chapters retain byte-based subdivisions. A fresh public-API conversion of the
complete original canceled at source page 100 returns CancellationError and leaves its output
and staging directory empty; return plus cleanup took 0.0048 seconds in that run.

This qualification covers the original large-report acceptance together with the changes
already present on main: page spilling (`a28fb09`), streamed logical blocks (`89ca945`),
source-outline navigation (`14a8f90`), converted annotation links and default-budget corpus
admission. The 60,000-byte body target remains soft: an oversized atomic block occupies its own
spine document without text loss, subject to the existing entry/final-output ceilings. It does
not claim arbitrary safe subdivision inside tables, code or indivisible content. Existing
annotation links cross spine boundaries; inferred footnote relationships remain a separate
feature under #219. Earlier device observations are in the page-retention record; no new
physical-device run is claimed here.

Raw artifacts are outside the repository under `/tmp/pdfreflow-15-*`. Reproduce with:

```sh
swift test
swift build -c release
python3 tools/evaluate_real_document.py --case noaa-nca5-2023 \
  --pdf corpus/cache/noaa_61592_DS1.pdf --converter .build/release/pdf-reflow \
  --output /tmp/noaa-chapter-qualification --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/check_corpus_content.py --case noaa-nca5-2023 \
  --evaluation /tmp/noaa-chapter-qualification
```
