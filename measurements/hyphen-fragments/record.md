# Hyphenation fragments in the book vocabulary (#101), and off-page paints in fixture capture (#99)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLIs, six-agent
host load. Baseline: `9884ed6`, built from `git archive 9884ed6` into a scratch tree (release
SHA-256 `783c142a…`). Candidate: `9884ed6` plus this working tree (release `b5a0bf19…`). The tree
was then fast-forwarded to `bc5eb8c` (#94, OCR request options only), and `swift test` and
`scripts/check-all.sh --fast` were rerun there. No public API or default changed.

## #99: capture-layout-fixture aborted on FAA pages 474 and 475

**Cause.** Both pages carry one two-page illustration placed across the spread. Its marks lie
wholly off each page: 315 paints on page 474 sit right of the 594-pt page (for example
`(889.40, 380.22, 22.77, 17.97)`), and page 475's sit left of it (`(-377.23, 460.37, 102.84, 91.45)`).
`GraphicsReader.read` intersected every paint with the crop box (crop box = media box
`0 0 594 774`). A disjoint intersection is `CGRect.null`, `(inf, inf, 0, 0)`, so `result.paints`
held hundreds of null rectangles. The tool writes `paints` since #54, and `JSONSerialization`
raised `Invalid number value (infinite) in JSON write`. `lines`, `regions` and attributed-line
bounds were finite (d63bbbc had already guarded attributed-line bounds).

**Conversion effect.** None. Every current reader of `paints` skips null rectangles
(`clusters`, and `TintDetector.compose` filters `finite` first). The FAA lane below compares
identical.

**Fix.**
- `GraphicsReader.read` drops a paint whose crop-box intersection is null, at the source. A paint
  overhanging the edge keeps its visible part as before.
- `tools/capture-layout-fixture.swift` walks the payload before writing. Any other non-finite
  number stops the capture with its JSON path. With the unfixed reader it reports
  `Non-finite geometry cannot be captured: fixture.paints[12].rect[0] = inf` (474) and
  `fixture.paints[5].rect[0] = inf` (475).
- With the fix, both pages capture (exit 0). No fixture was recaptured.
- **Test.** `graphicsReaderDropsPaintsWhollyOffThePage` (in `TintedBoxTests.swift`) draws fills
  right of, left of, across and inside a 594 × 774 page. With the old `map` it fails its
  finiteness and rectangle expectations; the region-count control passes both ways.

## #101: fragments vouched for joins

`addVocabulary` recorded every word of every line, including the word opening a line after a
line-end hyphen. That word is the rest of a broken word (`timates`, `cations`). In NOAA page 553,
`…/community-resilience-es-` + `timates.html)` kept its hyphen with `uncertainHyphen`. #88's word
tier saw `es` and `timates` both as book words: `es` comes from DOI segments such as page 284's
`…/10.1021/es504293b`, and `timates` from this break's own continuation line. The page's link
annotation is `https://www.census.gov/programs-surveys/community-resilience-estimates.html`, and
`pdftotext` shows the same two lines.

### Survey

`FragmentSurvey.swift` is kept here and is not part of the package. To run it, copy it into the
test target (instructions in its header). It reads native lines per page with hidden text removed
and no OCR, and builds the old vocabulary (every word) and the new one
(`LayoutReconstructor.addVocabulary`). Per word it counts line-start continuations after a hyphen
versus other occurrences. It then joins every consecutive line pair with the real
`LayoutReconstructor.join` under both vocabularies, carrying the text after the last space so a
multi-line address stays whole, and lists every break whose text or warning differs. It also lists
every address break, and each one the word tier removes. Full output: `survey.txt`.

**First candidate: drop the first word of every continuation line.** It changed 7 FAA and 6 NOAA
breaks, all prose compounds with the same text and a new warning. FAA pages 73, 122 (×2), 153 and
431 have `straight-and-` + `level`; page 399 has `gallons-per-` + `hour`, and page 449
`higher-than-` + `normal`. NOAA has `twenty-first-` + `century` ×6. The only evidence for their
compounds was a compound opening a continuation line (`straight-` + `and-level flight`). That
hyphen is unbroken on the line, so the compound is real evidence. #88's Fed `monetary-policy`
(page 46's `implementing-` + `monetary-policy.htm.`) is the same shape.

**Rule adopted.** Skip the word opening a line that starts lowercase after a line ending in `-`
or a soft hyphen, unless that word holds a hyphen. The same letters seen anywhere else still count,
so a word is dropped only when every occurrence is a continuation. The rule is per page, as
collection is (a page's first line is never a continuation). The vocabulary stays a `Set<String>`,
and its only readers are `joinOperation` and `addressHyphenOperation`.

| Document | Pages | Hyphen breaks (address) | Words dropped | Decisions changed |
| --- | --- | --- | --- | --- |
| faa-phak-8083-25c | 522 | 103 (0) | 2 (`braced`, `thirds`) | 0 |
| fed-explained-2021 | 135 | 473 (14) | 205 | 0 |
| gpo-911-2004 | 585 | 2,972 (1) | 562 | 0 |
| wallace-algebra-2010 | 489 | 340 (0) | 114 | 0 |
| scotus-loper-bright-2024 | 114 | 913 (0) | 447 | 0 |
| usgs-mcs2025-copper | 2 | 0 | 0 | 0 |
| arxiv-replay-clocks-2023 | 12 | 35 (0) | 31 | 0 |
| gpo-our-flag-2003 | 56 | 14 (0) | 4 (`brush needed rectangular tally`) | 0 |
| dga-2025-2030 | 10 | 1 (0) | 1 (`dense`) | 0 |
| noaa-nca5-2023 (outside the gate, survey only) | 1,834 | 2,204 (368) | 502 | 1 |

**The one change, reviewed against the source.** NOAA page 553,
`…/community-resilience-es-` + `timates.html)`, goes from `…-es-timates.html)` with a warning to
`…-estimates.html)` with no warning. Evidence: `es` has 14 continuations and 26 other occurrences,
`timates` 1 and 0, and `estimates` 201 other occurrences. The link annotation confirms the join.

**Real words dropped.** A few real words appear only as continuations: Our Flag's four, DGA's
`dense`, FAA's `braced` and `thirds`. They are harmless. A dropped word matters only as a joined
word, or as a piece in the address word tier, and no break in the survey consults one.

**#88's word tier.**
- **Fed 27** (`communi-` + `cations.htm`) no longer needs the allowance for one non-word piece:
  `cations` is dropped, so neither piece is a word.
- **NOAA 553** does need it: `es` stays a word from DOI segments.

The allowance therefore stays, and the tier is unchanged.

**Limits.** The survey joins consecutive native lines, not the blocks layout builds. Joins across
pages, columns reordered by layout, tables and footnotes are covered by the lane comparisons
below, for the four gate books only. OCR pages are not surveyed.

## Tests

- **`HyphenFragmentTests.swift`** (4 tests):
  - Collection: continuation words are dropped, including after a soft hyphen, and the other
    words on those lines are kept.
  - Controls: words seen elsewhere, ordinary and capitalized line starts, a compound opening a
    continuation line (FAA `straight-` + `and-level`, joined silently), and a new page.
  - Reproducer: new fixtures `noaa-553` and `noaa-284`, captured with the fixed tool from source
    `1942cbf3…`. Page 553 reads `…-estimates.html) and emerging`, and the break adds no warning.
  - Decision controls: Fed 27 still joins, Fed 46's `page1-` + `econ/` is kept with a warning, and
    the prose joins are unchanged.
- **`AddressHyphenTests.fedPage36…`**: its vocabulary assertion now expects no `econ`, which only
  opens the line after `page1-`. Its page 36 and 46 text and warning expectations are unchanged
  and pass.
- **Negative control:** with collection bypassed, 9 reproducer expectations fail: `es`, `cations`
  and `ience` present, `timates` present, the NOAA text (×2) and join, Fed's `econ` assertion,
  and Fed 27's vocabulary check. All controls pass.

## Before and after

Release CLIs, library defaults, `tools/run_corpus_regressions.py` one case per call with
`tools/probe-raster-environment.swift`, compared by
`tools/compare_conversion_runs.py --allow-different-converters --detail`.

| Book | Baseline | Candidate | Changed pages, images, navigation, report fields |
| --- | --- | --- | --- |
| fed-explained-2021 | pass | pass | none |
| gpo-911-2004 | pass (191 checks) | pass | none |
| wallace-algebra-2010 | pass | pass | none |
| faa-phak-8083-25c | pass | pass | none |

The lane shows no text or warning change on these books, matching the survey. NOAA is outside
the gate and was not converted.

## Verification

- `swift test` on `bc5eb8c` plus this tree: 463 tests pass (5 new).
- `scripts/check-all.sh --fast`: exit 0. It covers 463 Swift tests, 204 Python tests, 6 fixture
  conversions, 13 policy conversions, 22 rejection cases and 8/8 concurrency processes.
- `git diff --check` is clean.
