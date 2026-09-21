# A box a page cut a paragraph with, a row split after an exponent, and Our Flag's lost hyphens

The three items of [#203](https://github.com/vocaro/PDFReflowLib/issues/203), measured on `main`.
The record the issue cites, `measurements/box-cuts-and-split-row-spaces/record.md`, was written on
the abandoned coordination branch and is not in this tree; it is readable as
`git show 798b3c3:measurements/box-cuts-and-split-row-spaces/record.md`, and none of its code is
on `main` ([decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md)). Every
number below was measured here, on this tree.

Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), arm64, shared with other agents' conversions.
Library source at `4d5d86d` (baseline) and at `4d5d86d` plus this change (candidate). Release
CLIs, library defaults, `--package-identifier urn:uuid:test --modification-date
2026-01-01T00:00:00Z` for the standalone conversions.

| Binary | SHA-256 |
| --- | --- |
| baseline, `swift build -c release` at `4d5d86d` | `15ca6d3e36cfcbeb4c26664291e4321ec036b06e34fea42b7d511774cd5f9406` |
| candidate, this change | `e185a9bd36501606ec9446ca8ec08e8c1e60ebccbc17a8ed8e593fcafe1cec54` |

Both binaries converted every case of `tools/run_corpus_regressions.py --jobs 4` with EPUBCheck;
each case's `result.json` was opened and its `runPassed` read individually, never through a pipe.
The per-book comparison below reads each EPUB's block stream (paragraphs, preformatted blocks,
headings, figure captions and standalone page markers, in spine order) and diffs the two.
`tools/compare_conversion_runs.py` was not used: it refuses a pair without a capability-probe
receipt, and these lanes were run without `--environment-probe`.

## Item 1: a box at the foot of a page cuts the paragraph that runs past it

### What the baseline produces

The Fed prints Box 3.5, *Gauging Monetary Policy through the Fed's Balance Sheet*, over most of
page 47, and the page's last paragraph names it:

> Finally, the Federal Reserve's actions to implement monetary policy are reflected in the Federal
> Reserve's balance sheet. … (See box 3.5 for more details about key line items of the Federal
> Reserve's balance sheet.) The vast major-

`ity of the Federal Reserve's assets are securities holdings.` opens page 48. On the baseline the
two are separate blocks with the word broken between them, and the box reads *after* the sentence
that refers to it:

```
<p>… (See box 3.5 …) The vast major-</p>
<figure>…Box 3.5…</figure>
<span epub:type="pagebreak" id="page-48" aria-label="44"/>
<figure>…page 48's running-head rule…</figure>
<p>ity of the Federal Reserve's assets …</p>
```

### Why

`LayoutReconstructor.appendPage` joined `blocks.last` to `pageBlocks.first` and required both to
be paragraphs. Page 47's last block is the box's crop and page 48's first block is that page's
running-head rule — every Fed page emits one, a 1,240 × 10 pixel strip — so the two paragraphs
were never adjacent and the join never ran. Neither #177's `continuationPastBox` nor any part of
its cross-page walk is on `main`.

### The rule

A cross-page join steps over the image blocks between its two halves, and each image it steps over
keeps the side of the page boundary its own page is on: the earlier page's before the joined
paragraph, the later page's after it. The marker the join sets stands inside the paragraph, so
this is the only placement that leaves every block on its own page — placing the box after the
paragraph would carry page-47 content past the page-48 marker. One condition is added, because
reaching past a picture claims more than standing beside the boundary did: a block reached past a
picture must read as the page's prose (`readsAsSentence`). Reconstruction's held-back tail grows
to match (`amendableTail`), which is what
[decision 0011](../../doc/decisions/0011-a-picture-keeps-its-side-of-the-page-marker.md) records.

The candidate produces:

```
<figure>…Box 3.5…</figure>
<p>… (See box 3.5 …) The vast major<span epub:type="pagebreak" id="page-48" aria-label="44"/>ity
   of the Federal Reserve's assets are securities holdings. … increases the level of reserves.</p>
<figure>…page 48's running-head rule…</figure>
```

### The folio the first draft took

Without the prose test, the join also fired where the previous page's last block was a folio and
the next page opened with a crop: the 9/11 report produced `145 school, KSM left Kuwait to enroll
at Chowan College`, and Our Flag produced three of the same shape on pages 11, 23 and 24. The real
continuation on 9/11 page 163 — `…following his graduation from secondary` — is the block *above*
the folio, which is #45's reading-order anchor and is not ported. `readsAsSentence` on a block
reached past a picture removes all four; a folio that is simply the last block is joined exactly as
it was before, so #45's own defect is neither fixed nor widened.

### Every new cross-page join, by book

Thirty paragraphs join across a boundary that did not before. Each was read against the source
text (`pdftotext -layout` on the cited pages).

| Book | Joins | Reading |
| --- | ---: | --- |
| `fed-explained-2021` | 12 | pages 21→22, 40→41, 47→48, 55→56, 93→94, 97→98, 98→99, 100→101, 103→104, 106→107, 118→119, 129→130. All correct: `…four times` / `a year`, `…The vast major-` / `ity`, `…all institu-` / `tions`, `…the Reserve Banks pro-` / `cess`, and eight more of the same shape |
| `gpo-911-2004` | 7 | 373→374, 489→491, 491→493, 495→496, 571→572, 577→578, 582→583. All correct; four are broken words (`num-`/`bers`, `Secu-`/`rity`, `Domes-`/`tic`, `offi-`/`cers`, `delib-`/`erately`, `per-`/`haps`) in the endnotes and the final chapters |
| `census-rrs2002-01` | 5 | 4→5, 5→6, 6→7, 9→10, 18→19. All correct; page 4 ends `The mean parameters of the component distributions are` and page 5 opens `solved by a nonlinear optimization method`, which is what the source prints |
| `wallace-algebra-2010` | 4 | 120→121, 288→289, 343→344, 429→430. **All four are wrong**, in one way. See below |
| `usda-ars-agresearch-2012-11` | 1 | 16→17, correct: `…saving as much water` / `as possible and keeping crops viable` |
| `cia-blue-book-14-1955` | 1 | 208→209, two lines of the report's unverified OCR layer over a handwritten table (`#216`). Garbage joined to garbage; no reader-visible loss |
| the other twelve | 0 | identical |

Wallace's cost is known and recorded. On that book a crop has already taken the lines that
actually continue the sentence, so the two halves the join brings together were never consecutive.
Page 288's last printed prose is `…simplifying the first root, 6√5. The trick in this`, all of
which goes into a display crop, and the candidate joins the paragraph above that (`…the product
rule of radicals`) to page 289's first surviving line (`fastest method, is to find perfect
squares…`). Page 343→344 loses `values into x = (−b±√(b²−4ac))/2a`; page 429→430 loses `b are the
other two sides (legs), then we can use the following formula, a² + b² = c²`; page 120→121 joins
two rows of one worked example across the folio.

No word moves and none is lost. What changes is that two fragments the crops had already broken
read as one paragraph instead of as two blocks, which asserts a continuity the page does not have.
A variant that required a picture on the *earlier* page's side was measured on the same three
books: it removes three of Wallace's four and eight of the Fed's twelve, so it was rejected. What
these four need is the reading-order anchor #45 describes — the join should reach the last line the
page actually printed, crop or no crop — which is not ported and is not this change. Filed as
[#267](https://github.com/vocaro/PDFReflowLib/issues/267).

### The page label the joins exposed

The Fed states `/PageLabels`, and its page 48 prints `44`. `EPUBWriter` passed `pageLabels` only
to the standalone-marker path, so all twelve of the Fed's new inline markers were written
`aria-label="48"`, `aria-label="22"` and so on. The writer now passes its labels to
`EPUBTextEncoder.piece` as well, and the twelve read `44`, `14`, … as the page-list already did
(#248). No other corpus book with labels gained an inline marker.

## Item 2: a row split after an exponent read as a list item

### Why

Wallace sets an example as one printed row: `8x² − 3x + 7 − 2x² + 4x − 3` on the left,
`Combine like terms 8x² − 2x² and − 3x + 4x and 7 − 3` on the right (page 23, Example 33). PDFKit
breaks each of those rows after the raised exponent, so `8x2` is one extracted line and
`− 3x + 7− 2x2 +4x− 3` the next, beginning 1.89 points to its right on the same baseline.
`BlockAssembler.isList` accepts a minus and a space, so the second piece was classified
`.listItem`, flushed the open paragraph and became a `<pre>` block of its own in the middle of the
derivation.

### The rule

A marker is a marker because the page set it at the start of a printed line. A piece the extractor
cut out of the middle of a row began no line, so it is read as prose and rejoins the piece before
it through `continuesRow`, which already exists. The evidence is another line on the same row that
ends at or before this line's left edge and is nearer than the 0.75 of a body a column's gutter
needs — the same bound `continuesRow` and `LayoutReconstructor.ordered` use, so a page's columns
and a table's cells are untouched, and a piece that opens its row has nothing to its left.

### Counts

`<pre>` blocks in the converted book, and among them those that open with a minus, and those that
directly follow a block ending in a superscript:

| Book | `<pre>` | opening `− ` | after an exponent |
| --- | ---: | ---: | ---: |
| Wallace, baseline | 3,013 | 436 | 370 |
| Wallace, candidate | 2,633 | 56 | 7 |
| CIA report, baseline | 799 | 131 | 0 |
| CIA report, candidate | 780 | 113 | 0 |

Wallace gains 230 paragraphs and 150 characters of inserted spaces; no word changes. The issue
counted 27 such rows with the coordination branch's own tool; this count is taken differently (any
`<pre>` opening with a minus directly under a block that ends in a `<sup>`) and is not comparable
to it, so it is given as measured here and in both directions.

Page 23 is the reproducer the Swift test pins. `<p>8x2</p><pre>− 3x + 7− 2x2 +4x− 3</pre>` becomes
one paragraph, and so does `Combine like terms 8x2` with `− 2x2 and− 3x +4x and 7− 3`. The
controls on the same page still keep their breaks, because they open their rows: `− 7(5x− 6)` and
`− 3x +5y Our Solution`. The license page's genuine list (`• Other Rights:`, `− Your fair dealing
or fair use rights…`) is unchanged, as are the bulleted lists on 9/11 page 583, FAA page 364 and
Fed page 77, which the test checks directly.

The CIA report's 19 are lines of its unverified OCR layer over statistical tables (`- Per Cent`,
`- Percent`, `- L25 106 LOS`) that were being called list items; they are pieces of a printed row
and now read as prose. Every other book is unchanged.

**Page 226's Example 295 is not in scope on `main`.** The issue names it because #177 brought it
out of its crop; that change is not here, so on `main` the example is still a preserved region
(`image-767`) and prints no `<pre>` row at all.

**What remains.** A row whose *left* piece is itself a list item or a marked line (`19) (5n4 +…`)
still splits into two blocks, because those assembler branches open a `<pre>` rather than an open
paragraph and set no `previous` for the piece that follows. The right piece no longer reads as a
list item — it is a `<p>` — but the row is still two blocks. Filed as
[#265](https://github.com/vocaro/PDFReflowLib/issues/265).

## Item 3: Our Flag's lost hyphens — a statement that does not hold on `main`

The issue says five of Our Flag's lost-hyphen lines have no soft hyphen in the page's text and
still rely on #157's rule. **Neither half is true on `main`, and there is nothing here to fix.**

**#157's rule is not on `main`.** It was `lostLineEndHyphen` / `endsShortOfMeasure` /
`justifiedMeasures` in `c64f637`, on the abandoned branch. None of those names, and no citation of
#157, exists anywhere in `Sources/`. The five lines the issue describes are five of the thirteen
joins that rule made *on that branch*; on `main` no such join is made at all.

**Every residual split in Our Flag is a hyphen the page draws.** All 48 word-splits in the
converted book were enumerated two ways — a pair whose joined form the book itself prints
elsewhere, and a pair whose joined form the system lexicon holds while neither half is a word —
and each was looked up in `pdftotext -raw` output:

| Break | Count |
| --- | ---: |
| The page draws U+00AD and PDFKit drops it | 47 |
| The page draws U+002D | 1 (`horizon-` / `tally`, page 30) |
| No hyphen drawn at all | 0 |

The 47 are the Apple defect already written up in
[apple-feedback-soft-hyphens](../apple-feedback-soft-hyphens/report.md): Poppler 26.04 returns 64
line-final U+00AD in this document and PDFKit returns none. `HyphenRepair` already removes a soft
hyphen unconditionally, so restoring the character in extraction would close all 47 with no
vocabulary, lexicon or measure evidence — which is what #177's `droppedSoftHyphen` did on the
abandoned branch, and what #157 item 1 is now really about.

The one hard hyphen is a different defect and not a lost hyphen: page 30 sets `1. Two persons,
facing each other, hold the flag waist high and horizon-` as a preformatted list item and
`tally between them.` as the paragraph beneath it, and #245's item repair does not reach across
that boundary. Filed as [#266](https://github.com/vocaro/PDFReflowLib/issues/266).

Our Flag converts byte-for-byte identically on the two binaries in this lane.

## Reproducing

```sh
swift build -c release
python3 tools/run_corpus_regressions.py --converter "$(swift build -c release --show-bin-path)/pdf-reflow" \
  --epubcheck "$(command -v epubcheck)" --output /tmp/corpus-203 --jobs 4
pdftotext -raw corpus/cache/CDOC-108hdoc97.pdf - | grep -c $'­'
```
