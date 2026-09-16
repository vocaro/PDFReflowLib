# Bold run-in section labels and unruled table notes (#60, #61)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 release CLI.
Baseline: repository `62877e6`; candidate: `62877e6` plus the working-tree changes below.
Source: *Mineral Commodity Summaries 2025: Copper*, `corpus/cache/mcs2025-copper.pdf`,
SHA-256 `348b1e224d830a51e6d35cf81343eead26a0cb2a4e74c474d699b7faed1b10e6`. Baseline converter
SHA-256 `b12628e4…e515fc` (built from `git archive 62877e6`), candidate `a3de1ed0…eecc419`.
No source PDF or full EPUB is committed.

## What was wrong

USGS copper page 2 ended in one run of prose and one run of table notes, neither of which the
reconstruction separated:

- `World Mine and Refinery Production and Reserves:` and `Substitutes:` were swallowed by the
  section above them, so page 2 carried the Events, COMEX and World Mine text in a single
  1,879-character paragraph and the World Resources and Substitutes text in a single
  690-character one. Page 1 merged `Import Sources (2020–23):` into the Recycling paragraph and
  `Government Stockpile:` into the Depletion Allowance paragraph.
- The nine table notes (`eEstimated. — Zero.`, `1Copper converted to refined metal…` through
  note 8 and its two continuation lines) stayed ordinary paragraphs, grouped four to a block by
  the short-line rule, with no `role="doc-footnote"` anywhere on the page.

## Source evidence

Read from `Tests/PDFReflowLibTests/fixtures/usgs-2-layout.json` (already committed) and
`usgs-1-layout.json`, and from the page rendered at 150 dpi with Poppler.

- **No rule is drawn above the notes.** All thirteen painted regions on page 2 are 1-pt rules
  (5 pt after `GraphicsReader`'s padding): four section-label underlines (`Events, Trends, and
  Issues:` 133.1 pt wide at the label's own extent, `World Mine and Refinery Production and
  Reserves:` 239.9, `World Resources:` 86.3, `Substitutes:` 58.5), four column-header rules
  under `2023 2024e 2023 2024e`, and five totals rules above the `World total (rounded)` row.
  Nothing is painted between the last body line (`… heat exchangers.`, minY 193.77) and the
  first note (maxY 183.32). The issue's premise of a drawn separator does not hold for this
  document; the notes are set off by white space and a type-size drop alone.
- **Lead-ins.** Each label is one `Arial-BoldMT` run at body size closing with a colon,
  followed by `ArialMT` body text on the same line — a run-in, not a heading. The body is
  10.08 pt on 11.04 pt leading in 13.76 pt PDFKit rectangles, so lines *inside* a paragraph
  report a box gap of −2.72 pt. Between sections the gap is 7.92 pt (page 1: 7.93 and 7.65),
  under the prose branch's `body * 0.9` = 9.07 pt threshold, which is why the paragraphs
  merged. The source therefore does add space — about 0.3 pt of paragraph spacing — but less
  than the rule required.
- **Sentence ends.** Page 1's Recycling section ends `… of the U.S. copper supply.` followed by
  a 6.48 pt raised `5`, so the line's last character is the marker, not the period.
- **Notes.** Note lines are 10.94 pt rectangles at zero leading (internal box gaps −0.14 to
  +0.23 pt), flush with the body column at x 45.36, and set off from the body by 10.44 pt.
  Their markers are raised runs (`e`, `1` … `8` at 5.04 pt, baseline offset +3.12) against
  7.92 pt note text, which native extraction already marks `.superscript`; because
  `TextLine.fontSize` is the first run's size, a marked note line reports 5.04 and the two
  unmarked continuation lines of note 8 report 7.92. Both are at most 90% of the body size.
  The running foot `U.S. Geological Survey, Mineral Commodity Summaries, January 2025` sits
  below the notes at body size, 6.46 pt clear of them; this two-page extract repeats it only
  twice, so `FurnitureDetector`'s three-page minimum keeps it.

## What changed

`Sources/PDFReflowLib/FootnoteDetector.swift`

- `Marker` (`number`/`letter`) replaces the bare `Int`; `noteMarker(of:)` admits a raised run of
  one to three digits or a single ASCII letter, and `marker(of:)` keeps returning only the
  number. A raised letter counts as a marker only beside a counted-up numbered series, so a
  page whose raised markers are only letters is still refused.
- `Layout` now carries an optional `separator` (the dash line to drop) and the note area's
  element `range`, rather than assuming the area runs to the last element.
- `layout` tries `ruled` — the existing dash-character separator, unchanged in its refusals —
  then `unruled`. `unruled` admits a block only when: the first raised marker on the page opens
  it and no earlier line carries one; at least three body-size lines establish a body size above
  it; the block sits directly under a body line; every line is at most 90% of the body size,
  shares one left edge within the body's own column, and follows at close leading; the gap above
  it is at least `body * 0.9` (the gap that already breaks a paragraph) and more than the
  block's own leading plus half its size; it holds at least two marked notes whose numbers count
  up; and at most two body-size lines — a page foot — follow it. A marker-less first line is
  never a continuation here: with no separator it is prose.

`Sources/PDFReflowLib/LayoutReconstructor.swift`

- `blocks` walks explicit body element indices instead of a prefix slice, so the elements after
  an unruled note block stay body text. A running foot below the notes keeps its place ahead of
  them, as captions and folios do.
- `opensSection` in the prose branch: a line whose first run is bold, closes with a colon or is
  set in capitals, and is followed by non-bold text on the same line opens a paragraph when the
  previous line ends a sentence, the line is at body size and flush with that line's left edge
  (within `body * 0.5`), and the gap is not negative and exceeds the leading the open paragraph
  has been wrapping at by `body * 0.2`. The sentence-ending character is read past closing
  quotes and brackets **and past a trailing raised numeric run**, so `… copper supply.5` ends a
  sentence. `previousGap` tracks the leading each line was attached at and is cleared on flush.
- A lettered note carries no `NoteKey`; only numbered notes do, so `NoteLinker` links page 2's
  raised `6` and `8` to notes 6 and 8 with return links, and the lettered `e` stays unlinked.

`tools/check_corpus_content.py` gains `distinctParagraphs` ({`first`, `second`}): both passages
must be paragraph text on the page and no paragraph may carry both. `paragraphs` matches a
phrase inside any paragraph, so it cannot see a lead-in swallowed by the paragraph above it.

## Verification

- `swift test`: 321 tests pass (314 at `62877e6`; `SectionLeadInTests.swift` adds five and
  `FootnoteTests.swift` two). `scripts/check-all.sh --fast`: 321 Swift tests, 166 Python tests
  (165 at `62877e6`), 8/8 concurrency trials, 6 fixture conversions, 13 policy conversions and
  22 rejection cases pass.
- Corpus lane (`tools/run_corpus_regressions.py`, `--epubcheck /opt/homebrew/bin/epubcheck`)
  with the candidate: `usgs-mcs2025-copper`, `scotus-loper-bright-2024`, `gpo-911-2004`,
  `faa-phak-8083-25c`, `fed-explained-2021`, `wallace-algebra-2010` and `gpo-our-flag-2003` all
  pass. USGS now runs 49 content checks, up from 40.
- Negative control: the same contract against the `62877e6` converter fails with nine errors —
  both page-1 `distinctParagraphs` pairs, two of the three page-2 pairs, the three `notes`
  phrases and both `noteLinks`. (The third page-2 pair, body against the first note, already
  held; it guards against a false footnote swallowing body text.)
- Before/after page comparison of every page's text, paragraph count, note-block count and
  image list for all seven books, both converted through the lane. Loper Bright (114 pages, 408
  paragraphs, 28 notes), 9/11 (585, 3,985), Wallace (489, 3,708), The Fed Explained (135, 713)
  and Our Flag (56, 552) are identical page for page. The tagged books' runs are comparable:
  `structureFallback` is 118 in both Fed runs, 37 in both Our Flag runs and 482 in both FAA
  runs, and no warning code's count changes in any book.

## Before and after

USGS copper, page 2: paragraphs 8 → 15 and note blocks 0 → 9. `World Mine and Refinery
Production and Reserves: … industry association reports.` (190 characters) and `Substitutes: …
heat exchangers.` (346) are now their own paragraphs; the Events paragraph drops from 1,879 to
1,688 characters and still carries the COMEX text, because that paragraph's opening line has no
bold label. The nine notes are emitted as `<div class="footnote" role="doc-footnote">` in source
order with their raised markers, note 8 holding its two continuation lines; the raised `6` after
`World Resources:` and the raised `8` after `3.5 billion tons of copper.` are `doc-noteref`
links to notes 6 and 8, which carry `doc-backlink` returns. Page 1: paragraphs 6 → 8, with
`Import Sources (2020–23): …` and `Government Stockpile: None.` split out. Page text, image
regions and warnings are unchanged on both pages.

FAA page 491 (glossary) is the only change outside USGS: paragraphs 23 → 25 with identical page
text. The source sets `ILS Category I:` through `ILS Category IIIC:` as five indented
`Times-Bold` run-in entries under `ILS categories.`; the baseline merged Categories II and IIIA
into Category I's paragraph and the candidate separates all five, matching the page as printed.

## Remaining gaps

- The premise that these notes sit under a drawn rule is not true of this document, so no
  graphics evidence is used. A page whose notes *are* ruled with a painted line, rather than
  dash characters, is still not recognized unless the white-space form also admits it.
- Only the bold run-in form of a section break is recognized. A section whose opening line is
  ordinary prose under the same sub-point spacing still merges: page 2's COMEX paragraph stays
  inside the Events paragraph.
- A page whose unruled note block is a continuation from the previous page with no marker of its
  own is refused, and `endsColumn` does not treat an unruled note block the way it treats one
  under a dash separator, so such a page could refuse a cross-page body join.
- A lettered note carries no `NoteKey`, so `eEstimated.` cannot be linked from the table that
  cites it; that table is preserved as an image.
