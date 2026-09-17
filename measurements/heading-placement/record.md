# Headings beside trailing figures and wide section titles (#63, #73)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 release CLI, Xcode 27.0.
Baseline: branch tip `04efe85` (after #47/#56 column cuts and #69/#70 list-marker pieces); the
candidate is `04efe85` plus the working-tree change, merged forward onto `78a4ba1`, which changes
no library source. Converter SHA-256s and every EPUB hash are in `identity.txt`. Every conversion
used `--package-identifier urn:uuid:00000000-0000-4000-8000-000000000001` and
`--modification-date 2026-01-01T00:00:00Z`; EPUBs were deleted after hashing and dumping.

Corpus: *Pilot's Handbook of Aeronautical Knowledge* (`faa-phak-8083-25c`, SHA-256
`247929ca…95cb7`), with every other cached corpus document and the Warren excerpt as controls.

## What was wrong

**#63.** FAA page 33 sets `Selecting a Flight School` at the foot of its right column; the
section's first paragraph continues on page 34, and the page closes with three figures and
captions. `appendPage` joins that paragraph across the page and, by #45's rule, keeps the page's
trailing images and captions ahead of the joined paragraph. It moved only the paragraph, so the
output read *title, figure 1-24, caption, paragraph*. Pages 49 (`Human Factors`) and 201
(`Chapter Summary`) had the same shape. The issue's original symptom (the title appended to the
caption paragraph, observed on `20c78f3`) no longer reproduces at the tip: with the label rule
suppressed for those three titles (a scratch environment switch, since removed) page 49's title
joins its own body paragraph and pages 33/201 keep it as a separate paragraph; no caption absorbs
it. A caption can still reach a title in reading order, so the caption rule below closes that path.

**#73.** FAA section titles are 12-point Helvetica-Bold over 10-point Times body text, a ratio of
1.2, below the 1.25 heading threshold, so only #43's section-label rule promotes them. That rule
requires a mixed-case label to be at most 90% of the widest prose line in its column. Page 43's
`Crew Resource Management (CRM) and` is 226.2 pt against 237.1 pt prose (95%); its second line
(84%) cannot continue a label that was never accepted, and since #67 the tagged `P` group keeps the
two lines as one paragraph. Twelve more titles across the book fail the same way (below).

## Source evidence

`render-pages.swift` rendered pages 33, 43, 49, 201 and 370 at 100 dpi for review. The fixtures
`faa-{33,34,43,49,50,201,202}-layout.json` (captured with `tools/capture-layout-fixture.swift`) give
the geometry: page 33's title at x = 285, y = 468.6, 12 pt bold, its first body line 14.8 pt
below; the three captions open with an 8-point bold `Figure N.` run followed by 9-point italic
text, and wrapped caption lines start at 9 pt (Figure 5-15 on page 107, 5-62 on 138, 14-11 on 343).
Page 370's title sets `(EMAS)` alone on its second line.

## Changes

`LayoutReconstructor`:

- **Headings move with their joined paragraph** (`appendPage`). When a join moves the previous
  page's last paragraph past trailing images, captions or folios, the headings directly above that
  paragraph move with it. Footnotes still follow the paragraph (#40); nothing else moves.
- **Book-wide label styles** (`LabelStyle`, `labelEvidence(on:)`, `labelStyles(from:)`). The
  extraction pass (which already accumulates hyphen vocabulary per page) records the style — size
  and body size to the half point, and whether every run is bold — of each narrow section label on
  the page, measured as `blocks` measures them but ignoring lines inside painted graphics, margin
  bands and retained running heads, and excluding contents entries. A style seen on three or more
  pages is the book's label typography. `sectionLabels` then also accepts a line wider than 90% of
  the column's prose, but no wider than that prose, when its style is one of those; every other
  label test (size band, capital or digit start, no sentence punctuation, clear space or label
  continuation above, not a list, contents rule) still applies. The capital test looks past an
  opening bracket or quote, so `(EMAS)` continues its title.
- **Captions end at clearly larger type** (`blocks`). An open paragraph that is a figure or table
  caption ends at a line at least 15% larger than the caption line above it and at least 95% of
  the reflowable body size. A first attempt compared caption and line against the page body
  alone; it split the wrapped captions of figures 2-22, 5-15, 5-62 and 14-11, whose pages measure a
  9-point body from figure text, so the rule compares the line with the caption itself (8 → 9 pt is
  12.5%). That version also separated Figure 5-16's caption from body prose it had absorbed (9 →
  10 pt, 11%); the final rule leaves that page as it was.

`PDFReflowLibPipeline` accumulates the evidence during extraction and passes the styles to
`blocks`. No option, public API or warning changes.

## Results

Block dumps (`block-dump.py`) compare baseline and candidate EPUBs; `pair.sh` ran each document
sequentially, one per invocation.

**FAA** (`block-diffs/faa-phak-8083-25c.diff`, 36 changed lines; warnings, image, page and
reflowed counts identical):

- Pages 33, 49 and 201: the title now directly precedes its joined paragraph, after the figure
  and caption.
- Twelve titles that were paragraphs become `h5` headings, each listed in the book's contents and
  each 12-point bold: `Crew Resource Management (CRM) and Single-Pilot Resource Management`,
  `Decision-Making in a Dynamic Environment`, `Instrumentation: Moving into the Future`,
  `Superchargers and Turbosuperchargers`, `Outside Air Temperature (OAT) Gauge`, `Minimum Equipment
  Lists (MEL) and Operations With Inoperative Equipment`, `Aircraft Owner/Operator
  Responsibilities`, `Balance, Stability, and Center of Gravity`, `Transport Category Aircraft
  Performance`, `Electronic Flight Displays (EFD) /Multi- Function Display (MFD) Weather`,
  `Engineered Materials Arresting Systems (EMAS)` and `Latitude and Longitude (Meridians and
  Parallels)`. Three of them (`OAT Gauge`, `Balance, Stability…`, `Transport Category…`) had been
  the opening words of their body paragraph and are now separate from it.
- `Full Authority Digital Engine Control` was already a heading; its second line `(FADEC)`, a
  paragraph in the baseline, now completes it.
- The same title changes appeared between `b9efcc9` and `b9efcc9` plus this change, before
  #69/#70 landed.

**Other changes**, each the heading move above and each reviewed in context:

- 9/11 (`gpo-911-2004.diff`): `6.1 THE MILLENNIUM CRISIS` and `11.1 IMAGINATION` now follow the
  retained folio (`174`, `339`) rather than preceding it.
- The Fed (`fed-explained-2021.diff`): three headings now follow the page's `Original page N`
  reference image instead of sitting between it and their paragraph.
- Replay Clocks (`arxiv-replay-clocks-2023.diff`): `3 REPLAY WITH CLOCKS` and `7 SIMULATION
  RESULTS`, the same with the reference image.
- Census (`census-rrs2002-01-page-1.diff`): page 1's `RESEARCH REPORT SERIES` and
  `(Statistics #2002-01)` form one heading (the bracket rule). On the damaged-encoding pages 2–20,
  whose text is Vision OCR (`ocrUsed`), two lines the baseline already reads as headings move with
  a joined paragraph past page 6's reference image, and the OCR text itself differs between the
  two binaries while repeating exactly for each (two runs each). Built on `b9efcc9`, the candidate
  produces the identical EPUB and the baseline a third text, so these OCR pages are exempt from
  byte comparison, as in `measurements/reproducibility/record.md`.

**Byte-identical**: Our Flag, Loper Bright, NBS, USGS copper, Wallace's algebra, Dietary
Guidelines, Blue Book, CDC, USCIS Arabic, IRS 596 and the Warren excerpt. NOAA and the full Warren
report were not run.

## Verification

- **Corpus lane** on the candidate, one case at a time: FAA (118 content checks), Fed (127), 9/11
  (139), Replay Clocks (55) and Census (54) pass with EPUBCheck and memory budgets
  (`lane-summaries/`). The FAA contract gains 20 checks on pages 33, 43, 49, 201 and 370; the
  `04efe85` converter fails five of them, one per page
  (`lane-summaries/faa-phak-8083-25c-negative-control-04efe85.json`).
- **Swift tests** (`HeadingPlacementTests.swift`): the three FAA page pairs keep title and joined
  paragraph adjacent after the caption; a synthetic join moves only a heading directly above the
  paragraph; a caption closes at a larger title but keeps an 8 → 9 pt wrapped line; page 43's title
  is one heading only with the book style supplied; a wide line with sentence punctuation, one
  wider than the column's prose, or one in another style is still not a label; and pages 33, 49
  and 201 each supply the style, which counts only from the third page. Disabling each of the
  three rules in turn fails the tests that cover it.
- `scripts/check-all.sh --fast` passes on the merged tree: 355 Swift and 186 Python tests and the
  fixture conversions.

## Remaining

- A wide title in a style the book does not repeat on three pages (a short report, a one-off
  display face) is still a paragraph.
- Figure 5-16's caption on FAA page 159 still carries the body sentence set directly beneath it.
- Replay Clocks' `6 REPRESENTATION OF REPCL AND ITS` / `OVERHEAD` remain two headings; unchanged
  here.
