# Page-bottom footnotes and slip-opinion running heads (#40)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 release CLI.
Baseline: repository `3507d7d`, Xcode 27.0 (27A266a). Source: *Loper Bright Enterprises v.
Raimondo* slip opinion, `corpus/cache/22-451_7m58.pdf`, SHA-256
`12f5ea075004886774c25e7831ea1608fd0f831f0113e83bb0e85811c0a4bb6e`. Baseline converter
SHA-256 `21db6d84…3f2f82` (built from `git archive 3507d7d`), fixed converter `4273a26c…69938`.

## What was wrong

Every Loper Bright page with a footnote appended the note to the last body paragraph together
with the typographic separator, and every page kept its running head as prose:

- page 60: `… not ours, that controls. —————— 2 See also A. Scalia, Judicial Deference …` in one
  `<p>`; page 97: `… we respect it”).<sup>2</sup> —————— <sup>2</sup>The majority tries …`;
  page 98: the continuation `rather than agencies to decide …` sat inside the body paragraph after
  `Vermeule 207.<sup>3</sup> ——————`, detached from its start on page 97;
- page 13: the body marker `1` after `Persistence.` was its own `<p>1</p>`, splitting the
  paragraph in three;
- `Cite as: 603 U. S. ____ (2024)` / `LOPER BRIGHT ENTERPRISES v. RAIMONDO`, the folio and the
  opinion row (`Opinion of the Court`, `GORSUCH, J., concurring`, `KAGAN, J., dissenting`,
  `Syllabus`) were paragraphs on all 114 pages; no `furnitureRemoved` warning anywhere.

## Source evidence

Layout fixtures captured with `tools/capture-layout-fixture.swift` from the checksum-pinned
PDF (new: `loper-61`, `loper-96` … `loper-101`; `loper-13` and `loper-60` already existed):

- Separator: a 9 pt text line `——————` (six em dashes), 54 pt wide, at the column's left edge
  (x 156.2), 2.3–14.9 pt below the last body line (10.98 pt body, 13.2 pt line boxes).
- Notes: 9 pt lines, 10.8 pt boxes at zero gap; each note's first line is indented 9 pt and
  opens with a 6 pt run (`2 `) at baseline offset +2.52, which native extraction already marks
  `.superscript`; that first line reports fontSize 6. Page 98's continuation is flush left with
  no marker; page 99 opens its note area with three continuation lines of page 98's footnote 3
  before footnote 4. On page 98 the 9 pt note text outweighs the body, so the page's
  character-weighted body size is 9; the body size must be measured above the separator.
- Body markers: `Ibid.2`, `207.3` are 7.02 pt runs at offset +3 inside their lines; on page 13
  the marker `1` fell past the justified right edge and extracts as a separate line
  (x 451.9–455.8, y 247.1–255.5, 7.02 pt) beside a line ending at x 455.7 (y 243.3–256.5).
- Running heads: title row with folio at y 667.4 (midY 0.849 of the 792 pt page) and the
  opinion row at 643.8 (0.820), both 9 pt; the body starts at 622.6, 8.0 pt below the opinion
  row's box. `FurnitureDetector`'s top band was the outer 10%, so no candidate was recorded;
  the opinion row also failed the one-line-height separation test. Across every other fixture
  the outermost furniture row lies at 0.91–0.96; between 0.80 and 0.90 there are only
  chapter-opening numbers (9/11 pages 19/65, which never repeat) and first body lines that
  their paragraphs follow directly.

## What changed

- `ReflowBlock.Content.footnote(InlineText)`; `EPUBWriter` serializes it as
  `<div class="footnote" role="doc-footnote"><p>…</p></div>` with `div.footnote { font-size:
  0.85em; }`. All six candidate markups pass EPUBCheck; `aside epub:type="footnote"` was not
  chosen because reading systems that implement pop-up notes hide such asides from the flow
  unless a `noteref` links to them, and notes are not linked (see gaps).
- `FootnoteDetector.layout`: the separator is a line of three or more dash characters
  (`—`, `―`, `–`, `_`, `-`) after at least three lines of a body size of at least 4 pt; every
  element after it must be an untagged, proportional, non-separator text line at most 90% of
  that body size, within [−0.25, +3] note sizes of the separator's left edge, descending at
  gaps in [−0.2, 0.8] note sizes; a note opens with a first run that is a superscript of one to
  three digits (plus optional space) and the markers count up; a marker-less first line is a
  continuation only when `continuesNote` is set. Anything else returns nil and the page keeps
  its previous reconstruction.
- `LayoutReconstructor.blocks`: the body is everything before the separator; notes are
  emitted after the body with the marker run reduced to its digits (`<sup>2</sup> See also`).
  `joinContinuedFootnote` (called by the pipeline after `appendPage`, never at a chapter start)
  joins a page's first marker-less note to the previous page's last note, moving that page's
  standalone boundary inline, so the completed note precedes the page's body. `appendPage`'s
  own join rule is untouched.
- `isDetachedMarker`: a one-to-three digit line below 80% of body size, starting within
  [−1, +0.5 body] of the previous line's right edge, raised at least 20% of that line's box
  above its bottom and no higher than its top, is appended to the paragraph as a superscript;
  the previous line stays the geometry reference for the next line.
- `FurnitureDetector`: the top band is the outer 20%; beneath an outermost row whose lines are
  all candidates, the next row inward (within three of its line heights, at least half a line
  height or 0.6% of the page clear of the body) is a second-row candidate that `apply` removes
  only when every line of the row above it is removed. `resolve`'s three-page repetition,
  position and typography rules are unchanged.
- `tools/check_corpus_content.py`: a `notes` expectation (text inside one `role="doc-footnote"`
  block on that page); the reader records note text per page.

## Verification

`Tests/PDFReflowLibTests/FootnoteTests.swift` (10 tests) and two additions to
`FurnitureTests.swift` are described in `doc/regression-testing.md`. The committed sources
have no footnote block, so the new suite cannot compile against them; the before evidence is the
corpus contract below and the page text in this record.

- `swift test`: 230 tests pass (3 suites).
- `scripts/check-all.sh --fast`: 230 Swift tests, 144 Python tests, 8/8 concurrency trials,
  6 fixture conversions and 13 policy conversions with 15 rejection cases pass.
- `python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow --epubcheck
  /opt/homebrew/bin/epubcheck --output <new> --case …`: `scotus-loper-bright-2024` passes
  EPUBCheck and 63 content checks on pages 2, 7, 13, 60, 61, 97, 98; `gpo-911-2004`,
  `fed-explained-2021`, `faa-phak-8083-25c` and `wallace-algebra-2010` pass unchanged. The same
  lane with the baseline converter fails the Loper contract with 36 errors: `——————` and the
  running heads present on all five pages, every `notes` phrase missing, the page-97/98 note
  continuation absent, the page-13 and page-97/98 marker contexts wrong, page 98's order wrong
  and no `furnitureRemoved` warning.
- Before/after page comparison (every paragraph, script span, `<pre>` count and image byte of
  every page through `tools/check_corpus_content.read_pages`) for all thirteen English corpus
  books converted with both binaries.

## Before and after

Loper Bright: 112 of 114 pages change. 302 running-head lines are removed: 83 bare folios,
57 `Cite as: 603 U. S. ____ (2024)`, 38 `LOPER BRIGHT ENTERPRISES v. RAIMONDO`, 16
`N LOPER BRIGHT …` (folio and title in one line), 35 `Opinion of the Court`, 33 `GORSUCH, J.,
concurring`, 33 `KAGAN, J., dissenting`, 7 `Syllabus`; `furnitureRemoved` is reported on 112
pages. Pages 45 and 47 (the four-page Thomas concurrence) keep `N LOPER BRIGHT …` and
`THOMAS, J., concurring`, and page 46 keeps its folio and opinion row, because each alternating
head occurs on only two pages there: the three-page minimum is unchanged. Twenty-one pages
carry 22 footnote blocks (13, 15, 21, 23, 25 ×2, 36, 40, 56, 60, 61, 62, 67, 76, 77, 79, 89, 97,
98, 99, 101, 103); five continuations are joined to the previous page's note, each read against
the source as a mid-sentence continuation: 67→68 `cites also / serve the Constitution`,
89→90 `unless “Congress / clearly states that it is.”`, 98→99 `only to history. / But as I
will explain below`, 99→100 `(1947) / (Dickinson); ante`, 101→102 `By / the early 20th
century`. No `——————` remains; the seven `<pre>` blocks (`* * *` and the #39 leftovers) are
unchanged; there are no images.

Page 13 after: `… the F/V Relentless and the F/V Persistence.<sup>1</sup> These vessels use …
(about 10 to 14 days, as` in one paragraph, then `<div class="footnote" …><p><sup>1</sup> For
any landlubbers, “F/V” is simply the designation for a fishing vessel.</p></div>`. Page 60:
the body ends `not ours, that controls.` and note 2 follows. Page 97/98: one note element
`<sup>2</sup> The majority tries … for courts<span … id="page-98"/> rather than agencies …
deferential standard.`, then page 98's body ending `Vermeule 207.<sup>3</sup>`, then note 3.

Other books: 9/11, FAA, Wallace, The Fed Explained, Dietary Guidelines, Our Flag, CDC, Blue
Book, Census, NBS and Replay Clocks are identical page for page and image for image (528, 599,
2,047, 315, 28, 147, 42, 425, 37, 8 and 72 images byte-identical; `<pre>` counts unchanged).
USGS copper page 2 is the only change outside Loper Bright: the reference marker `8` after
`3.5 billion tons of copper.` (6.48 pt, 4.8 pt above its line's bottom) was a standalone
`<p>8</p>` and is now `<sup>8</sup>` inside its sentence; the following `Substitutes:`
lead-in, which that stray paragraph had separated by accident, now joins the preceding
paragraph as the page's other section lead-ins already do, because the source adds only 0.3 pt
of paragraph spacing (8.0 pt between boxes versus 7.7 pt inside a paragraph). The page's
contract (ordered text, paragraphs, script, image region, absent text) still passes.

An earlier form of the detached-marker rule without the raised-inside-the-box requirement
changed four Blue Book OCR table pages (121, 125, 183, 311), where same-baseline cell numbers
such as `110` were appended as superscripts; the final rule leaves those pages identical.

## Post-merge results (branch tip e1cbc0d, #45 body continuation)

With #45's reading-order anchors, `isSkippable` treats `.footnote` blocks like images and
captions, `continuation`'s walk-back also steps over a note that a join moved behind the
paragraph of an earlier page, `endsColumn` ignores smaller-type lines under a dash separator
(the note lines had counted as prose below the body's last line and refused every join), and
`joinContinuedFootnote` finds the previous note by block rather than by the standalone marker,
which a body join has already moved inline. A footnote trailing a continued paragraph is
placed after the joined paragraph, not ahead of it as captions and folios are: the note's
reference is inside that paragraph (page 13's `Persistence.<sup>1</sup>`, page 25's notes 5
and 6 on the 24→25→26 chain), so the caption placement would emit note text before its
marker. The note then sits past the inline boundary and page navigation reaches it from the
next page; the Loper contract checks page 13's note on page 14 for that reason.

`compare_joins.py` against the e1cbc0d converter on all thirteen English books: 9/11 240→240,
FAA 129→129, Wallace 24→24, Fed 30→30, Our Flag 3→3, Blue Book 2→2, Census 3→3, Replay 3→3,
DGA/CDC/NBS/USGS 0→0 joins with identical text on every page (USGS page 2 keeps the `<sup>8</sup>`
change above). Loper Bright 0→66 joins gained, none lost, every one read as a mid-sentence
continuation (13→14 `(about 10 to 14 days, as / opposed to the more typical 2 to 4)`, 25→26
`“reasonable.”6 When the best reading / of a statute`, 54→55 `opin-/ion`, 79→80→81 a page-long
paragraph past page 79's note, 97→98 and 98→99 the note continuations). Counts: 549 contract
checks on 123 pages; 253 Swift and 159 Python tests; `check-all --fast` and all 15 lane cases
pass.

## Remaining gaps

- Notes are not linked to their references (`epub:type="noteref"`); links would need the
  writer to know a note's spine file before its reference is serialized. The reference stays a
  plain superscript and the note an unlinked block.
- A page whose note area is only a continuation with no body above it, symbol markers
  (`*`, `†`) and multi-column footnotes keep spatial prose. The USGS copper notes, which are
  set off by white space and a type-size drop with no rule drawn at all, are admitted by the
  unruled form added in #61; see the
  [section lead-in evidence](../section-lead-ins/record.md).
- A note behind a continued paragraph is attributed to the next page by the page list, because
  the boundary sits inside the paragraph it follows.
- A four-page opinion whose alternating heads occur twice each keeps them (pages 45–47).
- USGS section lead-ins set with under 1 pt of paragraph spacing merged into the preceding
  paragraph; a bold run-in label is paragraph evidence from #60, recorded in the
  [section lead-in evidence](../section-lead-ins/record.md).
