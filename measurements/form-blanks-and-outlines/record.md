# Form blanks, outline labels and counted folios (#152)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLIs.
Baseline: an unmodified release build of `f3840f4` (converter `ab9fb562…`); candidate: that tree
with this change (`528971b8…`; the sixteen cases outside the form and its FAA, Fed and 9/11
controls were run with `5168a329…`, which differs only in admitting the sentence-space join on
justified type as well, and changed none of them). Every corpus figure is `tools/run_corpus_regressions.py`, one case
per call, with one compiled raster/Vision probe shared by both runs and `--execution-context
host-terminal`, then `tools/compare_conversion_runs.py --allow-different-converters` (receipts in
`lane/`). No PDF or EPUB is committed.

## State before this change

Reproduced on `f3840f4`, after #151 (annotation page images) and #180 had landed. #151 had already
fixed what the review file lists as correct: no page carries an `Original page N` image, each page
warns that its form fields are not interactive, and the box glyphs under the checkbox widgets read
`☐`. #180 (justified lines PDFKit cuts at a stretched word space) changed nothing on this form, whose
prose is ragged. Every #152 defect was still present:

| Defect | Page(s) | Output at `f3840f4` |
| --- | --- | --- |
| Field labels run together | 1, 2, 5 | `<p>Name Street Address City and County …</p>`, one per block |
| Fill-in sentences fragment at blanks | 3, 4 | `<p>If the plaintiff is an individual The plaintiff, (name)</p>`, `<p>, is a citizen of the</p>`, a crop, `<p>State of (name).</p>` |
| Caption brackets as text | 1 | `<p>) ) ) ) ) ) ) ) ) ) ) ) ) ) )</p>` |
| Header rule crop, folio kept | 1–5 | a 1359×17 crop of the double rule with the head's clipped foot on every page; `<p>Page N of 5</p>` |
| Statement of Claim split | 4 | three paragraphs, cut after `claim.` and after `as possible the` |
| Section labels | 1, 3, 4, 5 | `I.` apart from its title; `II.`–`IV.` bold paragraphs; `A.`/`B.`/`V.`/`1.`–`3.` as `<pre>` |

The 21 images in the baseline EPUB were all rules: five head-rule crops and sixteen crops of blank
rules (the caption's name lines and the shorter fill-in blanks; the wider blanks already vanished
as page decoration, which is why page 2 had no blank crops and its labels still ran together).

## Root causes

Read from `tools/capture-layout-fixture.swift` output and the form's widget dictionaries.

1. **Blank rules were graphics.** Every rule on the form except the head's lies inside an AcroForm
   text or choice field's rectangle (68 text fields, one choice). Nothing read the fields as
   structure, so each rule was a crop seed: a narrow one became a crop between the fragments of its
   sentence; a wide one with no text beside it passed `isDecorationRule` and vanished. Either way
   the row had no blank, and PDFKit returned the text on either side of it as separate lines 200–300
   points apart, far past any row-joining rule. Six rows came back the other way: PDFKit read
   `State of (name).` across its blank as one line, the gap collapsed and its two edge characters'
   boxes stretched over it (a selection ending at the blank's middle ends at `)`, one starting there
   holds `.`).
2. **Labels one per row joined as prose.** A stack of labels at one edge and 18.7-point pitch
   reads as a ragged paragraph; the blank on each label's row was the only evidence it is a field.
3. **Outline markers sit on tab stops.** `I.`, `A.`, `a.` and `b.` stand 25–29 points (2.3–2.6
   font sizes) left of their titles, past `joiningMarkerPieces`' two-font-size limit. `II.`–`V.` and
   the single-letter/number labels PDFKit returned whole were at the body's size, so no size or
   `sectionLabels` rule (which requires the paragraph to open within 0.8 body and on the title's
   edge) made them headings, and `isList` set the single-letter ones as `<pre>`.
4. **A sentence's two spaces.** PDFKit cut the Statement of Claim's first line at the double space
   after `claim.` (5.54 points at 11 points). `joinedRows` requires such a junction not to end a
   sentence, and a non-mathematical row to share a justified measure; the form is ragged.
5. **The brace.** Fifteen lines each holding one `)` at x = 302.2, one under the next.
6. **The folio counts the pages.** `Page N of 5`'s boundary word is the unchanging total; the page
   number is the second word, which no folio rule read, so no run formed.
7. **The head's rule is a double rule.** Two padded hairlines merge into one graphic 6.9 points
   tall, past `isThinRule`'s six, so the page-decoration test never read it; its crop took the foot
   of the removed head.

## Changes

- `FormBlank` (`DocumentModel.swift`) and `AnnotationEvidence.blanks`: a visible text or choice
  field over thin rules along its lower edge is a blank; `PageContent.blanks` carries them. The
  pipeline leaves blank rules out of the paints that seed crops. **Shared:** `PDFReflowLibPipeline.extractPage`.
- `NativeTextReader.splitAtBlanks` (new, called from `lines(on:)`): a line holding a one-line
  field's blank is cut at the blank when a selection of the blank's interior (an em in from each
  end) holds no letter or digit, the pieces spell the line (spaces aside), and each piece is
  clamped to its side of the rule. **Shared:** `NativeTextReader.lines(on:)` gains a `blanks`
  parameter (default empty).
- `LayoutReconstructor.joiningBlankRows` (new): the pieces and blanks of a row read left to right as
  one line, a blank as `____`, punctuation after a blank closing up; a row ending in its blank
  carries `wraps = false`, so the next line opens a new block. A field taller than two lines of its
  row is an answer area and joins nothing; a line over the rule, a tagged line or a page without
  blanks is untouched.
- **Shared:** `LayoutReconstructor.joiningMarkerPieces` — a gap of up to 3.5 font sizes also joins
  when the marker and the text each start on an edge another line of the page starts on.
- **Shared:** `LayoutReconstructor.joinedRows` — a junction where the left piece ends a sentence
  and kept its trailing space, at most 0.75 em wide, runs on, but only where the page has no
  justified measure at that size and the row is the first line of the paragraph beneath it (same
  left edge, ordinary leading, at least 90% of that line's width). A first version also let such a
  row through `isProseRow`; #180's controls (a justified column's row stopping 16 points short of
  the measure, and a measure only two lines share) failed on it, and pass now.
- `LayoutReconstructor.outlineSectionLabels` (new): Roman (depth 0), capital (1) and numbered (2)
  labels at the body's size with a title-case title, when the page sets at least two nested tiers
  and at least one label is bold. They join the page's labels; `ReflowBlock.outlineDepth` records
  the tier. **Shared:** `rankHeadingLevels` keeps outline headings out of the size tiers and ranks
  them at their size's level plus their depth (to 6); the heading-row merge in `blocks` never
  continues a heading with an outline label.
- `LayoutReconstructor.bracketColumns` (new): three or more lone bracket lines on one edge at line
  pitch are a brace; **shared:** `blocks` drops them as text but keeps each column as a boundary
  element, so the caption still reads parties before case number.
- **Shared:** `FurnitureDetector.collect` normalizes the page number of a counted folio (`page 3 of
  5`); `FurnitureDetector.apply` removes a page-wide thin rule set against a removed margin line
  (within a quarter of its height, nearer it than the body) from the page's graphics.
- `tools/capture-layout-fixture.swift` records a page's blanks and captures lines cut at them, as
  the pipeline extracts them.

Hunks in functions other agents are working near: `joinedRows` (maths spacing, #188/#189) gains
only the sentence-space branch and leaves the mathematical path as it was; `joiningMarkerPieces`,
`rankHeadingLevels` and `blocks` (brace filter, label list, heading creation and merge) change as
above; `NativeTextReader.lines(on:)` and `PDFReflowLibPipeline.extractPage` gain the blank plumbing
only. `graphicsWithLabels`, `isDecorationRule` and `isThinRule` are untouched.

## Corpus results

One call per case, 20 English cases (NOAA included), both runs passing their contract, EPUBCheck,
progress and memory gates. The Arabic and Chinese cases were not run.

| Case | Pages changed | Fields | Images (before → after) |
| --- | --- | --- | --- |
| US Courts Pro Se 1 | 1–5 | text, paragraphs, headings and levels, list items, preformatted lines, images, navigation, warnings | 21 → 0 |
| every other English case | none | — | unchanged |

`compare_conversion_runs.py` reports no changed page, image, navigation entry or report field on
the other nineteen cases, FAA, Fed and 9/11 included (receipts for the form, the three controls,
USDA and NOAA in `lane/`; the rest were run and compared the same way). The form's contract (219
checks) passes on the candidate and fails on the baseline evaluation.

The only warning change is Pro Se 1's `imageRegion` warning, which no page reports now that no
page keeps a crop. Navigation gains the outline headings on pages 1, 3, 4 and 5.

An earlier candidate removed any page-wide rule lying between a removed margin line and the body.
It also took the magazine's foot rule on all twelve pages that have one (USDA 6–9, 11, 12, 15–19
and 22; a 1360×10 crop of a plain rule each) and the closing rule of two NOAA tables (pages 411 and
1565), 55 and 13.5 points above the foot, and a table rule on page 1498. Those rules belong to
the table or stand as near the photo credit above them as the foot below; the rule now
has to touch the removed line (within a quarter of its height), and all fifteen pages are
unchanged against the baseline.

## Review

The five Pro Se pages, against 100 DPI Poppler renders:

- Page 1: `UNITED STATES DISTRICT COURT` (h2) and `COMPLAINT FOR A CIVIL CASE` (h3) as before; the
  caption reads `for the`, both underscored lines, `Plaintiff(s)` and its instruction, `-v-`,
  `Defendant(s)` and its instruction, then `Case No. ____`, `(to be filled in by the Clerk’s
  Office)`, `Jury Trial: (check one) ☐ Yes ☐ No`; `I. The Parties to This Complaint` (h4),
  `A. The Plaintiff(s)` (h5), its instruction, six label paragraphs `Name ____` … `E-mail Address
  ____`, `B. The Defendant(s)` (h5) and its instruction. No image, no `)` and no folio.
- Page 2: `Defendant No. 1`–`4`, each followed by its seven label paragraphs ending `____`.
- Page 3: `II. Basis for Jurisdiction` (h4); the prose, question and checkbox paragraphs as
  before; `A.`/`B. If the Basis for Jurisdiction …` (h5); `1. The Plaintiff(s)`, `2. The
  Defendant(s)` (h6); `a. If the plaintiff is an individual` as a list line, then `The plaintiff,
  (name) ____, is a citizen of the State of (name) ____.`; the corporation item the same way; the
  instruction paragraph; `a. If the defendant is an individual` and `The defendant, (name) ____, is
  a citizen of the State of (name) ____. Or is a citizen of (foreign nation) ____.`
- Page 4: `b. If the defendant is a corporation` and its sentence whole across five rows and four
  blanks; `3. The Amount in Controversy` (h6); `III. Statement of Claim` (h4) and its paragraph whole;
  `IV. Relief` (h4) and its paragraph.
- Page 5: `V. Certification and Closing` (h4), the Rule 11 paragraph, `A. For Parties Without an
  Attorney` (h5), the address paragraph, `Date of signing: ____`, both plaintiff signature labels,
  `B. For Attorneys` (h5), `Date of signing: ____` and the eight attorney labels, each `… ____`.

What is not represented: the empty name boxes above `Plaintiff(s)` and `Defendant(s)`, and the
answer areas under sections II.A, 3, III and IV, are fields taller than a line whose closing rules
join no row; the EPUB carries their prompts but no mark for the space. Before, the two caption
boxes and the II.A area were rule crops and the rest vanished.

## Tests

`FormBlanksAndOutlineTests.swift`: the five Pro Se pages as source-derived fixtures (`uscourts-1`
… `uscourts-5`, with their blanks) through furniture removal, crops, blocks and ranking; unit tests
of each mechanism with controls; a synthetic AcroForm page end to end, and the same page without
its fields. Negative controls, each mechanism disabled in turn: row joining 23 failed expectations,
extraction cut 2, blank rules seeding crops 6, tab-stop join 12, sentence space 2, outline labels 9,
tier ranking 6, brace 2, counted folio 10, head rule 11; all at once, 61. The corpus contract for
Pro Se 1 grows from 162 to 219 checks and fails 55 of them against the baseline evaluation.

## Limits and follow-ups

- Blanks come only from form fields. A printed (non-fillable) form's ruled blanks, with no widget
  over them, are still graphics, as before.
- A field taller than two lines is an answer area and leaves no mark in the text.
- An outline needs two nested tiers on one page and a bold label; a page carrying one tier of a
  document's outline (Pro Se page 2 has none) ranks nothing. Outline depth is absolute (Roman 0,
  capital 1, number 2), so an outline that starts at capitals ranks one level below its size.
- The lowercase tier (`a.`, `b.`) stays a list line (`<pre>`).
- `--repeated-headers-and-footers keep` keeps the head, so its rule still crops with the head's foot.
