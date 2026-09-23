# A sparse chapter title measures against the document body

Issue #296, measured on 2026-09-23 against main `a1bd1c8` and the accompanying change.
The source is the corpus-pinned NOAA *Fifth National Climate Assessment*, SHA-256
`1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf`.

Physical page 33 sets its running head at 12 pt and its title at 24 pt. The title's 51
characters outweigh the running head's 42, making the page's character-weighted body 24 pt.
The old 30 pt heading threshold excludes that title and both lines join into one paragraph.
Pages 80 and 139 have shorter titles at 36 pt, so their running heads set the page body to
12 pt and the titles already become headings. This is typography evidence, not a colon or
word-count rule.

A sparse page establishes no prose body (fewer than three same-size lines or 200 characters).
When document evidence exists, cap only that page's heading estimate at the larger of the
document body and the smallest reflowable type on the page. The latter preserves the local
contrast: a small running head does not become a heading because it exceeds the document body.
Its geometry still uses the original page body, established prose keeps its own threshold,
and the existing document heading floor remains. No source-specific title matching is used.

The fresh capture of page 33 has exactly the committed fixture's lines, graphics, bounds and
source checksum. The page was rendered with Poppler and visually reviewed: the running head
is separate from the larger title above the photograph. The regressions exercise all three
source openers, a synthetic long/short title pair, established large-print prose, and the
existing heading/body controls. The new page-33 heading assertion fails against the baseline.
Raw captures, rendered pages, converted books and logs remain outside the repository at
`/tmp/issue-296-evidence`.

Reproduction from the repository root (Python 3.10 or later):

```sh
swift build -c release
python3 tools/evaluate_real_document.py --case noaa-nca5-2023 \
  --pdf corpus/cache/noaa_61592_DS1.pdf --converter .build/release/pdf-reflow \
  --output /tmp/noaa-heading-evaluation --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/check_corpus_content.py --case noaa-nca5-2023 \
  --evaluation /tmp/noaa-heading-evaluation
swift test --filter 'sparse|establishedLargePrintProseKeepsItsOwnHeadingThreshold|typographyReadsThePageOnce|Heading|heading|Title|title|Body|body|Cover|cover|Fed|fed'
swiftc $(python3 tools/pdfreflow_tools/swift_sources.py capture-layout-fixture.swift) \
  -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture noaa-nca5-2023 33 /tmp/noaa-33-live.json
pdftoppm -f 33 -l 33 -scale-to 1200 -singlefile -png \
  corpus/cache/noaa_61592_DS1.pdf /tmp/noaa-33
```

Validation: 99 focused Swift tests and 31 corpus-content Python tests pass. Baseline and
candidate both convert all 1,834 pages at library defaults and pass EPUBCheck with zero
warnings/errors, structural validation, progress validation and the 1,280 MiB peak-RSS gate.
The strengthened nine-page corpus contract passes all 59 content checks on the candidate;
it fails only the newly required page-33 heading on the baseline.

`comparison.json` compares every page's text, headings, paragraphs, image references, lists,
table rows and preformatted blocks. Only headings/paragraphs change, on pages 33, 384, 526,
815 and 1710: each previously joined running-head/title paragraph becomes a running-head
paragraph and title heading(s). The four additional pages were freshly captured and rendered
for visual review, and their fixtures now exercise the same defect, including lowercase
second title lines. Pages 80 and 139 remain unchanged. All 1,609 image entries are byte
identical, all page markers match, and the total text remains 5,553,330 characters. The
comparison does not claim a visual review of the entire document or image legibility
qualification; the evaluation receipt's `qualifiedForFidelity` remains false.

| Measurement | Baseline | Candidate |
| --- | --- | --- |
| Converter SHA-256 | `9ee62ad1f0b73c847b44a4540eb25f6b02f65bcdfb1653957cb919e645b2025d` | `16dc131e3008e5c0786ce49c09963c0eafb37f812b2b3e3217050e75f3dc5571` |
| EPUB SHA-256 | `2474492e66b97a5300a518ae8a1a5dd7aec50b54ee9abbb97b3bc4616d1d7587` | `5690ef45951d24c63efc9d1c6798cad1aa242b92d2e32cb43ddc123e9f009f23` |
| EPUB bytes | 269,200,237 | 269,200,299 |
| Conversion seconds | 125.6 | 132.4 |
| Peak process RSS bytes | 910,737,408 | 1,001,521,152 |

Runs used macOS 27.0 arm64 and recorded three concurrent evaluations because other agents
were running validations. The timings and memory values are observations under contention,
not a performance comparison or mobile-device measurement.
