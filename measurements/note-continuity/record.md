# Endnote links lost to a misprinted head, a continued list and list-item markers (#87)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 release CLIs. Work began on
`583713f`. The baseline is the release CLI built from unmodified `583713f` (SHA-256 `b9a646c2…`); the
candidate is `583713f` plus this working tree (release `c1e68dd3…`). Both ran in the corpus lane with
one shared capability probe (`tools/probe-raster-environment.swift`, execution context
`host-terminal`), one case per run. Source: 9/11 `GPO-911REPORT.pdf` (`657d4147…`). Pages 205, 496 and
545 were rendered with Poppler and read; 543/544 geometry was read from fresh source captures.

## What was wrong

#80 left 63 raised markers in 9/11 body pages plain. Three causes cover 58 of them (the #80 record
sorted 5 more as uninvestigated: they are cause 3 as well).

1. **Misprinted head (40 markers).** Page 496's running head reads `478 NOTES TO CHAPTER 4`, but the
   page holds chapter 3's notes 93–112. Page 495 ends with chapter 3's note 92, and page 497 continues
   with 113–114 before opening chapter 4 at note 1. The detector keyed the page to chapter 4. Its notes
   collided with page 502's real chapter-4 notes 93–112, so `NoteLinker` treated all 40 keys as
   ambiguous. That left markers on pages 115–124 (chapter 3) and 143–148 (chapter 4) plain.
2. **Continued candidate list (2 markers).** Note 107's numbered candidate list starts on page 543
   (#80) and runs to page 545. Page 544 holds only items 7–9 and their further paragraphs. The
   detector read it alone: the items' edge was its first start, so they became chapter 7's notes 7–9.
   Those keys collided with page 532's notes 7–9, which left page 234's markers 7 and 9 plain. On page
   545, the lines above note 108 were spatial prose. `Thereafter, … Khalid` / `al Zahrani, …` split
   into two paragraphs, and item `10. Abderraouf Jdey` became a one-line `<pre>` with its wrapped lines
   as a paragraph.
3. **List-item markers (21 markers).** `NoteLinker` scanned paragraphs only. The raised markers inside
   preformatted bullets and numbered items stayed plain:
   - the 16 counted by #80 in chapters 7 and 10–13 (page 270's 185; 344–345's 13–15; 349's 37; 365's
     24; 387's 10; 389's 15; 406's 37; 423's 5; 430's 12–14; 436's 17; 438's 19; 444's 20);
   - the 5 left uninvestigated in #80 (page 183's 85 and page 205's 93 and 96–98), which are bullets
     too.

## What changed

`Sources/PDFReflowLib/NumberedNoteDetector.swift`, `NoteLinker.swift`, `LayoutReconstructor.swift`,
`EPUBWriter.swift` and `PDFReflowLibPipeline.swift`. No public API or default changed.

- **Continuity scoping (`NumberedNoteDetector.scopeByContinuity`).** This runs after reconstruction
  and before linking, over the chapter-scoped note keys and the heads read during extraction. A notes
  page is re-keyed from its printed chapter M to chapter N only when all of these hold:
  - its head names the single chapter M, and every note on it is keyed to M;
  - its first note is not 1, and continues the last note of the previous physical page, which is
    keyed to N ≠ M;
  - M's note 1 is on another page, and another page also claims one of this page's numbers in M;
  - N claims none of this page's numbers.

  Every decision is recorded as `NoteLinker.Summary.rescopedPages` (page, printed chapter, chapter,
  numbers). This is internal, like the rest of the summary; no report field or warning was added.
  Numbering that restarts at 1 never moves a page.
- **Open lists across pages (`Layout.openList`, `resumption`).** A numbered list inside a note is still
  open at a page's end when the page's last line reaches the list's right edge (the widest of at least
  two list lines on the page). Page 543 sets its list 12 pt narrower than its notes on both sides. The
  pipeline hands that state (note, next item, the items' inset from the note indent) to the next
  physical page through `LayoutReconstructor.blocks(continuingNoteList:noteLayout:)`, and clears it on
  every other page. The page resumes the list only when the line numbered as the next item comes at or
  before its first note start, in one of two ways:
  - **Above the open note's successor.** The item sits the list's inset inside that note's indent
    (545: `10.` at 68.7 above note 108 at 56.7).
  - **As the page's first start.** The item is numbered as the list expects and not as the chapter's
    next note (544: `7.` where note 108 is expected). The note indent is then the item edge less the
    inset (51.7).

  The page is then read from its first line with the list open, so earlier lines are that note's text.
  The resumed page may hold no note start, and `count >= 3` and the dedented-continuation requirement
  do not apply to it. When the resumed reading refuses, the page is read as before. A bulleted list is
  never resumed. The next note may follow a numbered list after up to 1.6 body sizes of space, the
  allowance that opens a list (545: 9.66 pt, 1.38 body sizes). That shape refused a page before.
- **List-item markers.** `NoteLinker` also scans a `preformatted` block whose text opens with a list
  marker (`LayoutReconstructor.isList`, now internal). Code and notes are never scanned. A linked item
  stays preformatted, with only the marker becoming a `noteReference`. `EPUBWriter` collects references
  from those blocks too, so their notes receive ids and backlinks.

## Before and after (9/11)

The table counts superscript digit runs in body blocks on pages 19–467, with chapters from the
outline openings, the same way as #80's table. Every link goes to a note id in the marker page's
chapter.

| Chapter | Linked before | Plain before | Linked after | Plain after | In list items after |
| --- | --- | --- | --- | --- | --- |
| 1 | 241 | 0 | 241 | 0 | 0 |
| 2 | 93 | 0 | 93 | 0 | 0 |
| 3 | 94 | 20 | 114 | 0 | 0 |
| 4 | 174 | 20 | 194 | 0 | 0 |
| 5 | 108 | 1 | 109 | 0 | 1 |
| 6 | 206 | 4 | 210 | 0 | 4 |
| 7 | 162 | 3 | 165 | 0 | 1 |
| 8 | 98 | 0 | 98 | 0 | 0 |
| 9 | 173 | 0 | 173 | 0 | 0 |
| 10 | 82 | 4 | 86 | 0 | 4 |
| 11 | 39 | 1 | 40 | 0 | 1 |
| 12 | 39 | 3 | 42 | 0 | 3 |
| 13 | 15 | 7 | 22 | 0 | 7 |
| **Total** | **1,524** | **63** | **1,587** | **0** | **21** |

- **Link counts.** Before, the lane EPUB matches #80's 1,524/63. The candidate's pipeline summary reads
  `markers: 1587, linked: 1587, unscoped: 0, missing: 0, ambiguous: 0, ambiguousNotes: 0`. There are
  zero cross-chapter links and no duplicate note ids (1,587 ids).
- **Decisions.** The only continuity decision is `page 496, printed 4, chapter 3, numbers 93...112`.
  The only open-list hand-offs are 543 → 544 (note c7-107, next item 7) and 544 → 545 (next item 10).
- **Sweep.** A temporary environment-gated debug build (removed) converted every English corpus
  document. No other book produced a decision or a hand-off. Warren and NOAA were converted with an
  unlimited output budget and JPEG images, since both fail the default image ceiling on either build.
  Links elsewhere: Loper Bright 22, USGS copper 2, every other book 0 (their list-item markers have no
  chapter or page note, so they stay plain).

Reviewed targets:
- Page 143's 93 (`embargo on arms shipments to the Taliban, in December 2000.`) reaches chapter 4's
  `93. UNSCR 1333, Dec. 19, 2000.` on 502.
- Page 115's 93 and 124's 112 reach chapter 3's notes on 496 (`John Hamre interview`, `Although some
  members of the House…`).
- Page 234's 7 and 9 reach 532.
- Page 205's bullets reach `93. PDD-62 …` and `96. PDD-62, May 22, 1998, p. 9. Congress had authorized
  the Alien Terrorist Removal Court…`.
- Page 430's item marker 12 reaches `12.Some smaller parts of the current intelligence community…` on
  584.

### Markup review against the `583713f` build

Every page's text is identical once spaces are ignored.
- **84 pages** differ only in link markup.
- **8 pages** (117, 119, 124, 144, 145, 146, 205, 365) also move a marker's trailing space outside
  the link (`<sup>96 </sup>and` → `<sup>96</sup> and`). This is #11's documented handling of a marker
  extracted as `N `.
- **Page 545** is the intended change. `Thereafter, Hamlan received a visit … Khalid al Zahrani, who
  asked …` is one paragraph, and `10. Abderraouf Jdey, a.k.a. Faruq al Tunisi. …` is one paragraph with
  its wrapped lines (it was a `<pre>` plus a paragraph). Page 544's markup is unchanged: its items were
  already paragraphs, and their keys never received ids.

`tools/compare_conversion_runs.py --allow-different-converters` found 0 provenance errors, 0 changed
images, equal page markers and 0 changed report fields (warnings identical). It lists 143 changed page
records, all accounted for:
- 48 pages differ in `noterefs` only;
- 23 pages differ in `anchors` and `noterefs`, plus the 8 trailing-space pages above with `scripts`;
- 23 pages differ in `anchors` only: new note ids, or a spine-file boundary that moved inside a page as
  link bytes repacked the book (221's `6.5` heading now opens `chapter-13.xhtml`);
- 40 notes pages after 545 differ in `paragraphIDs` only, renumbered because 545's two paragraphs
  merged;
- 545's paragraphs and list items change.

Loper Bright and USGS copper compare as passing outright, with no changed pages, images or report
fields; their 22 and 2 note links are unchanged.

## Contracts

`corpus/regressions.json` gains 15 checks on 8 new 9/11 pages, for 960 checks on 207 pages. The
9/11 case goes from 176 to 191 checks.
- **Reproducers (10):**
  - `noteLinks` from 115 (93 → 496), 124 (112 → 496), 143 (93 → 502), 234 (7 and 9 → 532), 205 (96
    in a bullet → 523) and 430 (12 in an item → 584);
  - 545's two paragraphs, and its distinct-paragraph check between `Hamlan never did.` and item 10.
- **Controls (5):** 205's bullet stays a list item; 544's item 7 and its `In December 1999` further
  paragraph are paragraphs and stay distinct from item 9; 545's note 108 is a paragraph.

The `basis` sentence for the case is extended. `doc/regression-testing.md` has its coverage sentence
and test count updated, and `doc/architecture.md` describes the three rules.

Negative control: the lane on the `583713f` build fails exactly the 10 reproducer checks and passes
the 5 controls. The candidate passes all 191.

## Verification

- `swift test`: 385 tests pass (379 on `583713f` plus 6).
  - `ContinuedNotePageTests.swift` (new source fixtures `911-495`, `-496`, `-497`, `-502`, `-544`,
    `-545`, captured with `tools/capture-layout-fixture.swift`; the committed `911-543` recaptures byte
    for byte):
    - a chained reconstruction of 495/496/497/502 showing the collision, then the single rescope and
      both markers linking with no ambiguity;
    - nine synthetic controls where the printed head must win: numbers restarting at 1, a gap, no
      note 1 in M, no collision, N already holding a number, a two-chapter head, a non-adjacent
      previous page, genuinely continuing notes, and a page that switches chapters;
    - a chained reconstruction of 543/544/545, with a carry-off negative showing the old keys c7-7…9
      and the old `<pre>`;
    - resumption controls: page 532's genuine notes 3–13 handed a list from note 2, or from another
      chapter; 545 handed a wrong next item, inset or note; `openList` absent on 532, 545, 583's
      bullets and a list ending on a short line.
  - `NoteLinkTests.swift`: list-item links with code and in-note controls, writer ids and backlinks
    for a note referenced only from a `<pre>`, and source page 365's item 3 marker 24.
- Negative control for the suite ([before-tests.log.gz](before-tests.log.gz)): the new tests ran
  against this tree with four stubs restoring `583713f` behaviour (no rescope, no resumption, no
  closing-gap allowance, no list-item scanning). All 6 fail, with 21 issues, all reproducer
  expectations. The controls above pass under the stubs.
- `scripts/check-all.sh --fast`: exit 0 (385 Swift, 186 Python, 13 policy conversions and 22
  rejection cases, repeat-run identity on six fixtures).
- Corpus lane, both binaries, one case per call, shared probe: `gpo-911-2004` (candidate 191 pass;
  baseline 181 pass / 10 fail), `scotus-loper-bright-2024` (91 / 91) and `usgs-mcs2025-copper`
  (49 / 49). EPUBCheck reports 0 on all six runs, and structural and progress checks pass.
- `git diff --check` clean.

## Remaining gaps

- Continuity scoping needs the previous physical page's notes to be keyed. A misprinted head after a
  refused or resumed page is not re-scoped.
- A list is resumed only on the next physical page, and only if numbered. A bulleted list continuing
  onto a new page, or a numbered one whose last line on the page is short, still reads as before.
- The rescope decisions are internal (`PDFReflowLibPipeline.Result.noteLinks.rescopedPages`); no
  report field or warning was added.
