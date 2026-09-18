# Feathered group boxes and one-line entries set apart by space (#181)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs, host
terminal. Date 2026-09-17. The work was done on `f3840f4` (the coordination tip, after #158's crop
seeding in `bff0a04`), and every measurement below is on that base.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `f3840f4` | `98696241939a6e87f44d071a677aed168812f0e7a7c9f9372a0154d0e1c75a97` |
| candidate | `f3840f4` plus this change | `07016b164fc9628b11cbf8564c60e62cf94243138b88176f9e5e4a4fc1521ad5` |

No PDF, EPUB or raster is committed. Five source fixtures were captured with
`tools/capture-layout-fixture.swift` on the candidate reader (`noaa-7`, `noaa-48`, `noaa-81`,
`noaa-343`, `noaa-1700`); they hold extracted text and geometry only. Tools in [`tools/`](tools/)
ran from a scratch directory; paths inside them are those of the run. The Swift survey tools compile
the library sources (minus `EPUBWriter` and `PDFConverter`) with the tool (`tools/build.sh`), as
#158's did.

## What #158 had already changed

Nothing on the issue's pages. #158 (`bff0a04`) changed 28 NOAA pages (4, 31, 32, 36, 42, 53, 65, 71,
79, 285, 351, 405, 411, 687, …; see its record), but page 48 was not among them: on `f3840f4` its one
crop, `[0 0 792 427.2]`, still took 35 lines and 297 of the page's 347 words, and every one of the
issue's four phrases was absent from the book's text. Page 1700's ten Technical Contributors, and
every other one-line author block, were still one paragraph. #158's backdrop rule did remove the
page's corner-art *image*; what remained was that image's transparency-group box (below).

## Page 48: the group box around the corner art

Source page 48 paints six footprints (`tools/cropsurvey.swift`, `GraphicsReader` on `f3840f4`):

| Paint | What it is |
| --- | --- |
| image `[0 0 792 248.7]` | the corner line art, one 4801 × 1623 image at 30% opacity, clipped to the page |
| unclassified `[0 0 792 256.7]` | that image's transparency-group box |
| fill `[70 445.4 722 543.9]` | the callout band (a tint) |
| fills `[65.5 263.3 380 378.1]`, `[65.5 67.3 380 252.1]` | the left column's two shaded panels |
| image `[409 173.1 729.5 406.1]` | Figure 1.5 |

InDesign wraps the corner art in a transparency group (`/Group`, alpha 0.3) whose `BBox`,
`[-151.4 -141.66 1018.6 256.717]`, is the art grown by its feather: eight points taller than what the
group paints. #158 made a form's box record no footprint where the form's own paints cover it
"within two points" and mark its widest paint `grouped`; eight points misses that, so the box was
recorded as an unclassified paint across the page's lower half. #158's backdrop rule removed the
image (the left column is set over it), but not the box, which is no image. The box then read as
solid ink over the lower left panel's lines, so that panel was no tint; it seeded a crop with the
figure, and whole-line expansion took the left column, its sub-heading, the figure's title, lead
and caption.

**Rule** (`GraphicsReader`, the form-box branch of `Do`; `GraphicsReader.fills`): a form's box is
covered where its paints lie within two points of it, as before, *or* cover at least nine tenths of
its area. A box that keeps more than a tenth of itself beyond its paints reaches past the object and
is still recorded (the #158 control, a 40-point paint in a 120-point box, covers 13%). On page 48 the
art covers 96.9% of the box; with the box gone, the lower panel is a tint and the only crop is the
figure's own, `[409 173.1 729.5 406.1]`, taking no line.

### Designs measured and rejected

- **Treating stroked or unclassified paints as backdrops** in `withoutTextBackdrops`, as images are.
  Measured on page 48 alone, where it fixed the crop, then dropped: the box is no picture under the
  text but a bounding box that should not have been recorded, so the reader's group rule is where
  the defect was, and changing that rule alone moves nothing outside NOAA's overview and the FAA's
  (unchanged) chapter openers.

## Contributor entries: one line each, set apart by space

Page 1700 sets its contributors one to a line on one edge, 21 points apart (7.7 points between
rectangles), and never wraps one; page 81's authors stand 16.5 points apart (3.2 points). The
recommended citation beneath each block wraps at 0.1–0.2 points. #134's `hangingEntryEdges` needs an
entry wrapped into a hanging indent, and #71's spaced-paragraph rule needs the paragraph's own leading
(none for a paragraph's second line) and a sentence end (an affiliation ends none), so every entry
joined the one above.

**Rule** (`LayoutReconstructor.spacedEntryEdges`, `edgeWraps`, `wrapGap`, `wrapEvidence`,
`bookWraps`; used by `opensHangingEntry` through `HangingEdge.spacing`):

- An edge's **wrap** is the least gap under a line reaching within one size of the edge's widest
  line, to the nearest line beneath it on the edge, when three lines reach that measure (as #157's
  measure asks). Where the edge has none, the **book's wrap** at that body size stands in: the median
  over pages of each page's median edge wrap, collected during extraction (0.15 pt at NOAA's 10-point
  body). Page 81's citation reaches its measure on two lines, page 1700's on one, and page 343 sets
  its citation overleaf; all three read the book's wrap.
- An edge **qualifies** when at least three lines on it stand at one even gap (within a tenth of a
  size of the first) at least a fifth of a size over the wrap, none of the run's upper lines reaching
  the measure. Lists, code, leader entries, wholly bold labels and lines outside the body's size are
  no evidence; a page over 2,000 lines has none.
- On such an edge a line opens the next entry by #134's ends-early test and only where it stands at
  least that fifth of a size over the wrap below the line above, so an entry's own wrapped line
  continues it.

NOAA's front matter (pages 6 and 7), freed from its crops by the group rule, lists its staff one to
an entry at ordinary leading and wraps an entry **1.8 ems** into a hanging indent, past the 1.5-body
drift a paragraph's lines may take, so each wrapped line became a paragraph of its own. **Rule**
(`continuesOpening`): on a #134 hanging edge, an entry's first line runs on into a line in the edge's
indent (up to 2.5 sizes) when the wrapped line opens with a letter, digit or bracket, neither line
sets arithmetic, three of the edge's lines that have a line hanging beneath them end within a size of
the widest (the entries' measure), and the wrapped line's first word would not have fitted after the
first line. Each guard was added for a lane finding: Pro Se page 3's `☐ Federal question` joined its
question and Wallace page 19's next worked step joined its annotation (first-character and
arithmetic guards); #147's `hangingLineNeedsSpaceAboveItsEntry` control (a lone reading-list entry,
its own evidence) and NOAA page 5's poem, whose couplets hang their second lines 1.8 ems in (measure
and full-line guards).

### Surveys

`tools/entrysurvey.swift` (book wrap first, then every page's spaced edges beyond #134's, with the
splits the ends-early and spacing tests would make; a superset of `blocks`, [entry-survey.txt](entry-survey.txt)):
99 NOAA pages, 40 of the 41 pages headed *Authors and Contributors* (page 1738's multi-entry block
holds two entries, no run), FAA 31, Wallace 23, Fed 5, magazine 1, DASC 2, arXiv 1, USGS 1, DGA 2
(no split). Only the lanes' changed pages below changed in output; the rest are split already by
other rules (list items, #162's references) or not read in that order.

## Before and after (`f3840f4` → candidate)

`tools/run_corpus_regressions.py`, one case per call, with one compiled probe for both sides, then
`tools/compare_conversion_runs.py --allow-different-converters --detail` (`tools/pair.sh`); each
side's EPUB deleted after its comparison. 61–81 GB free throughout. Every English case except Warren
(#5) ran.

| Case | Contract (base → cand) | Changed pages |
| --- | --- | --- |
| noaa-nca5-2023 | base fails 13 (the new checks), cand passes 42 | 97 with content changes; 957 more differ only in `headingRanks` |
| fed-explained-2021 | both pass 201 | 91 |
| usda-ars-agresearch-2012-11 | both pass 242 | 22 |
| wallace-algebra-2010 | both pass 288 | 74, 75, 163, 217 |
| ntrs-20190030725-dasc-2019 | both pass 246 | 6 |
| faa-phak-8083-25c, gpo-911-2004, dga-2025-2030, gpo-our-flag-2003, cia-blue-book-14-1955, cdc-zombie-pandemic-2011, nbs-jres-geltman-1977, arxiv-replay-clocks-2023, usgs-mcs2025-copper, scotus-loper-bright-2024, census-rrs2002-01, uscourts-pro-se-1-2016, ntrs-20200002975-gwl-2020, ntrs-20180003024-earthdata-slides-2018, ntrs-20210020887-techport-thm-2021 | both pass (560, 306, 96, 134, 10, 60, 64, 71, 51, 115, 74, 162, 286, 225, 72) | none |

The one NOAA check the baseline passes is page 1700's `Amy E. East, US Geological Survey`, which
the fused paragraph also contains; its distinct-paragraph checks fail.

### NOAA

- **Group rule** (`tools/cropsurvey.swift`, [crop-survey.txt](crop-survey.txt)): 53 NOAA pages,
  words inside crops 10,738 → 1,965, all in the landscape overview and front matter (pages 4–79),
  whose corner art is the same feathered group; FAA 16 chapter openers, 2,142 → 0, whose page-sized
  photograph keeps them page-image pages either way (no output change); nothing else in the English
  corpus. No page takes more words into a crop. 45 overview pages change in output; the book's
  reflowed words rise 123,473 → 128,504 ([noaa-words.txt](noaa-words.txt), `check`-style block text
  per changed page). Page 48 now reads its title, callout, `h6` sub-heading, both left-column
  paragraphs, the figure's title, the crop, and the figure's lead and caption.
- **Eight overview pages leave the page-image path** (25, 34, 45, 47, 49, 52, 68, 77): without the
  box their crops hold under a tenth of their words, so #117's `layoutComesApart` reflows them with
  no `unverifiedTextLayer` and no source-page image. Four hold fewer reflowed words than before,
  because a crop the page image made moot is now the page's image of that part: page 25's two shaded
  tables (493 → 388 words; its rows are fills the table reader does not read, now five region crops),
  page 27's table header row (212 → 206), page 47's last two right-column lines, taken by the corner
  art where its trimmed piece overlaps the painting (179 → 161), and page 77's running foot (279 →
  276, furniture).
- **Entries**: 40 contributor pages and their continuation pages (386, 693, 857, 987, 1052, 1167,
  1225, 1356, 1422, 1487, 1562, 1621) and the production team (1799) split one paragraph per entry,
  and each `Cover Art` label leaves the artist's name. Every split was read and falls between two
  entries.
- **Front matter** (pages 5–7): pages 6 and 7 reflow their staff lists instead of a crop, one
  paragraph per entry with its wrapped line.

### Other cases

- **Fed page 91** (Box 6.1's timeline): `…Fedwire, the world's first wire transfer system.` and
  `The Federal Reserve Banks begin operating their automated clearinghouse service.` become separate
  paragraphs (the 1918 and 1974 events); 1980 and 2003 still share one.
- **Magazine page 22** (index): entries on one edge split where a page number ends a line (`…Oct-2`
  / `Innovations for Pest Control in Produce, Jul-2`); the three columns still interleave (#153).
- **Wallace 74, 75, 163, 217**: a worked example's annotation column, one note per step at open
  leading, splits between notes (`Nicole is three times as old as Kristin.` / `Replace variables…`),
  never inside one.
- **DASC page 6**: `…invariant formulated in section V-A.` and the paragraph opening `Connection to the
  passing constraint (5.b):` are two paragraphs, as the source sets them.

## Tests and contracts

- `swift test`: 911 pass (eight new tests in `FeatheredGroupsAndSpacedEntriesTests.swift`).
  `scripts/check-all.sh --fast`: exit 0, including the generated doc counts.
- Source fixtures with the defect as a control: `noaa-48` (the four phrases leave the crop; with the
  group box as a paint of its own they are back inside it), `noaa-81`, `noaa-343`, `noaa-1700` (one
  paragraph per entry with the book's wrap, fused without it), `noaa-7` (wrapped staff entries whole).
  Synthetic: an in-memory PDF with a feathered group box and a box reaching past its paint; `fills`
  bounds; spaced edges refused at the citation's own leading, for two entries, uneven leading, a
  paragraph filling its measure at open leading, a larger body and bold labels; an entry's wrapped
  line at the wrap kept with it; hanging-indent continuations refused under a sentence end, three ems
  in, for a checkbox, a worked step, entries with no shared measure and a line broken short.
- Mutations ([mutants.log](mutants.log), `tools/mutate181.py`): 20 of 20 single-guard mutations fail
  at least one test, over this file, `HangingEntryTests`, `CropsOverRunningTextTests` and
  `ParagraphOpeningTests`. Five survived a first pass and three a later one; a control was added for
  each and it was rerun.
- Contract (`corpus/regressions.json`, noaa-nca5-2023): page 48 gains the sub-heading and four
  paragraph phrases (left column, second paragraph, figure lead, caption); page 1700 gains `Amy E.
  East` and two distinct-paragraph pairs; new pages 7 (a wrapped staff entry whole, distinct from the
  next), 81 and 343 (two distinct pairs each). The case's basis no longer excludes #181; the review
  file lists pages 7, 81 and 343. The baseline fails 13 of the 14 new checks.

## Cost

`GraphicsReader.fills` is one rectangle intersection per form box. `edgeWraps` runs once per page in
extraction (for `wrapEvidence`) and once in `blocks`, quadratic in the lines of one edge; pages over
2,000 lines are skipped. The continuation's measure is read only for a line in a hanging edge's
indent. Lane conversions (base → cand): NOAA 133.0 → 134.2 s and 988 → 976 MiB peak, FAA 56.4 → 52.3 s,
9/11 13.8 → 14.5 s, Fed 5.8 → 5.5 s, magazine 4.7 → 5.2 s. Wallace measured 27.1 → 35.0 s in that
lane while another agent's conversions shared the machine; alternating the two binaries twice on
Wallace gave 27.2 / 26.6 s user (base) against 27.4 / 26.1 s (candidate).

## Remaining gaps and follow-ups

1. **The widest entry of a spaced block still joins the next** (NOAA pages 343, 488, 568 and 610:
   `Stephen D. LeDuc, US Environmental Protection Agency, Office of Research and Development` /
   `David H. Levinson, …`). The ends-early test measures against the edge's widest line, which on a
   page is often that entry. Four pairs of about 700 entries. Expected: one paragraph
   each; needs the book's measure at that size, as the wrap has.
2. **Page 1738's two-entry *Authors* block** stays one paragraph: two entries are no run.
3. **NOAA page 5's poem** hangs each couplet's second line 1.8 ems in at a shared measure, so two
   more couplets join (the baseline already joined three of nine). Expected: verse keeps its lines.
4. **Page 69's photo credit underline reads as a table's sub-header** (`TableRegionDetector
   .underlinedColumnRegions`), and the region it grows takes 234 words of both columns into a crop;
   page 40 the same. The group box hid it on the baseline. Not changed here because the table reader
   is #150's.
5. **Page 25's shaded tables** are region crops now that the page reflows; their rows are fills the
   table reader does not read (#150's area as well).
6. **Page 47's corner art overlaps the painting**, so their crop takes the right column's last two
   lines (18 words).
7. **Page 48's figure lead and caption** read as one paragraph (`The US has warmed rapidly since the
   1970s. Figure 1.5. …`); the bold lead is its own block in the source.
8. **Front matter labels wrapped into the indent** (`Federal Steering Committee for the Fifth National
   Climate` / `Assessment`) and a wrapped entry after a line-long one (`Katie Reeves, …` / `Charles A.
   Brodine, …`) on page 6 still split or join wrongly.
