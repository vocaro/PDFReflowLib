# Damaged text encodings (#38): signal survey, detection rule and gates

Corpus `census-rrs2002-01` (`corpus/cache/rrs2002-01.pdf`, SHA-256
`0f97380ae4308581bd70013b7317faafd7c217654236bd31d1448f26eae56905`). macOS 27 arm64, release
CLI, library defaults unless stated. Date 2026-09-16.

## Mechanism

Pages 2–20 were distilled from LaTeX with Acrobat Distiller 4.05. Every body font is Type 1
(`FontFile3`/`Type1C`) with an `Encoding` dictionary whose `Differences` array names glyphs
`G<index>` (object 142: `[1 /G90 /G108 /G111 /G100 ...]`) and no `ToUnicode` map; five Type3
fonts (`T2`–`T6`) use `c<code>` names the same way. Poppler (`mutool draw -F txt`) yields U+FFFD
for every character; PDFKit instead reports the index as the character, so `Two data files
were used.` extracts as `Wzr gdwd ohv zhuh xvhg1` (each letter shifted by three, ligatures
dropped) and PDFKit attributes the runs to a fallback `Helvetica` font. The converter's existing
damage test counts U+FFFD/U+FFFC and never fired. The Word cover (page 1) uses non-embedded
WinAnsi TrueType fonts and extracts cleanly.

## Survey tooling

- `dump-pages.swift` (this directory): scratch tool compiled with the library's `NativeTextReader`,
  `GraphicsReader` and supporting sources exactly as `tools/capture-layout-fixture.swift` is
  (see doc/regression-testing.md). For every page it records PDFKit's page string, per-run font
  names and, from the Core Graphics page dictionary, every font reachable from `Resources/Font`
  and nested Form XObjects: subtype, encoding form, `Differences` count and sample, `ToUnicode`
  presence and font-program kind.

  ```sh
  swiftc -O Sources/PDFReflowLib/NativeTextReader.swift Sources/PDFReflowLib/ConversionTypes.swift \
    Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
    Sources/PDFReflowLib/GraphicsReader.swift Sources/PDFReflowLib/NativeSpacingReader.swift \
    measurements/damaged-text-encoding/dump-pages.swift -o /tmp/dump-pages
  /tmp/dump-pages corpus/cache/rrs2002-01.pdf /tmp/dump/rrs2002-01.json 2>/dev/null
  ```
- `score.py`: per-page statistics over the dumps (words, function-word rate, rare-bigram rate,
  font evidence) and the ranking used below. `bigrams.py` derives the embedded common-bigram list.

Fourteen English corpus documents, 5,059 pages: Loper Bright 114, Replay Clocks 12, algebra 489,
Our Flag 56, Blue Book 312, DGA 10, 9/11 585, Warren 920, CDC 42, Census 20, FAA 522, NBS 7, USGS 2,
NOAA 1,834. The Arabic and Chinese cases were not surveyed (English statistics only). Dumping
took 0–71 s per document.

## Signal (a): structural font evidence

A simple font (Type1, MMType1, TrueType, Type3) with no `ToUnicode` stream whose `Differences`
names are at least half index-style (`G108`, `g3`, `c63`, `glyph12`, `index5`, `cid7`; `uniXXXX`
and `uXXXX` are conventional Unicode names and never count). Composite Type0 fonts are not
examined (they map through CMaps; an `Identity` CID font without `ToUnicode` is a different
damage class).

| Document | Pages with evidence |
| --- | --- |
| Census | 19 of 20 (all body pages; page 1 cover: none) |
| Every other surveyed document | 0 of 5,039 |

No page outside the Census report has such a font, including the DGA Type3 fonts (they carry
`ToUnicode`), the Blue Book and Warren OCR layers, and NOAA.

## Signal (b): English text statistics

Words are runs of at least two letters. `stop` is the share of words in a 148-entry
function-word list; `rare` is the share of within-word ASCII letter pairs outside the 300 most
frequent pairs of macOS `/usr/share/dict/words` (web2, 235,974 words, SHA-256
`be41ad97…bab9`; the 300 pairs cover 97.66% of pair occurrences). Both tables are embedded in
`TextEncodingCheck.swift`; nothing is downloaded and no model is used.

Census per page (words / stop / rare / font evidence):

| Page | Words | stop | rare | fonts |
| --- | --- | --- | --- | --- |
| 1 (cover) | 80 | 0.287 | 0.007 | 0 |
| 2 | 336 | 0.000 | 0.648 | 5 |
| 3 | 270 | 0.000 | 0.697 | 2 |
| 4 | 390 | 0.003 | 0.610 | 7 |
| 5 | 340 | 0.000 | 0.643 | 8 |
| 6 | 447 | 0.000 | 0.640 | 6 |
| 7 | 456 | 0.004 | 0.669 | 9 |
| 8 | 388 | 0.000 | 0.645 | 9 |
| 9 | 386 | 0.000 | 0.634 | 9 |
| 10 | 291 | 0.000 | 0.660 | 5 |
| 11 | 337 | 0.000 | 0.653 | 4 |
| 12 | 59 | 0.000 | 0.549 | 3 |
| 13 | 267 | 0.000 | 0.613 | 4 |
| 14 | 325 | 0.000 | 0.644 | 5 |
| 15 | 73 | 0.000 | 0.541 | 2 |
| 16 | 308 | 0.000 | 0.632 | 2 |
| 17 | 286 | 0.000 | 0.636 | 3 |
| 18 | 279 | 0.000 | 0.618 | 10 |
| 19 | 181 | 0.000 | 0.603 | 9 |
| 20 | 41 | 0.000 | 0.663 | 6 |

Distribution over pages with at least 30 words in the other documents (stop minimum / 5th
percentile / median; rare maximum / 95th percentile / median):

| Document | Pages ≥30 words | stop min / p5 / med | rare max / p95 / med |
| --- | --- | --- | --- |
| Loper Bright | 114 | 0.300 / 0.364 / 0.431 | 0.057 / 0.033 / 0.024 |
| Replay Clocks | 12 | 0.176 / 0.176 / 0.497 | 0.059 / 0.059 / 0.029 |
| Algebra | 352 | 0.000 / 0.283 / 0.497 | 0.467 / 0.059 / 0.030 |
| Our Flag | 52 | 0.154 / 0.332 / 0.451 | 0.052 / 0.036 / 0.019 |
| Blue Book (inherited OCR) | 283 | 0.000 / 0.048 / 0.126 | 0.280 / 0.220 / 0.120 |
| DGA | 9 | 0.257 / 0.257 / 0.291 | 0.028 / 0.028 / 0.022 |
| 9/11 | 573 | 0.012 / 0.213 / 0.420 | 0.114 / 0.043 / 0.024 |
| Warren (inherited OCR) | 851 | 0.000 / 0.115 / 0.455 | 0.464 / 0.066 / 0.023 |
| CDC comic | 25 | 0.155 / 0.193 / 0.387 | 0.133 / 0.097 / 0.046 |
| FAA | 490 | 0.023 / 0.102 / 0.422 | 0.061 / 0.040 / 0.021 |
| NBS | 7 | 0.198 / 0.198 / 0.408 | 0.043 / 0.043 / 0.024 |
| USGS | 2 | 0.294 / 0.294 / 0.294 | 0.021 / 0.021 / 0.021 |
| NOAA | 1,781 | 0.047 / 0.131 / 0.314 | 0.072 / 0.051 / 0.025 |
| Fed Explained | 125 | 0.192 / 0.287 / 0.375 | 0.056 / 0.033 / 0.020 |

Neither statistic alone separates: `stop = 0` also occurs on Blue Book OCR tables (pages 184,
189, 190, 255, 256), Warren's handwriting exhibits (510) and index pages (915, 916) whose
`rare` is 0.04–0.12, and `rare` reaches 0.467 on algebra page 472 (radical answer key, 32
words: `5) 2 3√ | 6) 6 2√ …`) and 0.464 on Warren page 553 (handwritten exhibit OCR, 39
words) whose `stop` is 0–0.03. The combined text rule `words ≥ 20 ∧ stop < 0.05 ∧ rare ≥ 0.30`
matches every Census body page (minimum margin: rare 0.541 on page 15 versus the 0.30
threshold; stop at most 0.004 versus 0.05) and exactly four other pages of 5,039:

| Page | Words | stop | rare | Content |
| --- | --- | --- | --- | --- |
| Algebra 182 | 28 | 0.000 | 0.327 | radical exercises |
| Algebra 472 | 32 | 0.000 | 0.467 | radical answer key |
| Warren 548 | 32 | 0.031 | 0.316 | handwritten exhibit OCR |
| Warren 553 | 39 | 0.026 | 0.464 | handwritten exhibit OCR |

None of the four has font evidence, so the combined rule flags none of them.

## Detection rule

A page reports `damagedTextEncoding` only when both signals hold: a font with structural
evidence in its resources (or a nested Form, depth ≤ 4, at most 256 fonts examined) and
extracted text with at least 20 words, under 5% function words and at least 30% rare pairs,
for a declared language whose primary subtag is `en`. Pages that already require a full-page
image are not judged. Automatic policies (`.automatic`, `.automaticIncludingImageBackedText`)
and `.always` then recognize the page image; `.never` retains the unreadable text, recommends a
source-page reference (`referenceImageOmitted` under `referenceImages = .never`) and drops any
structure-tag association; the page's words never enter the hyphen-repair vocabulary.

Text-only detection was rejected because its margin over the four near misses is thin
(0.467 versus 0.541) and those pages are exactly the classes the issue names as risky.
Font-only detection was rejected because the structural evidence says nothing about whether
PDFKit happened to produce readable text and, on a math page whose only index-style font is a
symbol font, the prose may be intact. Requiring both keeps the measured false-positive rate at
0 of 5,039 pages while the Census body scores far inside both thresholds.

## Census before and after

Before (HEAD dc81a78, from the issue and the previous contract basis): pages 2–20 shipped
shifted-letter prose with only `imageRegion` warnings; page 3 read `5GdwdIlohv / Wzr gdwd ohv
zhuh xvhg1 / 461 Vfkhgxoh G dj`.

After, defaults (`--ocr automatic`): 20 pages, 20 reflowed, 19 recognized, 54 images. Pages
2–20 each report `damagedTextEncoding` ("… Recognition of the page image replaces it.") and
`ocrUsed`; page 1 reports nothing. Vision on page 3 reads: `2 Data Files Two data files were
used. 2.1 Domingo-Ferrer and Mateo-Sanz We used the same subset of American Housing Survey
1993 public-used data that was used by5. … 1. Total income 2. Adjusted gross income 3. Wage and
salary income … 12. Aged exemption Ilag 13. Schedule D flag 14. Schedule E flag 15. Schedule C
flag 16. Schedule F flag …` — the reviewed heading, first sentence, subsection title and the
16 numbered fields are recovered (one OCR error: `Ilag` for `flag` in field 12; `by5` for
`by [5]`). Page 20 reads `and for different noise proportion parameters d, we compute a
masked data set …` with its equations preserved as regions.

After, `--ocr never`: 20 pages, 20 reflowed, 0 recognized, 56 images. Pages 2–20 report
`damagedTextEncoding` ("… The unreadable native text is retained; read the accompanying
source-page image instead.") and carry the source-page reference; the shifted text is
unchanged. Page 1 reports nothing.

Commands:

```sh
swift build -c release
.build/out/Products/Release/pdf-reflow corpus/cache/rrs2002-01.pdf auto.epub > auto.json
.build/out/Products/Release/pdf-reflow corpus/cache/rrs2002-01.pdf never.epub --ocr never > never.json
```

## Reproducer and controls

`Tests/PDFReflowLibTests/DamagedEncodingTests.swift` builds an original Type3 fixture whose
glyph procedures draw the correct letters through Helvetica while the `Differences` names each
code `G<code + 3>`; PDFKit extracts `Wzr gdwd ilohv zhuh xvhg1` from it, and the same fixture
with a correct `ToUnicode` CMap extracts `Two data files were used.` The checksum-pinned
`census-1` and `census-3` source-layout fixtures (captured with `tools/capture-layout-fixture.swift`)
supply the real statistics: page 3 scores 270 words, stop 0.000, rare 0.697; page 1 stop 0.287.
Controls: `blue-12`, `blue-5`, `algebra-438`, `algebra-471`, `911-451`, `faa-511`, `flag-27`,
`cdc-5`, `911-585`, `usgs-1` fixtures and the six bundled fixture PDFs are not flagged.

Failing baseline: with the detector disabled (`damagedEncoding` forced false in the pipeline),
the end-to-end tests fail (see "Gates" below); the unit tests on `TextEncodingCheck` have no
pre-change counterpart because the type is new.

## Gates

- `scripts/check-all.sh --fast`: pass in 59 s. 226 Swift tests (218 before plus the eight in
  `DamagedEncodingTests.swift`), 156 Python tool tests (155 plus the `absentWarningCodes`
  negative control), the native-extraction concurrency smoke gate, six fixture conversions and
  13 policy conversions with 22 rejection/cleanup cases.
- Failing baseline: with `TextEncodingCheck.hasUnmappedFont` forced to return false, the
  mechanism test, the font-evidence test and every end-to-end test fail on the missing
  `damagedTextEncoding` warning while the plausibility-statistics and bundled-fixture controls
  still pass; the source was restored afterwards.
- Corpus lane (`tools/run_corpus_regressions.py --case …`, release CLI, EPUBCheck): PASS
  `census-rrs2002-01` (54 content checks, 20 reviewed pages), `cia-blue-book-14-1955`,
  `cdc-zombie-pandemic-2011`, `wallace-algebra-2010`, `gpo-911-2004`, `faa-phak-8083-25c`.
- Census memory gate: the first run failed its 128 MiB RSS ceiling at 245 MiB because 19 pages
  now run through Vision (38 MiB without OCR). The ceiling was set when the report did no
  recognition; the OCR-bearing peers measure 370 MiB (CDC, ceiling 512) and 260–290 MiB (Fed,
  ceiling 768). The manifest ceiling is raised to 512 MiB with that reason recorded in its
  scope; the rerun measures 248.5 MiB and passes. Conversion takes 5.3 s.
- Control books: no `damagedTextEncoding` warning and unchanged recognized-page counts on the
  five controls (Blue Book 0 recognized, CDC 9, algebra 0, 9/11 8, FAA 0), consistent with the
  survey's zero font-evidence pages outside the Census report; the detector runs one Core
  Graphics dictionary walk per page and a word statistic over already extracted text.

## Limits and gaps

- Only English (`en`, `en-*`) is judged; other declared languages never report the code.
- Pages with fewer than 20 words (numeric tables, figure pages, formula-only pages) are not
  judged even when their fonts are unmapped; their few damaged words still ship.
- Composite Type0/CID fonts, fonts with an incorrect but present `ToUnicode` map, and embedded
  fonts whose builtin encoding (no `Differences`) is custom are outside the structural signal.
- The bigram table comes from a word list's type frequencies, not running text; it separates
  prose from substitution-cipher text but is not a language model.
- Vision transcription of the Census pages carries ordinary OCR errors (`Ilag`, `by5`); the
  contract checks five reviewed phrases on page 3 only.
