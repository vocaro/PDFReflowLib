# Implausible inherited text layers (#93): survey, rule, review and gates

Tier: deterministic Apple PDF/OCR stack, macOS 27.0 (26A428) arm64, Xcode 27.0 (27A266a), release
CLI, host terminal, library defaults unless stated. Date 2026-09-17. The survey, rule and review were
built on `ce2cf5b` and repeated after merging each later coordination tip (`ec22aff`, `a4b0f30`,
`9ec0608`, `f8a0a7a`); the final measurements below are on `f8a0a7a` (library sources identical to
`9ec0608`): baseline CLI `3f121800…6a2c` built from those sources, candidate CLI `86eeaf7a…3ded`.
Both run under the name `pdf-reflow`. Vision's compiled programs under that name changed several
times during the day (other conversions on the machine share the cache, #94); every final comparison
below used identical programs (`b7e8a53e…d171a`), and CDC's recognized text was identical across
three different compiles. The machine was shared (load average 12–60), so times are paired
alternating runs, not budgets.

**Result.** Text inherited over a page-sized image now fails a two-part English plausibility test
(too few English words, or too little text for the page's text-shaped ink), reports
`implausibleTextLayer` under every policy, and is replaced by OCR under the default policy. Of the
1,353 image-backed pages in the English corpus it fails 34: 27 CDC comic pages and 7 Warren pages.
All 34 were reviewed; none replaces a good layer (one, Warren 103, replaces a correct but
incomplete caption-only layer; OCR reads the caption too). CDC dialogue units with reflowed text rise from
124 to 222 of 231. No Blue Book, NBS, DGA, FAA, Fed, Our Flag or NOAA page fails, and the corpus
comparator finds no change in any of those books.

## Rule

Implemented in `Sources/PDFReflowLib/TextLayerPlausibility.swift`, called from `extractPage` for
pages whose text is over a page-sized graphic (the `unverifiedTextLayer` pages), except pages that
require a page image or already report `damagedTextEncoding`, and only for English books.

1. **Too few English words.** Whitespace tokens, stripped of leading and trailing non-letters, split
   at hyphens, clitics (`'s`, `n't`, `'ll`, `'re`, `'ve`, `'m`, `'d`) removed. A word is *English* if
   the system lexicon (`NLEmbedding.wordEmbedding(for: .english)`, 57,171 lower-case words on macOS 27)
   contains it or it is `a`/`I`; *damaged* if it is a lower-case word the lexicon lacks, has irregular
   capitals (`sreANee`, `HAve`), or is a stray lower-case letter (`n e x t`); *neutral* otherwise
   (capitalized or upper-case unknown words: names, abbreviations; words holding symbols: `v/eus`).
   Fails when English + damaged ≥ **20**, English < **50%** of them, and fewer than **20%** of the
   tokens contain a digit.
2. **Too little text for the ink.** Only when the layer has fewer than **32** English words (and did
   not fail 1): the page is rendered at 180 DPI and `OCRTextCoverage.measure` runs with the layer's line
   boxes. Fails when at least **75%** of the text-shaped ink lies outside them, in at least **7**
   uncovered rows, and the layer has fewer English words than uncovered rows.

Policy: `.automatic`, `.automaticIncludingImageBackedText` and `.always` recognize a failing page;
`.automaticKeepingImageBackedText` (new, CLI `--ocr keep-image-backed`) and `.never` keep its
layer, which keeps `unverifiedTextLayer` and its reference. The warning is emitted either way.

### Why a lexicon

The #38 statistics (function-word and letter-pair rates) do not separate the CDC layer: its pages
read a median 0.39 function words (minimum 0.16) and at most 0.13 rare pairs, inside ordinary prose. The CDC damage is
real letters in wrong places. An embedded dictionary was considered (web2 is 2.5 MB and lacks
inflections; a Bloom filter over it would still be ~0.3 MB and admit short noise). The system
English word embedding's vocabulary is on-device, loads in 7 ms with about 2 MB of physical
footprint, and answers 100,000 lookups in 37 ms (`NLEmbedding.contains`); lookups are serialized
behind a mutex. It knows `zombie`, `okay`, `website` and not `sreanee`, `eeen`, `tbe`, `witb`.
Its contents can change with the OS; without it only the ink test runs.

## Tools

- `survey-pages.swift` (built with `build-tool.sh`, which compiles the library sources into the
  tool) walks every page, repeats the pipeline's extraction up to the OCR decision (graphics,
  native lines with column joints, hidden-text removal, tint composition, #117's
  `layoutComesApart`), keeps image-backed pages, and records their text, line boxes and
  `OCRTextCoverage` at 180 and 72 DPI. `survey-all.sh <dir>` runs it on the seventeen English books
  (0–912 s per book; Warren is the slowest).
- `score-pages.swift` scores those records with the library's own `TextLayerPlausibility` and
  writes [scores.tsv](scores.tsv) (one row per image-backed page).
- `sensitivity.py` recomputes the failing pages per book as each threshold moves.
- `probe-ocr.swift` recognizes chosen pages with `OCRReader` (its own executable name, so its own
  Vision compile: review evidence only).
- [cdc-dialogue-units.tsv](cdc-dialogue-units.tsv) is the manual CDC count below.

## Survey

Image-backed pages per book (Census, algebra, 9/11, Loper Bright, Replay Clocks, USGS, the pro se complaint and the NASA paper have none;
Arabic and Chinese books are not judged). *Rendered* counts pages the ink test renders. *Reviewed*
counts failing pages read against the source.

| Book | Image-backed pages | Rendered | Fail (words / ink) | Reviewed | Wrongful replacements |
| --- | ---: | ---: | ---: | ---: | ---: |
| CDC comic | 33 | 6 | 27 (25 / 2) | 27 | 0 |
| Warren | 910 | 76 | 7 (6 / 1) | 7 | 0 (103 borderline, below) |
| Blue Book | 312 | 25 | 0 | – | 0 |
| NOAA | 62 | 44 | 0 | – | 0 |
| FAA | 18 | 1 | 0 | – | 0 |
| Fed Explained | 8 | 0 | 0 | – | 0 |
| NBS | 7 | 0 | 0 | – | 0 |
| Our Flag | 2 | 1 | 0 | – | 0 |
| DGA | 1 | 1 | 0 | – | 0 |
| **Total** | **1,353** | **154** | **34** | **34** | **0** |

Near misses reviewed as plausible or deliberately exempt (English share of judged words):

| Page | Share | Numeric share | Layer | Outcome |
| --- | ---: | ---: | --- | --- |
| Warren 520–527 witness lists | 0.65–0.75 | 0.08–0.11 | good OCR (names, `Vol. VII, p. 34.`) | pass; nearest plausible layer to 0.5 |
| NBS 7 | 0.56 | 0.17 | Paper Capture prose split mid-word (`fi e ld stre ngth`) | pass (damaged spacing, readable) |
| Blue Book 33 | 0.60 | 0.18 | chart axis noise | pass |
| Warren 636, 628, 546 | 0.50–0.58 | 0.02–0.06 | carbon-copy typescript noise | pass (damaged, not flagged) |
| Warren 885 notes | 0.39 | 0.45 | good (`Id. at 283.`, `supra, pp. 61-71`) | exempt by digits |
| Blue Book 116–260 tables (20 pages < 0.5) | 0.31–0.50 | 0.21–0.43 | label OCR plus handwritten cells missing | exempt by digits |

The digit guard is load-bearing: without it the 20 Blue Book table pages and Warren 885 fail. For
Blue Book 122 the probe's Vision transcription is worse than the inherited layer (`VALVATIÓN DE ALL`,
Thai and Arabic characters in the handwritten cells), so replacing those tables would be wrongful.

### Sensitivity (from scores.tsv)

| Variant | Blue Book | CDC | NBS | NOAA | Warren |
| --- | --- | --- | --- | --- | --- |
| rule | 0 | 27 | 0 | 0 | 7 (103, 549, 552–556) |
| English share < 0.4 | 0 | 16 | 0 | 0 | 5 |
| English share < 0.6 | 1 (33) | 28 | 1 (7) | 0 | 13 |
| English share < 0.7 | 1 (33) | 29 | 1 (7) | 0 | 21 (adds witness lists 520, 526, 527) |
| numeric share < 0.3 | 9 tables | 27 | 0 | 0 | 7 |
| no numeric guard | 20 tables | 27 | 0 | 0 | 8 (adds 885) |
| judged words ≥ 10 | 0 | 27 | 0 | 0 | 8 (adds 548) |
| uncovered ≥ 0.6 | 0 | 27 | 0 | 2 (139, 934) | 8 (adds 551) |
| uncovered ≥ 0.3 | 0 | 27 | 0 | 3 | 15 |
| uncovered rows ≥ 5 | 0 | 27 (FAA 1 added) | 0 | 0 | 7 |
| words test only | 0 | 25 | 0 | 0 | 6 |
| ink test only | 0 | 2 (20, 31) | 0 | 0 | 1 (103) |

FAA, Fed, Our Flag and DGA fail under no variant except FAA page 1 at five rows. The ink test's
nearest non-CDC pages are NOAA 139 and 934 (0.63, 0.65 uncovered: map and chart labels in
born-digital figures) and Warren 551 (0.61, handwriting). Among pages at or above 75% uncovered the
most uncovered rows is 27 (Blue Book 142, whose layer has 37 English words), which sets the 32-word
render bound.

## Review of the failing pages

### CDC comic (27 pages)

Pages 3, 5–12, 14, 18, 19, 21, 23–30, 32–34 and 37 fail the word test (11–79 English of 27–190
judged; the page-5 warning reads "only 23 of 77 words"); pages 20 (0 English words, 88% of the ink,
7 rows) and 31 (1 word, 79%, 13 rows) fail the ink test. Page 37 is the afterword, whose layer is
letter-spaced (`W e h o p e y o u e n j o y e d`); the others are dialogue. Every page's
recognized text was read against an 80-DPI render. Dialogue units (balloons and caption boxes, as
counted in `measurements/comic-panel-order/page-audit.tsv`) with reflowed text:

| | Units with text | Pages |
| --- | ---: | --- |
| Before (`ce2cf5b`, audit) | 124 of 231 | |
| After | 222 of 231 | |
| Recovered | 98 | page 7: 2 → 6, page 20: 0 → 3, page 31: 1 → 11, page 33: 4 → 13, page 10: 3 → 12 |
| Still missing | 9 | sound-effect balloons on 9, 10, 11, 25, 31 (`UUURRRR!`, `URRK!`, `URP!`, `GARRR!`, `GLURP!`), `!!` on 14, two units on page 22 and `MEEW!` on 35 (unflagged native layers) |

Page 5 now reads `IN OTHER NEWS, SEVERAL PEOPLE HAVE BEEN HOSPITALIZED AFTER A STRANGE VIRUS BEGAN
SPREADING RAPIDLY THROUGH THE SOUTHEAST...`; page 7 `MAN I FORGOT I HAD THIS. IT USED TO BE MY
DAD'S.`; page 20 `I AGREE. I'VE CALLED EVERYONE IN ON THIS ONE. THEY'RE WORKING 'ROUND THE CLOCK.
EXCELLENT. LET ME SHOW YOU SOMETHING DR, GHOSH HAS BEEN WORKING ON...`. Recognition errors remain
(`MAXP`, `ZSNI`, `COC`, `OUST` for `JUST`), short exclamations come back in Cyrillic look-alikes
(`НИН?!`, `ОКДУ, МАУВЕ NOT`, `УДУУ!!`), the printed checklist in page 7's art becomes headings, and
sound effects become headings (#18). Unflagged comic pages 4 (0.60 English), 22 (0.57) and 35 (all
English, one sound effect missing) keep their layers.

### Warren (7 pages)

- 549, 552, 553, 554, 555, 556: Parkland Memorial Hospital admission notes (Commission Exhibit 392),
  handwritten. The layer is noise (`--mmiktmiA^ jMyLEil mPTSW`, 8–17 English of 23–55). The probe's
  recognition reads the printed form (`PARKLAND MEMORIAL HOSPITAL`, `ADMISSION NOTE`, `DATE AND HOUR`,
  `COMMISSION EXHIBIT No. 392-Continued`, dates such as `22 Nov 1963`) and some handwriting; the
  handwriting is still mostly wrong, with stray Arabic and Cyrillic letters. Not wrongful: nothing
  readable is lost.
- 103: Commission Exhibit 2215, a map with a photograph. The layer holds only the caption and folio;
  16 text rows (87% of the ink) are map labels. Recognition keeps the caption and adds the labels
  (`VIEW OF TRIPLE UNDERPASS FROM LOCATION ON ELM STREET`, `TEXAS SCHOOL BOOK DEPOSITORY`, `HOUSTON`,
  `MAIN`, `COMMERCE`) as prose beside the source-page reference. Borderline rather than wrongful: the
  layer was correct but incomplete, and the replacement loses nothing.

## Default-lane comparison

`tools/run_corpus_regressions.py`, one case per call, with the capability probe (`--environment-probe`)
and both CLIs; `tools/compare_conversion_runs.py --allow-different-converters --detail`. Final run on
`f8a0a7a`:

| Case | Contract | Changed pages | Notes |
| --- | --- | --- | --- |
| CDC | pass (59 checks) | 30: the 27 failing pages, plus 13, 15 and 39 (markup only) | `recognizedPageCount` 9 → 36; heading levels are ranked over the whole book, so page 39's checklist title goes `h3` → `h6` and OCR pages 13 and 15 change level; 24 pages' navigation entries change; 7 pages only shift paragraph ids; the 9 pages OCR'd in both runs keep 56 words |
| Blue Book | pass | 0 | |
| Census | pass | 0 | 17 OCR pages, 5,248 words in both |
| NBS | pass | 0 | |
| DGA | pass | 0 | |
| FAA | pass | 0 | |
| Fed Explained | pass | 0 | |
| Our Flag | pass | 0 | |

The same eight comparisons on `ce2cf5b`, `ec22aff` and `a4b0f30` gave the same result (CDC's 30
pages, nothing elsewhere). The new CDC contract fails on each baseline conversion with 42 errors on
all seven contract pages (5, 7, 14, 20, 23, 31, 34). The two documents added in `156eaf3` (the pro se
complaint form and the NASA paper) have no image-backed page, and re-surveying every book except
Warren on `9ec0608`, and Warren itself, reproduced [scores.tsv](scores.tsv) byte for byte.

Under a loaded machine one `a4b0f30` candidate run reported `ocrFailed` on CDC page 8 (the other 26
pages recognized). The warning is therefore written after recognition: that page's message now
ends "The existing text was discarded, but OCR of the page image failed or found no text, so the page
is preserved as an image." instead of claiming a replacement.

## Cost

Alternating runs of the two CLIs:

| Book | Baseline | Candidate | Change |
| --- | --- | --- | --- |
| CDC, final (3 pairs) | 7.7–11.4 s, user 6.3–8.8 s, RSS 373–393 MiB, footprint 229–244 MiB | 12.8–16.3 s, user 8.9–10.2 s, RSS 419–437 MiB, footprint 326–333 MiB | about +5 s (+55–65%) and +45 MiB RSS, +95 MiB footprint for 27 more recognized pages |
| CDC, `ce2cf5b` (3 pairs, quieter machine) | 7.6–8.5 s, RSS 371–383 MiB, footprint 229–231 MiB | 11.5–12.8 s, RSS 422–428 MiB, footprint 326–332 MiB | +4.2 s (+53%) |
| Blue Book, final (2 pairs) | 37.4–41.4 s, user 35.5–36.4 s, footprint 156–162 MiB | 36.2–37.8 s, user 34.5–35.9 s, footprint 243–264 MiB | time within noise; peak footprint up to +100 MiB in this pair |
| Blue Book, `ce2cf5b` (2 pairs) | 33.6–34.9 s, footprint 160–247 MiB | 35.1–36.4 s, footprint 230–253 MiB | +1.5 s (+4%); footprint not separable from noise |
| Warren full book, `ce2cf5b` (1 pair, `--maximum-output-bytes unlimited`) | 386 s, user 364 s, RSS 1,041 MiB, footprint 351 MiB | 409 s, user 382 s, RSS 1,108 MiB, footprint 508 MiB | +22 s (+6%), +157 MiB footprint; 17 recognized pages instead of 10 |
| Warren full book, final (1 pair, 21 other converters running) | 1,019 s, user 707 s, RSS 1,026 MiB, footprint 328 MiB | 975 s, user 742 s, RSS 1,090 MiB, footprint 491 MiB | user time +35 s (+5%), +163 MiB footprint; the same seven pages report `implausibleTextLayer` and are recognized |

The ink test renders 25 Blue Book pages (about 70 ms each), 76 Warren pages (about 0.5 s each,
mostly image decoding) and 6 CDC pages; the rest of the CDC and Warren increase is recognition of
the 27 and 7 replaced pages. The CDC lane's RSS gate (512 MiB) passes at 436 MiB.

## Gates

- `swift test`: 707 tests pass (eight in `TextLayerPlausibilityTests.swift`).
- `scripts/check-all.sh --fast` on the final tree: pass (707 Swift tests, 230 Python tests including the
  generated-count check after `tools/update_doc_counts.py`, six fixture conversions, 14 policy conversions
  including `--ocr keep-image-backed`, 22 rejection cases, repeat-run identity).
- Negative controls: with `TextLayerPlausibility.judge` forced to return nil, both end-to-end tests and
  the render-count test fail (5 issues); with the digit guard at 1.1, the Blue Book 149 and Warren 885
  controls fail (4 issues).
- Corpus lane, one case per call: all eight cases above pass with the candidate.

## Limits

- English only; a lexicon from the operating system, whose vocabulary may change between OS versions and whose presence on iOS was not measured
  (as Vision's transcription can, #94). Proper names and abbreviations are neutral, so a layer of
  garbled capitalized words (`Asbanolllical`) is not counted as damaged.
- A garbled layer with at least a fifth of its tokens holding digits is never judged by words; a
  sparse layer with 32 or more English words is never rendered.
- The ink test cannot see text in artwork that is not glyph rows on clear background, text under
  2.5 pt, or loss spread over fewer than seven rows.
- Replacement is all or nothing per page: recognized text replaces native styles, structure tags and
  reading order, and brings recognition's own errors.
