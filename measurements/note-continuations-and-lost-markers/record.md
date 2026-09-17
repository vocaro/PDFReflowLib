# Endnote continuations across pages and markers lost at extraction (#11)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 release CLIs. Work began on
`aa53aaa` and was carried through the tips `d35285f`, `605d7e3` and `e949bea`; every figure below is
from `e949bea`. The baseline is the release CLI built from unmodified `e949bea` (SHA-256 `abf0a8e2…`);
the candidate is `e949bea` plus this working tree (release `0a7c4723…`). Both ran in the corpus lane
with one shared capability probe (`tools/probe-raster-environment.swift`, execution context
`host-terminal`), one case per run. Source: 9/11 `GPO-911REPORT.pdf` (`657d4147…`). Pages 362, 369,
498, 545/546, 557/558 and 583/584 were rendered with Poppler and read; pages 362 and 369 were also
read with `pdftotext -bbox-layout`. Geometry came from fresh source captures and from a temporary,
environment-gated dump of every notes page's detector reading (removed).

## Survey: every notes-page transition

[transitions.tsv](transitions.tsv) lists the 117 notes pages (469–585). For each page it gives the
note open at the previous page's end, the page's first note start, the lines above that start and
the edge the first of them sits on, how the first line opens, and how the baseline and candidate
emit the page's first text. [tools/survey.py](tools/survey.py) reads the emitted form from an
unpacked EPUB.

The notes' typography decides every case. A note starts at the indent with its number (51.7 pt on
page 532). Its wrapped lines dedent 12 pt to one shared edge (39.7 pt). A further paragraph opens
unnumbered at the indent.

| Page opens with | Pages | Baseline | Candidate |
| --- | --- | --- | --- |
| The next note in sequence | 36 | note start | note start |
| A wrap at the dedented edge, lowercase | 46 | joined | joined |
| A wrap at the dedented edge, capital | 18 | separate unkeyed paragraph | joined, except 584 (below) |
| A wrap at the dedented edge, digit | 8 (473, 508, 524, 540, 542, 563, 570, 581) | separate; 540's `2002. For his training` a `<pre>` list item | joined |
| A wrap at the dedented edge, quote or bracket | 3 (506, 532, 580) | separate | joined |
| A further paragraph at the indent | 2 (498, 538) | separate, split after its first line | separate, whole |
| A chapter title at the page top | 2 (469, 518) | heading | heading |
| A resumed list (#87) | 2 (544, 545) | joined | joined |

No continuation was misread as a new note: every page's first note start is its predecessor's
number plus one in the same chapter. The only exceptions are 496 and 497, around page 496's running
head, which misprints the chapter (#87). The baseline had two problems.
- **Capital, digit and quote openings.** `appendPage` joined across the page only when the next text
  opened lowercase after a line without terminal punctuation. So 29 notes ended in a stray paragraph
  on the next page, 540's in a list item.
- **Spatial prose above the first note start.** The detector left the lines above a page's first
  note start to spatial prose. That split a long continuation at every indented line and inside
  wrapped lines, even where the join then happened. Page 498's further paragraph read `…the United
  States did` / `not accept…`, and `crit-` / `icized` stayed hyphenated across the split. 534,
  538, 546, 552 and 584 split the same way.

Two first lines follow a line that ends a sentence: 546's `Shehri and another individual…` after
`…identification document.`, and 558's `See FBI report…` after `…at the time.` In both, the upper
line is a full justified line, and the lower one sits at the dedented edge, 12 pt left of where the
book opens a paragraph (`The next set,…` directly below is indented). They are wraps. Page 584's
`The proposed National Counterterrorism Center…` also sits at the dedented edge. But page 583 ends
chapter 13's note 4 with a bullet whose last line stops at 288.0 of a 356.7 pt measure. The book sets
the first paragraph after a list flush left, so this is a new paragraph (render read).

## What changed

`Sources/PDFReflowLib/NumberedNoteDetector.swift`, `LayoutReconstructor.swift`,
`PDFReflowLibPipeline.swift` and `NativeTextReader.swift`. No public API or default changed.

- **Continued note (`NumberedNoteDetector.layout(continuedNote:)`).** An accepted layout now records
  `lastNote`, the note its last line belongs to. The pipeline hands it to the next physical page, as
  #87 hands an open list, and clears it on every other page. The detector reads the lines above that
  page's first note start as the open note's text only when all of these hold:
  - the first start is the handed note's number plus one, in the chapter the head names;
  - every line above it is a wrap at the dedented edge the page's notes share (the same edge and
    0.8–3 body-size inset the rest of the page must use), or an unnumbered line of at least ten
    letters at the indent, opening a further paragraph;
  - those lines are in the notes' type at their spacing.

  A larger line (a chapter title), a line off both edges, or a numbered line out of sequence
  refuses that reading, and the page is read as before. The list resumption is tried first.
- **Join evidence (`Layout.continuesParagraph`, `appendPage(continuesNote:)`).** When the page's
  first line is such a wrap, the cross-page join accepts the detector's reading in place of the
  lowercase, sentence-end, word-count and prose tests. The previous block must still be a paragraph,
  and the next must carry no note key. The previous paragraph's last line must still fill its column
  (this refuses 583/584), and no prose may lie below that line or above the first. A first line at
  the indent is a further paragraph and never joins.
- **Markers measured on themselves (`NativeTextReader.remeasureQuotedMarker`).** See below.
- **Quoted marker pieces (`isDetachedQuotedMarker`).** A piece of closing punctuation followed by one
  raised marker of one to three digits attaches to the paragraph's current line without a space. The
  piece must be on that line's row, starting within half a body size of its end, and untagged. This
  is the same move `isDetachedMarker` makes for a bare digit piece.

## Markers lost at extraction

[tools/lost.py](tools/lost.py) counts each chapter's notes, parsed from the numbered note paragraphs
(numbering must run 1…N without gaps), against its linked body markers. Every chapter parses without
gaps. On `e949bea`, 1,735 body markers link to 1,735 distinct notes of 1,742, and no `<sup>` digit
run is left unlinked anywhere in the book. The issue's figure (chapter 5: 131 notes, 109 surviving
superscripts) predates later extraction work: chapters 5–9 gained 148 linked markers between `7c46377`
(1,587) and `d35285f`, where this survey first measured 1,735. Chapter 5 actually has 132 notes, and 131 are referenced.

| Chapter | Notes | Linked before | Linked after | Notes without a reference, after |
| --- | --- | --- | --- | --- |
| 1 | 241 | 241 | 241 | — |
| 2 | 93 | 93 | 93 | — |
| 3 | 114 | 114 | 114 | — |
| 4 | 194 | 194 | 194 | — |
| 5 | 132 | 131 | 131 | 36 |
| 6 | 261 | 260 | 260 | 132 |
| 7 | 192 | 190 | 190 | 16, 116 |
| 8 | 113 | 113 | 113 | — |
| 9 | 210 | 209 | 209 | 91 |
| 10 | 86 | 86 | 86 | — |
| 11 | 42 | 40 | **42** | — |
| 12 | 42 | 42 | 42 | — |
| 13 | 22 | 22 | 22 | — |
| **Total** | **1,742** | **1,735** | **1,737** | **5** |

[tools/between.py](tools/between.py) prints the body text between references N−1 and N+1 for each
missing note. It found two causes:

1. **Measured as base text (2: chapter 11's 12 on page 362, 32 on page 369).** PDFKit splits the row
   at a closing quote kerned back over the period (`routine.` ends at 82.47 pt, `”` starts at 81.19).
   It then measures the piece `”12` on its marker: the 10.25 pt quote reads −3.44 pt and the
   5.125 pt `12` reads 0. The marker became base text in a paragraph of its own (`<p>”12</p>`), and
   the quote a subscript. The text layer and the render agree the digits are raised: their box is
   4.6 pt tall against 9.3 pt, top-aligned with the line.
2. **Swallowed by a preserved region (5: chapter 5's 36 on page 172, 6's 132 on 210, 7's 16 on 235,
   7's 116 on 255, 9's 91 on 313).** In every case the paragraph's last line and its marker lie inside
   a `Preserved region from page N` crop (235: `separate ways.16` and `Bayoumi … Feb=`). Each crop
   sits beside a row broken with the book's `=` line-end hyphen glyph (`Feb=`, `excep= tional`,
   `inter= mediary`, `numer= ous`, `announce= ments`). The marker survives only as pixels. That crop
   seeding is outside note linking and is not recovered here (defect below).

No marker was found merged into a word (`went.8They` is a spacing case from the missing-spaces
survey; its marker is raised and links to chapter 7's note 8). None was dropped outright.

**Recovery (cause 1).** `remeasureQuotedMarker` re-measures an attributed line from its full-size
runs only when all of these hold:
- every full-size run is closing punctuation (`” ’ " ' ) ] . , ; :`), uniformly lowered by 0.2–0.5
  of its size;
- each smaller run is one to three ASCII digits at 0.4–0.7 of that size, at offset zero;
- each such run directly follows a full-size run and ends the line or comes before a space.

[tools/scan-lowered.swift](tools/scan-lowered.swift) applied the rule to every page of every English
corpus PDF: FAA, Wallace, Warren, 9/11, Fed, DGA, NOAA, Our Flag, Blue Book, CDC, NBS, Replay Clocks,
USGS copper, Loper Bright and Census. It fires on exactly the two 9/11 markers. Without the
punctuation condition it would also reach 129 Wallace exponent pieces (`x2`, `a3`, `32`) and NOAA's
`Act219`. Without the size and position conditions it would reach 47 lines of the Blue Book scan's
OCR layer (7 pt digits beside 31 pt `I`, `Fe 4 1/.`). Both recovered links were reviewed:
- page 362: `…alert measures bowed to routine.”<sup>12</sup>` → chapter 11's `12. For the response
  being routine, see Gordon Prange, At Dawn We Slept…` on 578, with its backlink;
- page 369: `…unless the intelligence was “actionable.”<sup>32</sup>` → `32. For Shelton’s view, see
  Hugh Shelton interview (Feb. 5, 2004)…` on 579, with its backlink.

## Before and after (9/11)

- **Transitions.** Of the 117 notes pages, 76 now join (48 before), 36 open with a note and 5 open
  separately: 469 and 518 (titles), 498 and 538 (further paragraphs) and 584 (paragraph after a
  list). All 28 new joins were reviewed at their boundary text. Each previous last line fills its
  column, and each first line is at the dedented edge above the next note in sequence.
- **Text.** Book text is identical once whitespace and hyphens are ignored. The one character change
  is 498's `crit-icized` → `criticized`, now joined inside its paragraph. The `280350-` + `SD` joins
  on 542 and 551 keep the space that same-page wraps already give such serials (defect below).
- **Links.** 1,737 references and 1,737 note ids, no duplicate ids, 0 across chapters.

`tools/compare_conversion_runs.py --allow-different-converters` found 0 provenance errors, 0 changed
images, 0 changed report fields, equal page markers and unchanged navigation. It lists 81 changed
pages, all accounted for:
- 28 body pages differ in `noterefs` only: the text of the note each reference reaches grew by its
  continuation;
- 28 pages that end a continued note differ in `anchors`, `markup` and `paragraphIDs`: the page-break
  anchor moves inside the note, and ordinals renumber;
- 15 continuation pages differ in `markup` and `paragraphIDs`;
- 498 also differs in `paragraphs` and `text` (`criticized`), and 534, 538, 546, 552 and 584 in
  `paragraphs` (wrapped lines rejoined);
- 540 loses its `<pre>` item;
- 362 and 369 carry the recovered links;
- 578 gives note 12 its id and backlink.

Loper Bright and USGS copper compare as passing, with no changed pages, images or report fields.

## Contracts

`corpus/regressions.json` gains 16 checks for 9/11 (193 → 209), on 14 pages, 7 of them new to the
case. The case's `basis` sentence is extended, and `doc/architecture.md` describes the rules.
- **Reproducers (11):**
  - `continuedParagraphs` 472→473 (`24,2003);`), 507→508 (`19, 2004.`), 531→532 (`“Alternate View:`),
    539→540 (`2002. For his training`), 545→546 (`Shehri and another…` after a full stop), 579→580
    (`(Nov. 10, 2003)`) and 581→582 (`Waleed al Shehri`);
  - `paragraphs` on 498 (`…did not accept a Sudanese offer`) and 584 (`…analytic units. But it would
    enable…`);
  - `noteLinks` from 362 (12 → 578) and 369 (32 → 579).
- **Controls (5):**
  - `separateParagraphs` for 583→584 (after the short last bullet) and 497→498 (further paragraph at
    the indent);
  - `distinctParagraphs` for note 2's continuation against note 3 on 532, and for the paragraph
    starts on 498 and 584.

Negative control: the lane on the `e949bea` baseline fails exactly the 11 reproducers and passes the
5 controls. The candidate passes all 209. An intermediate candidate without the fill test joined
583→584; that separation check is the control for it.

## Verification

- `swift test`: 563 tests pass (554 on `e949bea` plus 9) in `NoteContinuationTests.swift`, with new
  source fixtures `911-362`, `-369`, `-498` and `-531` captured with `tools/capture-layout-fixture.swift`
  (each recaptures byte for byte). The 9 tests:
  - chained reconstructions 531→532 (quote), 472→473 (digits), 579→582 (bracket, digits, capital),
    497→498 (further paragraph) and 583→584 (short bullet), each with a carry-off negative showing
    the old separate paragraph;
  - detector controls on 532: a wrong or earlier note number, another chapter, a larger first line,
    a first line off both edges, a numbered line out of sequence;
  - `appendPage` with and without the evidence, and a keyed note that never joins;
  - marker re-measurement on the captured `”12` and `”32` runs, with synthetic controls (`x2`, `32`,
    four digits, the Blue Book's third-size digits, a marker run into text, uneven quotes, a
    shallow offset) and page 20's ordinary `7:45.4`;
  - both recovered markers linking through reconstruction and `NoteLinker`;
  - the attach control (a body size past the line's end, or a line below).
- Negative control for the suite ([before-tests.log.gz](before-tests.log.gz)): the new tests ran
  against this tree with four stubs restoring `e949bea` behaviour (no continued-note reading, no join
  evidence, no re-measurement, no quoted-piece attach). All 9 fail, with 34 issues, all reproducer
  expectations.
- `scripts/check-all.sh --fast`: exit 0 (563 Swift, 213 Python, 13 policy conversions and 22
  rejection cases, repeat-run identity on six fixtures).
- Corpus lane, both binaries, one case per call, shared probe: `gpo-911-2004` (candidate 209 pass;
  baseline 198 pass / 11 fail), `scotus-loper-bright-2024` and `usgs-mcs2025-copper` pass on both.
  EPUBCheck and the structural and memory gates pass on all six runs.
- `git diff --check` clean.

## Remaining gaps

- The five markers inside preserved regions (chapters 5, 6, 7 ×2, 9) stay unlinked until those crops
  stop swallowing body lines.
- A continuation is recognized only on the next physical page, and only after an accepted notes page.
  A continued note whose next page switches chapters in a title above its first start, or whose
  lines above that start refuse, is read as before.
- A note ending at a full justified line whose next page's first line is flush left is joined. The
  9/11 notes open paragraphs at the indent, so both such pages (546, 558) are wraps. A book that
  opens notes' paragraphs flush left would need other evidence.
