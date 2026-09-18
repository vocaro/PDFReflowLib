# Printed blanks, answer areas and outline depth (#197)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLIs.
Baseline: an unmodified release build of the coordination tip `9f45b17` (converter `3dae4641…`);
candidate: that tree with this change (`5256137a…`). Every corpus figure is
`tools/run_corpus_regressions.py`, one case per call, with one compiled raster/Vision probe shared
by both runs and `--execution-context host-terminal`, then `tools/compare_conversion_runs.py
--allow-different-converters` (receipts in `lane/`). No PDF, EPUB or
raster is committed.

## The three follow-ups #152 left

1. **Printed blanks.** `FormBlank` came only from AcroForm text and choice fields
   (`AnnotationEvidence.blanks`). A form printed to be filled in by hand has the same rules and no
   widget, so each rule stayed a graphic: a narrow one a crop, a wide one decoration. The
   Agricultural Research back cover's mailing coupon (`To stop mailing ______ ☐`, `To change your
   address ______ ☐`) is such a form: at `9f45b17` the two labels, their rules and the two drawn
   boxes were one 389×71-pixel crop, and the text carried neither label.
2. **Answer areas.** A field taller than two lines shares no row (`FormBlank.sharesRow`), so
   `joiningBlankRows` set nothing for it and its rule, excluded from the crop seeds, left no mark.
   Pro Se 1 has six: the caption's two name boxes (48 points, above `Plaintiff(s)` and
   `Defendant(s)`), and the space under II.A (68), 3 (65), III (90) and IV (87, at the top of page 5).
   The EPUB went from each prompt straight to the next section.
3. **Fixed outline depth.** `outlineSectionLabels` records depth 0 for Roman, 1 for capitals, 2
   for numbers, and `rankHeadingLevels` added that depth to the outermost tier's size level. An
   outline opening at capitals therefore ranked its `A.` sections one level below where the size
   scale put them, and its numbered parts two, for a Roman tier it never used.

## Changes

- `FormBlank.printed(paints:lines:fields:)` (`DocumentModel.swift`, new): a blank with no field.
  A thin rule (collinear pieces merged) that meets no other paint, at least three font sizes long,
  on the baseline of a row of type (the line's foot within half a font size above the rule's
  middle or a third of the line's height below it), with that row's text ending before it within
  ten font sizes or resuming after it within one, and nothing set over it. A rule is its column's,
  not a blank, where a line within six font sizes starts inside its span and ends within two font
  sizes (or 5%) of its end. The field is the row, so every later rule treats the blank as a
  field's one-line blank. **Shared:** `PDFReflowLibPipeline.extractPage` adds printed blanks to
  `PageContent.blanks` on native pages after hidden-text removal, and the crop seeds leave out
  every blank's rule, not only the fields'.
- `LayoutReconstructor.answerAreas` (new): each blank whose field is taller than 2.5 body sizes,
  with no line of type inside it and no crop over it, adds a line `____` at its rule, the area's
  width, at the body size, `wraps` false. **Shared:** `blocks` feeds these lines in after
  `joiningBlankRows`.
- **Shared:** `rankHeadingLevels` ranks an outline heading by its tier's index among the depths the
  document sets, not by its absolute depth.
- `SourceLayoutFixture.content` reads printed blanks from a fixture's paints as the pipeline does;
  `fields: false` drops a fixture's field blanks.

Hunks in functions other agents work near: `extractPage` gains the printed-blank call and the
crop-seed filter reads `content.blanks`; `blocks` changes only the joining call; `rankHeadingLevels`
changes only the outline line. `joiningBlankRows`, `splitAtBlanks` and `outlineSectionLabels` are
untouched.

## Where printed blanks are found

With a temporary diagnostic, every cached PDF was converted (`--ocr never`) and each printed blank
logged with its row: the 20 gated cases (NOAA included) and two uncatalogued PDFs other work keeps
in the shared cache (`M-618_a.pdf` and an IRS publication in Chinese); the Warren report, scanned
with an earlier draft, had none. The final rule finds two in the gated corpus, the Agricultural
Research coupon's (page 24, rules 82 and 57 points long), and 24 on two worksheet pages of the
IRS publication (`p596zhs--2025.pdf` pages 6–7: `… 5.` then a rule to write the amount on). None on Pro Se (every
rule there is a field's), Wallace, FAA, NOAA, 9/11, Fed, Census, Blue Book or the rest.

Earlier drafts found more, each reviewed against a render and each ruled out:

| Draft | Found | What it was | Rule added |
| --- | --- | --- | --- |
| 1 | Replay Clocks pages 3 and 5 | a left-column float rule level with a right-column line 2.3 ems after it | text after a rule must start within a font size |
| 1 | IRS pages 2, 4, 8, 14, 16, 19 | right-column section rules and bars level with a left-column line | a rule as wide as a nearby line is its column's |
| 2 | Wallace pages 472–480 (11) | radical bars 13–17 points long beside `√` | at least three font sizes long |
| 3 | NOAA page 25 | a tab bar touching the table title band below it (0.5 points apart) | no other paint within a point |
| 3 | NOAA page 53 | a list separator across the right column, level with a left-column line | the column test takes a line starting inside the span and ending within two font sizes of the rule's end (15.4 points short there) |

A draft that rejected a rule when any line of another column stood within 2.5 ems over its span
also lost `Case No. ____` on Pro Se read without fields, since `(to be filled in by the Clerk’s
Office)` sits under that blank; the final column test needs the line to reach the rule's end, which
that caption stops 55 points short of.

## Corpus results

One call per case, all 20 English cases, both runs passing their contract, EPUBCheck, progress and
memory gates.

| Case | Changed pages | Fields | Notes |
| --- | --- | --- | --- |
| US Courts Pro Se 1 | 1, 3, 4, 5 | text, paragraphs, markup | six `____` answer-area paragraphs; no image, navigation or warning change |
| Agricultural Research | 24 | text, paragraphs, markup, images | the coupon's labels read with their blanks; the 389×71-pixel coupon crop becomes a 41×65-pixel crop of the two drawn boxes |
| the other 18 | none | — | `compare_conversion_runs.py` exit 0 |

The eighteen unchanged cases include every case with outline or form material and every one the
drafts above touched (Replay Clocks, Wallace, NOAA, Census, Blue Book); no case sets an outline that
starts below the Roman tier, so the ranking change moves no heading in the corpus. Receipts for Pro
Se, the magazine and NOAA are in `lane/`.

The Pro Se contract grows from 219 to 229 checks (each answer area in order between its prompt and
what follows, and `____` as a paragraph on pages 1, 3, 4 and 5); the previous converter fails 39 of
them (page 5's opening `____` cascades through that page's order check). The Agricultural Research
contract grows by five checks to 273 (the two coupon labels as paragraphs, and the instruction and
both labels in order); the previous converter fails the four on the labels.

## Review

Against 50–60 DPI Poppler renders of the pages:

- Pro Se page 1: `__________ Division`, `____` (the plaintiff name box), `Plaintiff(s)`, its
  instruction, `-v-`, `____` (the defendant name box), `Defendant(s)`, its instruction, then the
  right block as before. Page 3: `List the specific federal statutes …`, `____`, `B. If the Basis …`.
  Page 4: the amount-in-controversy prompt, `____`, `III. Statement of Claim`, its paragraph, `____`,
  `IV. Relief`, its paragraph. Page 5 opens with `____` (IV's space continues there, closed by a
  rule above `V.`), then `V. Certification and Closing`. Page 2 has no answer area and none is set.
- Agricultural Research page 24: `Please return the mailing label from this magazine:`,
  `To stop mailing ____`, the crop of the two boxes, `To change your address ____`.

## Tests

`FormBlanksAndOutlineTests.swift`: printed blanks with ten controls (grid rule, box, value on the
rule, underline, radical bar, footnote separator, text too far after or before the rule, a column's
float rule, a separator across the next column's ragged list) and the `Case No.` caption case; Pro Se
read without its fields (every label and fill-in sentence still set with its blanks, no answer area
made of bare rules); the synthetic AcroForm page without its fields (`Name ____`, `Street Address
____`, the row PDFKit reads across its rule untouched, the lone rule still a crop); answer areas on
their own with controls (one-line field, an area with type in it, one under a crop, no blanks); the
six areas' places in the Pro Se reconstruction; and an outline opening at capitals, alone and beside
a Roman tier elsewhere in the document. Negative controls: printed blanks disabled, 14 failures;
answer areas, 12; fixed depth, 1; all three, 27.

## Limits and follow-ups

- A printed form's answer area (ruled writing lines on no row of type, or an empty box) is still a
  graphic; only a field's area is read as one.
- A printed blank is not cut out of a row PDFKit reads across it (the collapsed `State of (name).`
  case), since without a field nothing says the gap is a blank; the rule stays a graphic there.
- Drawn check boxes (the coupon's) stay crops; the form's glyph boxes read `☐` (#151).
- An outline still needs two nested tiers and a bold label on one page; a page carrying one tier of
  an outline set up on another page ranks nothing.
- The `a.`/`b.` tier and the header rule under `--repeated-headers-and-footers keep` (items 4 and 5
  of #197) are unchanged.
