# A rule down the margin, read as a column of letters

Measured under [#264](https://github.com/vocaro/PDFReflowLib/issues/264), baseline `a1bbea8`,
2026-09-22, macOS 27 (Darwin 27.0.0) / Swift 6.2 toolchain, arm64, release CLI at library
defaults. The source is `corpus/cache/CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf`
(SHA-256 `90e05e77fc088c29758c2ddda514c0c12f317e5686ee213d348db2f9da152ee3`, 312 pages), and the
page traces are the reading `NativeTextReader.lines` returns, captured with
`tools/probes/capture-layout-fixture.swift`. Block counts are every `<p>`, `<pre>` and `<h*>` of
the converted book outside its navigation document; character counts are the non-whitespace
characters inside those blocks.

## 1. What the page draws, and what the reading makes of it

Project Blue Book is a scan with an inherited recognition layer. Every page is one placed image —
`GraphicsReader` reports a single region, `x[1.4..612.0] y[1.2..786.7]` on page 7 — so the rule the
book paints down its outer margin is *ink*, not a painted path the graphics reader could own. The
recognition read that rule as a column of capital `I`s set in Times-Roman at 29.6 to 33.0 points,
against a body of 7.0 to 8.0 points, segmented at about a 35.5-point pitch down the page: on page 7
at `y` 752.9, 717.6, 681.4, 645.9, 610.4, 574.6, 538.8, 502.6, 466.9, 431.6, 394.9, 359.1, 324.0,
288.1, 250.9, 215.6, 180.3, 145.5, 109.0, 73.9, 39.9 and 4.4.

PDFKit puts each mark in the same line as the type beside it. Page 7, as read at `a1bbea8`:

| Line | Text | Rectangle | Size |
| ---: | --- | --- | ---: |
| 2 | `I LIST OF ILLUSTRATIONS` | `y[681.4..712.9]` | 31.5 |
| 4 | `Figure 38 Comparison …Areas of the` | `y[656.8..663.8]` | 7.8 |
| 5 | `I South Farwest Region . 54` | `y[645.9..677.4]` | 31.5 |
| 6 | `I Figure 39 Diagram of a Celestial Sphere.` | `y[610.4..641.9]` | 31.5 |
| 7 | `56` | `y[610.4..641.9]` | 7.6 |

Three separate damages, and the third is the one no rule downstream could have reached:

- **The size.** A line's size is its first character's, and the mark is that character, so a
  7.8-point line is reported at 31.5 points. The space after the mark carries the mark's font too,
  so cutting the letter alone would leave the size where it was.
- **The rectangle of the line the mark is in.** `y[645.9..677.4]` is the mark's box, not the text's.
  The wrap `South Farwest Region . 54` stands in `y[649.6..654.5]` and therefore *below* the entry
  it continues, `Figure 38 …of the` at `y[656.8..663.8]`; reported by the mark's box it sorts
  **above** it, which is the reordering the issue names.
- **The rectangle of every other piece of the same printed row.** PDFKit gives each piece of a row
  the height of the tallest piece in it, so the page number `56` — which holds no mark at all — is
  reported at `y[610.4..641.9]` although its own characters stand in `y[632.6..637.9]`. On page 7
  that is true of thirteen page numbers.

Page 22 carries the rule down the **right** margin (`x[598.8..617.8]`), so the mark is the line's
last character: the size is undamaged and only the boxes are wrong. Every line of the page's hanging
definitions is reported 31.9 to 32.6 points tall over a 10.5-point body, which is why
`preceding identifications. An explanation of their use follows: I` shared a row with
`INSUFFICIENT INFORMATION -` and `This identification category`.

### Why this is not #207

[#207](https://github.com/vocaro/PDFReflowLib/issues/207) reads a thin rule the page **paints**
against the printed row it strikes, and may only keep a painted region from claiming a line
(`LayoutReconstructor.expanded`). Nothing of that machinery applies here, and not because of a
threshold: a recognized rule is painted nowhere. `GraphicsReader.read` on page 7 returns one
region, the page image. By the time any ownership rule runs there is no rule left to own — only a
line whose rectangle is already wrong. It is a different mechanism, and the correction belongs
where the box is formed.

## 2. Where the true geometry comes from

Three readings were tried against the damaged lines before one held.

- **The page's own shows.** `NativeSpacingReader.read` returns **0** shows for page 7. A recognized
  layer is drawn with `Tr 3`, and the reader disqualifies any page that sets a text render mode it
  does not model. This is true of every page that can carry a recognized rule, so the content
  stream supplies nothing here.
- **Re-reading the page with the margin column excluded.** `page.selection(for:)` over
  `x[21.5..612.0]` drops the `I` glyph but not the damage: line 5 comes back as
  `" South Farwest Region . 54"` still in `y[645.9..677.4]` at size 31.5, because the space after
  the mark carries the mark's font and PDFKit's line-fragment height is unchanged.
- **`PDFPage.characterBounds(at:)`.** This holds. It is indexed over the page's characters *without*
  the separators the reading synthesizes between rows, which is exactly the offset the lines' own
  strings reach when laid end to end — the relation `NativeTextReader.lineRanges` already reads in
  the other direction. Over page 7's 50 lines and 1,457 characters, the union of a line's character
  boxes and PDFKit's own rectangle for it have midpoints within 0.2 points on every line the rule
  did not reach, and differ by 2.4 to 9.1 points on every line it did. The union runs about a point
  shorter than PDFKit's rectangle on a 7-point body (page 7 line 4: chars `y[657.0..663.4]`,
  reported `y[656.8..663.8]`), which is the padding a fragment carries; a corrected line is given
  its characters' own extent and the difference is immaterial beside the 24.5 points the rule was
  adding.

## 3. The rule, and what refuses it

`MarginRuleMarks` decides everything from the page's own reading. A **mark** is a character that is
`I`, `l` or `|`; is drawn at least 2.5 times as tall as the median of the page's own character
boxes; is at least twice as tall as it is wide; and stands in the outer twentieth of the crop box on
one side. **Four marks sharing one column are a rule.** A line holding marks is measured by the
characters that remain once its marks and the whitespace beside them are cut; a line that is rule
and nothing else is dropped; a line holding no mark but sharing its row with one that does, whose
reported box is at least twice as tall as the characters it holds, is measured by its own characters
too.

Only a page whose lines already show a rule glyph at one end, in the outer twentieth, on four lines
or more is measured character by character at all. Over the twenty-four cached sources:

| Source | Pages | Suspected | Rule found | Lines cut | Lines dropped | Rows re-measured |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| cia-blue-book-14-1955 | 312 | 279 | **241** | 855 | 3,876 | 1,036 |
| gpo-warren-1964 | 920 | 11 | 0 | 0 | 0 | 0 |
| nbs-jres-geltman-1977 | 7 | 1 | 0 | 0 | 0 | 0 |
| the other 21 sources | — | 0 | 0 | 0 | 0 | 0 |

The twelve pages of two other books that reach the cheap test are declined by the character test and
left exactly as they were read. **Not one of the 3,876 dropped lines carries more than a single
character**, and every one of the 855 cuts removes only the mark and the space beside it:

```
p18  0/2  "MULTIPLE OBSERVERS. I"            -> "MULTIPLE OBSERVERS."
p18  0/2  "1001 to 1500 reserved for 1949 I" -> "1001 to 1500 reserved for 1949"
p103 2/0  "I cases. Having culled the cream" -> "cases. Having culled the cream"
```

What the rule refuses, measured as unit tests in
`Tests/PDFReflowLibTests/MarginRuleMarksTests.swift`: three marks in a column; a mark-shaped letter
inside the measure; a tall narrow `T`; a mark as wide as it is tall; a mark read in the middle of a
line, where nothing can stand between a margin and the type beside it; and **a line genuinely that
tall, whose own characters are that tall, which keeps its box**.

## 4. What it changes

`scripts/check-all.sh --fast` passes at `a1bbea8` + this change (exit 0, ten gates). The corpus lane
(`tools/run_corpus_regressions.py --jobs 4`, EPUBCheck 5.x) reports `runPassed: true` and
`content-assessment.json` `passed: true` for all eighteen covered cases, both before and after;
`cia-blue-book-14-1955` keeps its nine content checks, zero spine boundaries crossed and no errors.

Compared entry by entry with `tools/epub_identity.py` against a release binary built from `a1bbea8`,
**seventeen of the eighteen books are byte-identical**. Only Blue Book moves:

| | baseline | with the fix |
| --- | ---: | ---: |
| Blocks | 24,909 | 22,889 |
| Non-whitespace characters | 608,818 | 610,794 |
| `furnitureRemoved` warnings | 278 | 219 |
| `unverifiedTextLayer` warnings | 312 | 309 |
| `implausibleTextLayer` / `ocrUsed` | 0 / 0 | 3 / 3 |
| Recognized pages | 0 | 3 |
| Images | 421 | 423 |

Two thousand fewer blocks with two thousand *more* characters: about 4,700 `I`s leave the book and
the text that remains joins into paragraphs instead of fragments. Page 22 reflows as 13 paragraphs
where it was 34 fragments, and its hyphens repair — `con\u{ad} I / sideration` becomes
`consideration`, `ob\u{ad} I / server` becomes `observer` — because the wrap now stands beneath the
line it continues. Page 7 loses its `I I I I I I I I` paragraph and reads

```
Figure 38 Comparison of Evaluation of Object Sightings in the Strategic Areas of the
South Farwest Region . 54
```

in that order, which is the defect the issue was filed on.

Three pages change their recognition, and for the same reason: 142, 148 and 190 are dense scanned
tables whose inherited layer is mostly the margin rule. With the marks counted as text the layer
passed the plausibility measure; without them the measure sees what is really there — `about 82% of
the page's text-shaped ink (27 rows) lies outside its lines, which hold 15 English words` — and the
page is recognized instead. Page 142 goes from 350 characters of `I` to 2,631 characters of table
transcription, page 190 from 414 to 2,384. The two extra images are those pages' own page images,
and the renumbering they cause is what flips 270 image entries between `.png` and `.jpg` under the
automatic encoding default (#242).

**The hung-entry rule of [#160](https://github.com/vocaro/PDFReflowLib/issues/160) still does not
reach pages 5 and 7**, and this change does not claim it does: those pages' entries run leaders out
to a page number, so a wrap does not stop a whole body short of its entry's right edge, and the two
pairs page 7 hangs cleanly remain below the three the rule requires.

What the corrected geometry exposes underneath the rule is filed as
[#277](https://github.com/vocaro/PDFReflowLib/issues/277): with the gutters of the three-column
contents pages visible for the first time, `columnRuns` (#174) reads short bands of them column by
column, so page 7 reflows six entries and then their six page numbers, and page 5 does the same in
runs of two to four. The rest of both pages reads row by row.

## Reproducing

```sh
ln -s "$PWD/corpus/cache" <worktree>/corpus/cache
swiftc $(python3 tools/pdfreflow_tools/swift_sources.py capture-layout-fixture.swift) \
  -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture cia-blue-book-14-1955 7 /tmp/blue-7-layout.json
swift build -c release
python3 tools/run_corpus_regressions.py \
  --converter "$(swift build -c release --show-bin-path)/pdf-reflow" \
  --epubcheck "$(command -v epubcheck)" --output /tmp/corpus-264 --jobs 4
python3 tools/epub_identity.py \
  --baseline-epub /tmp/corpus-264-baseline/<case>/<case>.epub \
  --candidate-epub /tmp/corpus-264/<case>/<case>.epub
```
