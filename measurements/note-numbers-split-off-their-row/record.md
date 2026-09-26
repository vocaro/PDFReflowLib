# A raised note number PDFKit returns as a line of its own is read with its row

Measured under [#314](https://github.com/vocaro/PDFReflowLib/issues/314), baseline `af18cfb9`,
2026-09-25, macOS 27.0 (26A428) / Xcode 27.0 (27A266a), arm64, release CLI, sources from the
pinned corpus cache. Every one of the 24 manifest documents was converted with the flags its
manifest entry asks for (`evaluate_real_document.conversion_flags`) and
`--package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`, once with
`af18cfb9`'s binary and once with this change; only each EPUB's hash, XHTML and package document
were kept, and the EPUBs were discarded as they were read. Page-level evidence comes from a debug
build of the same change that printed each page's `selectionsByLine` lines (bounds, text, and
each run's size and `kCTBaselineOffsetAttributeName`), the rows `SplitScriptRows` joined, and each
page's `PageTypography`; the debug code is not part of the change.

## What was wrong

`selectionsByLine` breaks a printed row at a full stop that a raised note number follows, where
the page sets the number by a text matrix of its own. The 9/11 report's page 145 shows the stop
with its own `Tj` after a `TD`, then `7.175 0 0 7.175 294.4246 238.7483 Tm (105)Tj`, a
two-hundredth of a point inside the stop's end, then `10.25 0 0 10.25 306.2004 236.4933 Tm
(This made it )Tj`; PDFKit returns `…to the Washington Times.` and `105 This made it`, the second
starting where the first ends. The number's run is 7.17 points at +2.25; the words after it are
10.25 points at 0. Each piece became a line, so the number opened a paragraph of its own:
`…the Washington Times.</p><p><sup>105 </sup>This made it</p><p>much more difficult…`. Where the
number closes its row alone, it came back as a line of its own placed by its rectangle, and was
written a plain digit: Loper Bright's page 13, `…the F/V Persistence. 1</p><p>These vessels…`,
whose footnote 1 then had no raised reference to link from. `SplitScriptRows` (#303) joined only
rows of stacked scripts and left these single-level pieces as PDFKit returned them.

## The rule

A piece now also joins the row it continues when the row ends in a body glyph and every script run
the piece opens with, before its first host-size glyph, stands above the row's baseline by more
than max(0.5, 12% of its own size), at one level. Every other condition of #303 still holds: the
piece starts at the row's end (at most max(1, 25% of the host's size) right of it, at most 0.5 left,
as there are no closing scripts to start under), any words it carries sit on the row's baseline at
the host's size, and every script is within a first level's reach. Two further readings follow from
what the corpus showed:

- **A stop PDFKit returns on its own.** NCA5's page 145 comes back as `…–1.3 ± 0.7 W/m²`, `.` and
  `² Since NCA4, the`. The stop is a body-size glyph on the baseline between the row and the piece,
  which #303's `interrupted` rightly refuses to jump; read without it, the build the issue
  describes left it behind, after `Since NCA4, the`. A line of one or two punctuation marks at the
  row's size, on its baseline and starting at its end, is now the row's next character, taken only
  together with a piece that follows it: `W/m<sup>2</sup>.<sup>2</sup> Since NCA4, the`.
- **A link's underline.** NCA5 underlines its links with a 4-point bar from the baseline down,
  and carries it to the stop a note number follows: page 26's `Table 1.1.9.` then `12 Where
  documented…` (the bar spans x 116.33–412.13, the baseline is y 133.1 by `mutool draw -F stext`,
  the bar 129.1–133.1). #303 refuses any painted mark within the scripts' reach, since a fraction's
  bar, a vinculum or a table's rule there makes the glyphs something else. Beside a single raised
  mark, a bar lying wholly under the baseline (within max(0.5, 12%)) is now the row's own
  underline; a bar above the baseline still keeps the pieces apart. Pages 26, 952, 1747 and 1825
  join by this.

A number that opens a line — a page-foot note's own, a line-initial marker in a list of notes —
starts at no row's end, and is never a piece of the line above it.

## What the joins moved downstream

Joining a piece removes a small-type line from the page and makes a short row whole. Four page and
book statistics read those lines, and each was checked against the source:

1. **The notes' own leading (Hebrew Shakespeare, page 87).** The page sets a letter at 9.5 points
   on 13 and notes at 7 on 9. `PageTypography.wrappedProseRuns` admits a run only if every row but
   the last fills 75% of the measure; PDFKit's split left the letter's row `title So He Drove Out
   the Man ,` at 121.53 of 162.05 points, 74.99%, so the letter never qualified and the one
   secondary-leading slot went to the notes (`[7: 9.0]`). Whole, the row admits the letter, the slot
   went to it (`[10: 13.0]`), and measured against 13 points the note `18 The title…`, 12.75 points
   under `…The Publisher.` and 12.6 the most one 9-point step allows, ran on from it. A smaller size
   that sets wrapped prose of its own now keeps its own leading where it differs from the page's
   (`[10: 13.0, 7: 9.0]`), which is what `additionalLeading` said it did ("nor borrow that prose's
   looser spacing"). Across the corpus this entry changes only that note: the Fed's pages 46 and 95
   gain `8: 10`, equal to their page leading, and are not stored.
2. **The page body (Hebrew Shakespeare, physical pages 91 and 476).** `bodySize` weighs a line's
   characters at its first glyph's size. On these pages the 7-point notes and the 8-point
   translation tie: 931 and 926 characters on page 91, 788 and 787 on page 476. The joined note
   numbers (6 and 48 characters, counted at 4.8 and 5.7 points while they were lines of their own)
   now count with the 8-point rows they belong to, exactly as the book's unsplit rows count theirs,
   so the body becomes 8 and the heading threshold 10, above the 9.5-point Hebrew verse, which
   reads as 49 paragraphs instead of `<h2>` headings. The verse is verse: the source prints it
   beside its translation, and pages 89, 474, 475 and 478 of the same layout already read it as
   paragraphs. The same tie still makes 1,476 verse lines headings on 93 other pages, filed as
   [#325](https://github.com/vocaro/PDFReflowLib/issues/325).
3. **The spine's direction (Hebrew Shakespeare).** `EPUBWriter` stated
   `page-progression-direction="rtl"` for a book most of whose text blocks read right to left. The
   book sets its Hebrew verse a short block to a line beside English paragraphs: 49.5% of its
   blocks read right to left at `af18cfb9`, and 50.3% once 444 split pieces of English stopped
   being blocks of their own, which turned the spine. Its letters are 27.5% Hebrew, and the book
   (UCL Press, no `/ViewerPreferences /Direction`) is bound left to right. The spine now follows
   the book's letters, the judgment `ArabicText.readsRightToLeft` makes of each block: the Hebrew
   book stays left to right, the Arabic guide (94.9% Arabic letters, 96.1% of its blocks) stays right
   to left, and no other document carries a right-to-left letter.
4. **Reading order and joins that follow the whole row.** Loper Bright's page 13 now carries its
   sentence onto page 14 (`…(about 10 to 14 days, as` / `opposed to the more typical 2 to 4)`),
   and `PageFootnotes` links footnote 1, written as an aside after the page's `——————` rule and
   ahead of the paragraph that runs on to the next page, as on its pages 23 and 76. The 9/11
   report's page 220 joins `brief=` and `ing slides`, the line-end hyphen of the row the number
   interrupted, into `briefing`. The Hebrew Shakespeare's physical page 272 sets the speaker `milcah` before `If I die
   before you die, dress my corpse, Milcah,`, where the page prints it at `Do not bring forth such
   words from your lips.` (rendered and read against the source); with the stray `140` line gone,
   it stands at its own speech.

## What it moves across the corpus

Every block of every manifest document, baseline against this change:

| Book | joins (#314 rule) | changed regions | what they are |
| --- | ---: | ---: | --- |
| ucl-hebrew-shakespeare-2017 | 495 | 467 | 323 a note number joined and raised (`angry . 5` → `angry .⁵`), 117 an already raised number joined and the row's wrap run on, 17 only the space the old row join set before a mark, 8 the page-body flip on physical pages 91 and 476 (49 verse headings to paragraphs), 2 the speaker `milcah` moved to its speech on physical page 272 |
| noaa-nca5-2023 | 27 | 16 | 15 a note number joined and the paragraph run on (pages 26, 144, 145, 162, 163, 174, 177, 462, 659 with two numbers, 664, 945, 952, 1082, 1747, 1825), 1 only a space before a mark (page 1774); 10 glossary joins changed no byte, the old row join having already read those pieces as one paragraph |
| gpo-911-2004 | 2 | 2 | pages 145 and 220, each three paragraphs to one; page 220 also closes `brief= ing` |
| scotus-loper-bright-2024 | 1 | 2 | page 13: the `1` raised, footnote 1 linked and written as an aside, the paragraph carried onto page 14 (two regions of one change: the paragraph moved after the aside) |
| usgs-mcs2025-copper | 1 | 1 | page 2: `copper. 8` → `copper.⁸` |
| the other 19 books | 0 | 0 | byte-identical EPUBs |

Joins count rows the rule took (NCA5's 28th join, `CO₂` and its 180, is #303's and was already on
`af18cfb9`). Every changed region holds a note mark except seven of the eight heading regions of
pages 91 and 476, explained above. Every region carries the same text in the same order, with a
space or a line-end hyphen fewer, but for the two moves described above, Loper Bright's footnote
and the Hebrew speaker label; and the Hebrew book's package document is unchanged. None of the five books recognizes a page, and the ten that do (the CDC comic, the
Census report, the Blue Book, the Fed, Our Flag, Warren and its excerpt, the Earthdata slides, the
Hindi reader and Agricultural Research) convert byte-identically, so no difference here comes from
recognition.

## What it does not reach

Six note numbers in the corpus still break their paragraph, filed as
[#324](https://github.com/vocaro/PDFReflowLib/issues/324): the 9/11 report's page 376, where the
page draws `41` before the line it closes and PDFKit returns one line, `41on in the war on
terror.`; NCA5's page 328, where the page sets the stop before `190` in a 12-point Times inside a
10-point Lora line, so the row's largest glyph is punctuation and it has no body to host a piece;
and NCA5's pages 145, 146, 322 and 1752, where the number comes back with no words after it and
every NCA5 rectangle is 1.385 ems tall against PDFKit's substitute Helvetica's 1.0, so no piece of
scripts alone can be placed by measurement.

## Pins

`corpus/regressions.json` pins the 9/11 report's page 145, NCA5's pages 145 and 163, Loper Bright's
page 13 (the paragraph, the raised `1`, footnote 1 as an aside, the continuation onto page 14), the
copper summary's page 2 and the Hebrew Shakespeare's pages 87 and 91, each phrase taken from
`pdftotext -layout` and the rendered page. `af18cfb9`'s binary fails 12 of those checks (copper 2,
Loper Bright 4, 9/11 1, NCA5 2, Hebrew 3); the rest pin what it already read right, the raised
number's context where it was already a superscript. Page 87's note is pinned by a new `paragraphOpenings` check,
since a note that runs on from the line above it still holds every word of itself; a build of this
change with the notes' own leading switched off fails it and nothing else. The five cases pass the
corpus runner with no content error, and each one's XHTML equals the survey's.

## Commands

```
swift build -c release --product pdf-reflow
# per manifest document, with its manifest flags:
pdf-reflow <source> out.epub [--language TAG] [--no-ocr] \
  --package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck "$(command -v epubcheck)" --output <dir> --case <id>
```
