# A table read as cells

Measured under [#210](https://github.com/vocaro/PDFReflowLib/issues/210), baseline `9dfbd4b`,
2026-09-21, macOS 27.0 (26A425) / Xcode 27.0, arm64, release CLI at library defaults with a fixed
package identifier and modification date. Character counts are non-whitespace characters of every
`<p>`, `<pre>`, `<h*>`, `<td>` and `<th>` in the converted book, read through
`tools/check_corpus_content.py`'s own spine reader.

The owner's comment on the issue
([#210, 2026-09-20](https://github.com/vocaro/PDFReflowLib/issues/210#issuecomment-5748289394))
closed two of its three items and named the third: the USGS statistics tables stay crops "and that
is the right answer for them … What they actually need is real table markup, and
`ReflowDocument.Content` has no table case — `EPUBWriter` emits none. That is the open part of this
issue." This is that part. Census page 14 and FAA page 416 were re-measured and are as the comment
records them; neither is changed here.

## What the three USGS tables look like to a reader

`mcs2025-copper.pdf` is two pages and draws three tables. On `9dfbd4b` all three are
preserved-region crops (#36): the book converts to 3 images, 6,180 characters of prose and no cell.
The crops are right in the sense the comment means — reading those tables as lines of text would
put `Mine, recoverable 1,200 1,230 1,230 1,130 1,100` in a paragraph and lose which year each
number belongs to — and wrong in that a reader cannot read a picture.

The pages state their columns in three different ways, and no one of them is enough:

| Table | Page | How PDFKit hands the rows back |
| --- | ---: | --- |
| Salient Statistics—United States | 1 | Label and values as two lines on one baseline, except five rows PDFKit merges whole |
| Tariff | 1 | The first row as three lines; the other four merged whole |
| World Mine and Refinery Production | 2 | Every row merged whole: `United States 1,130 1,100 882 890 47,000` |

A merged row cannot be divided at its spaces: `1.7¢/kg on lead content.` is one cell with spaces in
it and `United States 1,130 1,100 882 890 47,000` is six cells with the same spaces between them.

## The mechanism: the white that runs down every row

The division is read from the page's own text-showing operations rather than from PDFKit's lines.
`NativeSpacingReader` already walks the content stream for the spacing repair and records each
show's origin and the x its glyph advances end at; `PageReader` now reads that walk once and hands
it to both readers. A printed row's *ink* is its shows merged where they touch (within half a
point), and an x range no row of a block puts ink in is a *corridor*.

Corridors over the three tables, measured on the source:

| Block | Rows | Corridors ≥ 0.5 em | Columns |
| --- | ---: | --- | ---: |
| Salient Statistics (baselines 571.0–328.5) | 23 | 353.7–367.2, 397.8–409.0, 438.8–450.7, 480.6–492.2, 522.1–532.8 | 6 |
| Tariff (174.5–108.5) | 7 | 250.6–310.8, 375.6–433.3 | 3 |
| World production, body only (494.2–285.1) | 21 | 151.3–202.6, 236.8–261.3, 295.3–346.3, 380.6–405.3, 439.3–501.8 | 6 |

Two measurements decided the shape of the rule.

**A per-row threshold cannot divide the widest row.** Clustering one row's own shows at 1.2 em
divides twenty-two of the salient table's twenty-three rows and fails on
`Employment, mine and plant, number 11,000 11,400 12,000 12,600 13,000`, whose values leave 5.6
points between them where the rows above leave 8.4 — 0.56 em against 0.83. A threshold low enough
for that row divides `Congo (Kinshasa)` into two cells. Reading every row against the *block's*
corridors instead divides both, because the corridor is what all twenty-three rows agree on.

**A spanning heading closes the corridors under it.** Over the whole world-production block,
including `Mine production Refinery production Reserves6`, only three corridors survive and the
table reads as four columns; over the rows below that line, five survive and it reads as six. So up
to two rows are lifted off the top of the block and read against the columns the rows below state,
which is what gives `Mine production` and `Refinery production` their `colspan="2"`.

A cell's text is what `PDFPage.selection(for:)` reads inside the cell's rectangle, except where the
page's own extracted lines divide on the cell's edges — the salient table's label column is one
line per row — in which case the cell is those lines' content and keeps the spacing repair, the
styles and the links the pipeline gives them. That is where `<strong>Salient Statistics—United
States:</strong>` comes from.

## The result, against the reviewed transcription

`corpus/usgs-mcs2025-copper-review.json` holds a complete cell-by-cell transcription of all three
tables, read from the rendered source and cross-checked against Poppler. All **40 data rows and
225 cells** are emitted, each in its own column. Two rows differ from the transcription only in the
transcription's own notation for a raised marker, and the converter is right in both:

| Reference notation | Emitted | The page prints |
| --- | --- | --- |
| label `Net import reliance…`, `note: "4"` | `Net import reliance4 as a percentage of apparent consumption` | the `4` raised after `reliance` |
| `(7)100,000` | `7100,000` | a raised `7` before `100,000` |

Everything the issue named is carried: the wide label column, the group rows holding only a label
(`Production:`, `Refinery:`, `Imports for consumption:`, `Exports:`, `Consumption:`,
`Price, annual average, cents per pound:`), the titled year header, `—` for zero, `e150` and `e740`
for an estimate, `(2)` for a note, and the label the page wrapped over two printed rows
(`Stocks, refined, held by U.S. producers, consumers, and metal` / `exchanges, yearend`), which is
joined into one cell.

## What it takes to keep prose out

Five conditions, each measured against a case that needs it.

| Condition | The case it answers |
| --- | --- |
| Three columns at least | Two columns of prose facing each other leave one corridor, the gutter |
| No column of prose | FAA page 416: the NDB table sits in the right column of a two-column page, and on geometry alone the left column's six prose rows and the table's rows form one four-column grid |
| A column of values | A three-column list of names and trades states columns and is not a numeric table |
| Half the cells filled at least | Wallace page 424 letters a right triangle — `A`, `B`, `x`, `63°`, `7.6` — over four rows that divide at four columns and fill 7 cells of 16 |
| No cell opens a figure label | FAA page 207 sets `Figure 8-4. Look at the chart…` over two rows beside a three-row altimeter table; the caption became two cells of the table it captions |

The prose condition is a proportion, not a count: three of the twenty-four rows of the USGS label
column reach the column's edge with five words or more in them, and every one of the FAA left
column's rows does. Counting alone reads them the same; the share separates them.

The fill condition is measured: the three USGS tables fill 78%, 90% and 98% of their cells, and the
algebra book's worked-example tables 60% to 85% with their group rows' empties counted against
them, against the triangle's 44%.

## What moved, per book

Both lanes ran on `9dfbd4b`'s tree and on this change, 18 cases each, `--jobs 4`, EPUBCheck
5.3.0 at `/opt/homebrew/bin/epubcheck`. Every case of this change's lane passes on its own
`runPassed`, `memoryGate.status`, `epubcheckExitCode`, `structuralCheck` *and* its
`content-assessment.json`, read case by case.

| Book | Characters | Δ | Images | Δ | Δ bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| `usgs-mcs2025-copper` | 8,376 | +2,050 | 0 | −3 | −327,114 |
| `wallace-algebra-2010` | 455,350 | +529 | 2,174 | −13 | −194,824 |
| the other sixteen | unchanged to the character | 0 | unchanged | 0 | +87 to +106 |

The other sixteen books move by the three CSS rules the stylesheet gained and by nothing else.

**`usgs-mcs2025-copper`**: page 1, 2 images → 0 and 2,390 → 3,791 characters; page 2, 1 → 0 and
3,790 → 4,526. Three tables, 51 rows.

**`wallace-algebra-2010`** moves on 17 of its 1,193 pages, and no page loses a word.

- *Nine pages recover a table from a crop* (81, 83, 159, 161, 162, 163, 168, 169, 377): the book's
  own worked-example tables — the rate/time/distance table, the coin value table, the investment
  table, the mixture table — were preserved-region crops, and the text inside them was not in the
  book at all. 13 crops become 16 tables and the pages gain 529 characters that were pictures. Page
  159 is the shape of it: `| | Number | Value | Total | |` over `| Quarter | q | 25 | | Using value
  table, use q for quarters, d for dimes |`.
- *Eight pages gain structure and no text* (438, 440, 442, 445, 454, 455, 456, 488): the answer
  keys, which the book sets in three columns of numbered answers. Their characters and their
  reading order are identical to the baseline's; they are now rows of three cells rather than the
  same three answers run together in a line.

`faa-phak-8083-25c` emits no table: page 416's NDB table is declined by the prose-column condition
and page 207's altimeter table by the caption condition. Its 87 contract checks pass unchanged, and
`rowBlocks` still keeps page 416's printed rows, which is the reading the issue's comment records
as already right. The `MH Under 50 2 5` row remains, which is #274.

## The contract this replaces

`corpus/regressions.json` pinned the three tables as pictures: six `imageRegions` correlations
against rendered references and two `minimumImages`, whose stated purpose was to catch "a row or a
cell lost from the preserved table". The tables are no longer pictures, so that contract is
replaced by a stronger one of the same intent: a new `tableRows` check kind reads each `<tr>` as
the cells it holds, and twenty rows are pinned cell by cell — the column headings, the two rows the
old contract read by eye, and every row carrying a mark the tables use. A cell lost, a cell read
into the wrong column and a row lost all change a pinned row. The case's checks go from 17 to 30.
`corpus/references/usgs-mcs2025-copper/*.png` are no longer referenced; they are left in the tree as
the evidence the earlier contract was measured against.

A baseline binary built from `9dfbd4b` fails exactly one case against the new contract —
`usgs-mcs2025-copper`, on all twenty-one of its table rows — and passes the other seventeen, which
is the statement that the change and the contract move together and nothing else does.

## Gates

`scripts/check-all.sh --fast` passes all ten gates (python-tool-tests, measurements-policy,
swift-tests, release-build, pdfkit-concurrency, documented-builds, doc-counts, issue-citations,
fixture-epubs, conversion-policies) on the merged tree. 567 Swift tests and 231 Python tests pass.
EPUBCheck reports 0 errors on every corpus book.

## What a cell does not carry

A cell that is not exactly one of the page's extracted lines is read as the plain characters inside
its rectangle, so a raised marker inside such a cell is a character and not markup: `Reserves6`,
`e150` and `7100,000` read as the page prints them, and the digit is not a `<sup>`. Recovering the
style would need the run geometry inside a line, which the extraction does not carry. This is
recorded in the corpus manifest as the case's one remaining fidelity issue.

## Evidence

Sources: `corpus/cache/mcs2025-copper.pdf` SHA-256
`348b1e224d830a51e6d35cf81343eead26a0cb2a4e74c474d699b7faed1b10e6`;
`corpus/cache/Beginning_and_Intermediate_Algebra.pdf` and `corpus/cache/faa-h-8083-25c.pdf` as the
manifest pins them. Baseline converter SHA-256
`705629ef477fcb7aa35f52a1962a0c8c98e72976fcb154e45284a3302f2d1b78`, built from `9dfbd4b`.
