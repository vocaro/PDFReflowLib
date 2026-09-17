# Text the rendering never shows (#74, #85)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI. Work began on
`7c46377` and was merged forward onto `090cc70` (#84/#75, form tags and tagged titles) before the
lane; the before/after comparisons use a release CLI built at `090cc70` without this change.

| Binary | SHA-256 |
| --- | --- |
| `7c46377` baseline (negative control only) | `db7b595c8f21e97b333dc2d0e5ff1915ebd74e37125365b64cb40ec3fec2dc71` |
| `090cc70` baseline | `143a931859f5724992c6384f48ec2d7b4d61274bd7d74e0dbd71421f02aef4e6` |
| candidate (`090cc70` + this change) | `2412eb1ee787474566cbd973f426e0feedf2c959adbc3f5d1ed6be1b51294359` |

## Diagnosis

PDFKit's line selections include every shown glyph, and carry no paint order or clip.

- **#74, The Fed Explained page 8.** The chapter opener's content stream shows the running head
  (`vi`, then `The Fed Explained: What the Central Bank Does`, inside `/Artifact`) and only then
  paints `Im0`, a 1275×1650 CMYK JPEG scaled to 612×792 under `0 0.5 611.5 791.5 re W n` with
  `GS0` (`/BM /Normal /ca 1 /SMask /None /op false`), no image mask. The photograph hides the head;
  the title, pull quote and contents entries are drawn after it. Pages 14, 66, 88 and 116 draw
  their heads the same way, but furniture removal already took those; on page 8 it emitted two
  paragraphs above the chapter title.
- **#85, FAA handbook page 159.** Inside `/Figure <</MCID 12401>>`, `q 72 457.875 237 271.67 re W n`
  is followed by a text object at baseline 428.27 (9 pt) and 417.47: the caption `Figure 5-16. …`
  left in the placed artwork from an earlier edition. Both lines lie wholly below the clip, so
  they are never painted. The real caption `Figure 6-20. …` sits at baselines 441.94 and 429.44,
  so the hidden first line overlaps the visible second line 1.17 points lower and 3.5 points to
  its right, and PDFKit keeps them as two native lines. Several hidden shows are TJ continuations
  with no positioning operator of their own.

## Rule

`GraphicsReader` (internal additions only) places every text show while scanning, without decoding
glyphs:

- **Horizontal text.** The baseline is exact (text matrix, rise, CTM). The start is exact after a
  positioning operator (`Tm`, `Td`, `TD`, `T*`, `'`, `"`, or a leading TJ number, which is an exact
  displacement). Otherwise it is a lower bound: glyph advances are never negative, so only TJ
  adjustments and negative `Tc`/`Tw` (counted per byte and per 0x20 byte, scaled by `Tz`) can move
  the start left. Type 3 fonts leave the start unknown. The show also records where its run began
  (`chainStart`, the last known origin on the same line matrix).
- **Rotated, mirrored or vertical text** (`Identity-V`-style encodings, `WMode 1`) is a thick ray
  from its origin: 1.5 × font size either side, and a whole line when the start is unknown.
- **Clip.** Each show records an over-approximating clip bounding box, intersected down the stack
  and across form BBoxes. A clipping path with no points changes nothing, unlike the crop reader's
  `clip`, which is untouched.
- **Covers.** An image or a single-rectangle fill is a cover only when it cannot let what is
  beneath it show through. That requires fill alpha 1, a `Normal`/`Compatible` blend, `SMask
  /None`, no overprint, and a non-pattern colour space. The image must have no `SMask`, `Mask`,
  `SMaskInData`, `ImageMask` or `OC`, and the cover must be outside `/OC` marked content and
  transparency-group or optional forms. Its bounds are intersected with an under-approximating
  clip that stays exact only through single axis-aligned `re` clips (then `null`). Clipping text
  render modes 4–6 end exactness at `ET`.
- **Unplaceable pages.** Mode 7, a font set through `gs`, unbalanced text objects and cap overflow
  mark the page's placement unsupported, and nothing is dropped there. The new state operators do
  not consume the 100,000-operation budget, so no page newly falls back to an image.

`HiddenTextFilter.hiddenLines` (after `MarkedTextReader`, before `TintDetector`, skipped when the
page requires a page image or has synthetic style) drops a native line only when all of these hold:

1. A show with an exact origin starts inside the line (±0.75 pt), and every such show is hidden.
2. Every horizontal show whose baseline lies in the line's band (±25% of its height) and whose
   start lower bound is left of the line's right edge is hidden for the whole line rectangle
   (±1 pt). Hidden means disjoint from the show's clip, or contained in a cover painted after the
   show. One exception applies: a visible run that starts outside this line, inside another
   native line, on a baseline more than 0.5 pt from every hidden start here, belongs to that line
   (FAA 159's overprinting caption).
3. No visible slanted show's ray reaches the line.

Pages with unsupported drawing, unplaceable text or any invisible (mode 3) text are skipped
entirely, so inherited OCR layers stay with the unverified-text-layer logic. When covers would
hide at least half of a page's lines, the text is the image's own transcription layer, and only
the clip rule applies there. The CDC comic draws every balloon's lettering beneath the page artwork
that shows it (the survey below found 521 such lines, 80–100% of each page). Tagged groups that
lose a line get `lineCount` recomputed.

No warning code is added. Pages 14, 66, 88 and 116 of the Fed no longer report `furnitureRemoved`
for heads that are now omitted as hidden text; nothing else in any report changed.

## Survey: every English corpus page

`survey-hidden-text.swift` is compiled with the library sources except `EPUBWriter` and
`PDFConverter` (as `main.swift`, `-swift-version 6 -enable-bare-slash-regex`). It mirrors
`extractPage`: page-image pages are skipped, tags are applied, and the filter runs. `survey/*.tsv`
lists each dropped line with its tag, reason, rectangle and text. It was run on the merged tree for
every book below except NOAA, which was run on `7c46377` with the final rule; NOAA has no tagged
pages that `090cc70` changes.

| Book | Pages | Dropped lines | Pages | Skipped: invisible text | Skipped: placement |
| --- | ---: | ---: | ---: | ---: | ---: |
| The Fed Explained | 135 | 9 (cover) | 5 | 1 | 0 |
| FAA handbook | 522 | 2 (clip) | 1 | 0 | 0 |
| CDC comic | 42 | 0 (521 suppressed by the transcription-layer guard) | 0 | 0 | 0 |
| DGA, Our Flag, USGS, Census, Replay Clocks, 9/11, algebra, NOAA | 3,008 | 0 | 0 | 0 | 0 |
| Loper Bright, Blue Book, NBS, Warren | 1,353 | 0 | 0 | 1,337 (114/312/1/910) | 0 |

No dropped line carries a structure tag, and no page is emptied.

Every dropped line was reviewed against a `mutool draw` render:

- **Fed pages 8, 14, 66, 88, 116** (50 DPI, side by side): 9 lines. On page 8 they are `vi` and
  `The Fed Explained: What the Central Bank Does`. Page 14 has `6 The Fed Explained: …` fused, and
  pages 66, 88 and 116 have the folio (`62`, `84`, `112`) plus the title. No running head is
  visible on any opener. The titles, pull quotes and contents entries drawn over the photographs
  are all kept: they are painted after the cover.
- **FAA page 159** (100 DPI crop of the figure): only `Figure 6-20.` is painted, and the two
  dropped lines are the `Figure 5-16.` caption. The visible caption and every figure label are kept.

Development findings that shaped the rule:
- A first version refused every page with non-horizontal text, which skipped 147 FAA pages
  (rotated figure labels). Slanted shows became vetoing rays, and the count is now 0.
- Without the run-start exception, FAA 159 kept its first hidden line: the visible caption's
  second line admits itself on the unbounded right.
- Without the transcription-layer guard, CDC lost 521 lines and 26 pages became empty (OCR
  candidates, and the contract's page-5 `unverifiedTextLayer` would go).

## Before/after (corpus lane)

`tools/run_corpus_regressions.py --epubcheck /opt/homebrew/bin/epubcheck --environment-probe
<probe> --execution-context host-terminal --case <id>`, one case per call, baseline `090cc70` then
candidate. Next, `compare_conversion_runs.py --allow-different-converters`, and `compare-pages.py`,
which separates pages that differ only by the book-wide paragraph ordinal from real changes. The
summaries are in `lane-summaries/`, and the EPUBs were deleted after recording.

| Case | Baseline `090cc70` | Candidate | Real page changes | Images | Report |
| --- | --- | --- | --- | --- | --- |
| fed-explained-2021 | FAIL 138 checks: `Page 8: unwanted text 'The Fed Explained: What the Central Bank Does'` | PASS 138 | page 8 only (122 more pages differ only by paragraph ordinal) | identical | `warnings`: 4 fewer `furnitureRemoved` (pages 14, 66, 88, 116) |
| faa-phak-8083-25c | FAIL 202: `Page 159: unwanted text 'Figure 5-16'` | PASS 202 | page 159 only (354 ordinal-only) | identical | identical |
| dga-2025-2030 | PASS 19 | PASS 19 | none | identical | identical |
| cdc-zombie-pandemic-2011 | PASS 11 | PASS 11 | none | identical | identical |
| gpo-our-flag-2003 | PASS 67 | PASS 67 | none | identical | identical |

The `7c46377` negative control (`fed-explained-2021-negative-control-7c46377.json`) fails only the
new page-8 absent-text check. Pinned CLI conversions of the Fed
(`--package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 --modification-date
2026-01-01T00:00:00Z`) differ only in `chapter-1.xhtml`, where `<p>vi</p>` and `<p>The Fed
Explained: What the Central Bank Does</p>` are removed and the title's anchor becomes
`heading-8-0`, and in the matching `nav.xhtml` link.

Page 8 now reads `1 Overview of the Federal Reserve System` (h3), then the quote, then the
contents entries. Page 159 keeps `Figure 6-20. … trim tab.` as its own paragraph apart from
`control pressures that may exist…`.

## Reproducer and controls

`Tests/PDFReflowLibTests/HiddenTextTests.swift` has 9 tests and 22 cases:

- `textPaintedBeneathAnOpaquePageImageIsNotReflowed` (Fed 8 shape, through the pipeline): the head
  is dropped, the title is the first block, and the warning is kept.
- `textWhollyOutsideTheClipIsNotReflowed` (FAA 159 shape with unpositioned continuations): both
  caption lines are dropped, and the label inside the clip is kept.
- `aClippedLineOverprintingAVisibleCaptionOnAnotherBaselineIsHidden`: FAA 159's native line
  rectangles and baselines. Controls: a visible run starting inside the candidate line, or on its
  baseline, keeps it.
- `textThatCanBeSeenIsKept` (14 cases): text over the image; translucent, multiplied, soft-masked
  (gs), masked (image `SMask`), stencil, slanted and smaller images; a triangular clip; a clip that
  contains the text, or that the text only partly leaves; invisible mode 3 text beneath the image;
  `/OC` content; a pattern fill.
- `anOpaqueFillOverTextHidesIt`: white and blue opaque fills hide; the same fill at `ca 0.5` does not.
- `aTextLayerBeneathTheImageThatShowsItIsKept`: all prose beneath the image is kept with its
  warning; a clip still hides on such a page.
- `rotatedVisibleTextKeepsTheLinesItCrosses`, `graphicsReaderPlacesTextShows` (rise, TJ adjustment,
  negative `Tc`, leading TJ number, path clip bounds), and
  `removingAHiddenTaggedLineKeepsItsGroupCountTrue`.

Mutations (applied together in one run, then restored; each failing test belongs to exactly one
mutation): skipping the pipeline call fails both pipeline reproducers; dropping the run-start
exception fails the overprinting-caption test; dropping the transcription-layer guard fails the
CDC-shape test. No other test failed.

Contracts (`corpus/regressions.json`, 1012 → 1016 checks):
- Fed page 8: `absentText` for the running head, plus `orderedText` title → quote.
- FAA page 159: `absentText` `Figure 5-16`. The #82 `distinctParagraphs` pair now names the real
  `Figure 6-20.` caption (#82 had pinned the hidden caption as a paragraph).

## Verification

- `swift test`: 402 tests pass (393 at `090cc70` plus 9).
- `scripts/check-all.sh --fast`: exit 0 (402 Swift, 186 Python, 6 fixture conversions, 13 policy
  conversions and 22 rejection/cleanup cases, fixture repeat-run identity).
- Corpus lane: see the table above.

## Limits and defects to file

- The rule cannot see through fills that are not a single rectangle, shadings, strokes or glyphs
  used as covers. It also misses text hidden by a clip whose bounding box still meets the line, or
  a line PDFKit merges with visible text. All of these keep text, as intended.
- The transcription-layer threshold (half of the page's lines) is a heuristic. A page where a
  photograph hides most of a small amount of real leftover text keeps that text.
- `tools/compare_conversion_runs.py` reports every later page as changed when a paragraph is
  removed, because page records include book-wide paragraph ordinals (`paragraphIDs`). It is a
  tool limitation worth filing: the report cannot distinguish a one-page change from a book-wide
  one.
