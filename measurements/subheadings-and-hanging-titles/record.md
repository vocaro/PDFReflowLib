# Body-size sub-headings, captions that leave their alignment, hanging title lines (#76, #82, #83)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 release CLI, Xcode 27.0.
Baseline: `7a29c09` (#81). The candidate is `7a29c09` plus the working-tree change; the same library
change was first measured on `5bf5e59` (`cand3`), and FAA's #81 page changes are identical with and
without it. Converter, probe and EPUB hashes are in `identity.txt`. Every conversion used
`--package-identifier urn:uuid:00000000-0000-4000-8000-000000000001` and
`--modification-date 2026-01-01T00:00:00Z`; EPUBs were deleted after hashing, dumping and inspection.

Corpus: *Pilot's Handbook of Aeronautical Knowledge* (`faa-phak-8083-25c`, SHA-256 `247929ca…95cb7`),
*Replay Clocks* (`arxiv-replay-clocks-2023`) and the 9/11 report (`gpo-911-2004`), with the other
English corpus documents as controls.

## What was wrong

**#76 — sub-headings run into their paragraph.** FAA sets two tiers of sub-heading below its
12-point Helvetica-Bold section titles: 10-point Helvetica-Bold (`Radius of Turn`, `Climb
Performance`, `Pulse Oximeters`) and 11-point Times-BoldItalic (`Fixed-Pitch Propeller`, `Balance
Tabs`, `Effect of Pressure on Density`), both over 10-point Times body text. Each sits on its own
line 12.4 points below the previous paragraph and 0.9 points above its first body line, flush with
it. The heading threshold (1.25 × body) and #43's section-label band (from 1.15 × body) both exclude
them, so nothing marked them as labels. On pages 91 and 199 the source's structure tags put each
sub-heading in a `P` group of its own, which kept it a separate (untitled) paragraph; pages 136, 156,
159, 165 and 262 have no usable tags (`structureFallback`), so spatial reconstruction joined the
line to the paragraph beneath it at ordinary leading. The difference was tags, not geometry: the
probe (`tools/probe-lines.swift`) shows identical sizes, gaps and edges on all seven pages.

**#82 — `Figure 5-16.` absorbs body text (FAA page 159).** The rendered page shows only
`Figure 6-20.` under the trim-tab figure. `mutool trace` finds the `Figure 5-16. The movement of
the elevator…` glyphs (Myriad-Bold, 9 point, x = 75.49, baseline 428.3) inside the placed figure's
`Figure` structure element, under a clip path covering y 457.9–729.5: a caption left in the placed
artwork from an earlier edition, clipped out and never painted. PDFKit still extracts it. Its second
line is followed 2.8 points lower by body text (`control pressures that may exist…`) at 10 points,
x = 72. The caption-to-body step is 11% (9 → 10 points), below #63's 15% rule, and the gap is no
larger than wrapped caption lines leave (1.6–2.3 points), so the text joined the caption.

**#83 — `6 REPRESENTATION OF REPCL AND ITS` / `OVERHEAD`.** acmart hangs the second line under the
title text past the number: first line x = 53.8, second x = 70.3 (16.5 points in, 10.9-point type).
#55's `stacksUnderHeading` accepts a shared left edge, centre or right edge within 0.6 em; these
differ by 16.5, 60 and 136 points. Vertical leading, size, sentence and numbered-line conditions
all passed; only alignment failed. The 9/11 report does the same at 12 points with an 18.1-point
hang (`3.2 ADAPTATION—AND NONADAPTATION—IN THE` / `LAW ENFORCEMENT COMMUNITY` and seven more). The
#55 synthetic test set its second line at x = 60, on the first line's edge, so it did not see this.

## Changes

`LayoutReconstructor` only; no option, public API, warning or default changes.

- **Sub-heading tier** (`sectionLabels`, `labelEvidence`). A line set below the label band, from
  0.95 to 1.15 × the reflowable body, is a label when every run is bold, its `LabelStyle` is one the
  book repeats (three or more pages, the #73 table), it is no wider than 90% of its column's prose,
  it starts with a capital or digit and has no closing sentence punctuation (the existing tests), it
  has clear space above it (0.8 × body; no continuation of a label above), and a paragraph opens
  directly beneath it: the nearest line below is within 0.8 × body, starts within 0.5 × body of the
  label's left edge, is wider than the label, is at body size (±10%) and is not all bold. The
  extraction pass records these styles in the same table (`recordingSubheadings`); headings keep
  their own size, so `rankHeadingLevels` ranks both FAA tiers below the 12-point titles (h6 under
  h5). Tagged pages 91 and 199 now agree: #67's rule reads a `P` group set in heading typography that
  introduces its paragraph as a heading.
- **Row pieces stay near each other.** The #55 join of a heading row PDFKit split at a gap now
  requires the next piece to start within 3 em of the previous piece's end. Without it, FAA page 340
  (whose columns are already read interleaved) merged its two column titles `Runway Safety Area` and
  `Runway Safety Area Boundary Sign`, which the new tier made headings, into one.
- **Captions end where alignment leaves them** (`blocks`). An open figure or table caption also ends
  at a body-size line (≥ 0.95 × reflowable body) at least 5% larger than the caption line above it
  when the line shares neither that line's left edge nor its centre (each more than 0.25 × body
  apart). FAA's wrapped captions keep their edge exactly (x = 36.0/36.0, 36.6/36.6, 72.0/72.0), so
  8 → 9-point wraps stay whole.
- **Hanging title lines** (`stacksUnderHeading(hanging:)`, `continuesHeading`). When the heading so
  far is a single line opening with a section number (`6`, `3.2`), the next line may instead start
  past that line's edge by more than 0.6 em and by no more than 0.6 em per character of the number
  plus one em for its space. All other #55 conditions still apply, including the refusal of a line
  that opens its own dotted number. A first draft estimated the indent from the number's share of the
  line's characters; it accepted Replay and one 9/11 title but missed seven (digits and spaces are
  narrower than capitals), so the bound replaced it.

## Results

Block dumps (`tools/one.sh`, from `measurements/heading-placement/block-dump.py`) compare the
baseline and candidate EPUBs, one document per invocation. `tools/split_check.py` classifies each
difference as a retag or a split whose concatenated text is unchanged.

**FAA** (`block-diffs/faa.diff`; headings 203 → 785; report fields identical):

- 582 headings added, none removed or changed, all h6 (`block-diffs/faa-added-headings.txt`):
  310 existing paragraphs retagged as headings (sub-headings the tags or geometry already kept
  apart, as on pages 91 and 199) and 223 paragraphs split into heading and paragraph (the #76
  symptom). No hunk changes text.
- Six hunks move text: `External Resources` (62), `Turbojet` (180) and `Enhanced Flight Vision
  System` (450) were paragraphs before a page's trailing figure; as headings they now move with
  their joined paragraph past the figure and caption (#63).
- Page 159: `Figure 5-16. … elevator trim tab.` is one paragraph; `control pressures that may exist
  …` opens the next.
- Page 340: `Runway Safety Area` and `Runway Safety Area Boundary Sign` are two headings (with the
  row guard; `cand1` without it merged them).
- Reviewed: the full list of added headings was read (each is a title in the book's contents or a
  sub-heading of one); the six moved hunks, page 340 and the less obvious titles were read in their
  dump context: `Omnidirectional` (page 353) is a sub-heading of `Taxiway Lights`; `Step 1` (page
  401) is a real sub-heading on a page whose columns the baseline already reads interleaved,
  unchanged here.
- Caption survey (`tools/survey.py`: paragraphs opening `Figure N-N.` longer than 160 characters or
  with more than two sentences, then a sentence opening in lowercase): the baseline has 28 such
  captions and one continuation, page 159; the candidate has 27 and none.

**9/11** (`block-diffs/911.diff`; headings 133 → 125): eight two-line section titles are now one
heading each — `2.4 … DECLARING WAR ON THE UNITED STATES (1992–1996)`, `3.2 … LAW ENFORCEMENT
COMMUNITY`, `3.3 … FEDERAL AVIATION ADMINISTRATION`, `3.5 … AND THE DEFENSE DEPARTMENT`, `4.1 …
KENYA AND TANZANIA`, `12.2 … AND THEIR ORGANIZATIONS`, `13.2 … INTELLIGENCE COMMUNITY`, `13.5 …
IN THE UNITED STATES`. Text unchanged.

**Replay Clocks** (`block-diffs/replay.diff`; headings 24 → 23): `6 REPRESENTATION OF REPCL AND ITS
OVERHEAD` is one heading; the other 16 section headings are unchanged.

**Byte-identical** (7a29c09 vs candidate): The Fed Explained, Wallace's algebra. (5bf5e59 vs `cand3`,
the same library change): Dietary Guidelines, Our Flag, Blue Book, CDC, NBS, USGS copper, Loper
Bright. Census differs only on its `ocrUsed` pages 2–20, whose Vision text differs between any two
binaries (`measurements/reproducibility/record.md`); page 1 and every non-OCR warning are identical.
USCIS Arabic, IRS 596 (non-English), NOAA and the full Warren report were not run.

## Verification

- **Corpus lane**, one case per invocation with the shared raster probe (`lane-summaries/`): FAA (146
  content checks), Replay Clocks (59), 9/11 (142), Fed (127) and Wallace (92) pass on the candidate
  with EPUBCheck and memory budgets. `compare_conversion_runs.py --allow-different-converters`:
  Fed and Wallace pass with no changed page; Replay changes page 6 only; 9/11 changes pages 77, 91,
  100, 111, 126, 383, 425 and 441 (the eight titles); FAA reports 496 changed pages from page 19 on,
  because its page records key paragraphs by a book-wide counter that every added heading shifts —
  the block dumps above show 276 pages with changed blocks, all text-preserving. No image, page
  marker or report field changed in any case.
- **Contracts** (`corpus/regressions.json`, 35 new checks): FAA pages 91, 136, 156, 159, 165, 199 and
  262 require the sub-headings and their paragraphs, page 159 separates the caption from the body
  text, page 340 requires both column titles and forbids the merged one; Replay page 6 and 9/11 page
  91 require the one-line heading and forbid either half. The `7a29c09` converter fails 15 FAA,
  3 Replay and 3 9/11 checks (`*-base.json`); `cand1` fails only page 340's forbidden heading
  (`faa-phak-8083-25c-negcand1.json`).
- **Swift tests** on source fixtures captured with `tools/capture-layout-fixture.swift` (FAA 107, 136,
  156, 159, 343; Replay 6; 9/11 91; existing FAA 43, 91, 165, 199, 262):
  `HeadingPlacementTests` — each untagged page's sub-headings run into their paragraph without the
  book style and open it with it, with block text otherwise unchanged; pages 91/199 read the same
  spatially; the #73 wide title is unchanged beside the new styles; plain type, sentence punctuation,
  a prose-width line, a sub-body size, an indented, bold or distant line beneath, and missing clear
  space above each refuse the label; evidence records each tier from its own pages and a style counts
  from its third page; the titles rank above both tiers; page 159's caption ends at its own line
  while pages 107 and 343 keep every wrapped line, plus a synthetic 9 → 10-point step that continues
  on the caption's edge and ends off it. `AcademicFrontMatterTests` — Replay page 6 and 9/11 page 91
  join their hanging lines; an unnumbered title, an indent past the number's bound and a line
  opening `6.1` stay separate; two titles 3+ em apart on one row stay two headings.
  Disabling each rule in turn (`tools/mutate.sh`: sub-heading tier, style recording, caption
  alignment, hanging indent, row gap) fails the tests that cover it.
- `swift test`: 368 tests pass. `scripts/check-all.sh --fast`: Swift and 186 Python tests, six fixture
  conversions and the repeat-run identity check pass.

## Remaining

- A two-line body-size sub-heading is not recognized (its first line has no paragraph beneath it,
  its second no clear space above) and still runs into its paragraph; none was seen in FAA.
- A sub-heading at the foot of a column, whose paragraph opens in the next column or page, has no
  paragraph directly beneath it and stays as before.
- A hanging second line under an unnumbered first line, or under a row PDFKit split into number and
  title pieces, is not joined.
- FAA page 159's `Figure 5-16.` text is still emitted, now as its own paragraph beside the real
  `Figure 6-20.` caption; extraction does not drop text clipped out of the page (defect to file).
