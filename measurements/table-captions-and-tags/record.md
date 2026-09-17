# Table captions, tagged table structure and spanning-header checks (#113, #114)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
The work started on `f15ab78` and was fast-forwarded to `3f59dff` and then `9bf4e76` as they
landed (neither touches tables; `corpus/regressions.json` edits were re-applied by script after the
second merge). Every lane figure below compares these binaries:

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `git archive 9bf4e76` | `26754f167e71aa66f5cfa6180271dc5b7c8aaefd10b5e0ad2dba0e12f42bddf3` |
| candidate | this tree on `9bf4e76` | `1d8eb863ec9f8620585f1b03605dc053acc6bddea59c1b7c787b98708d6940a0` |

The baseline is `9bf4e76` rather than `f15ab78` because `183c2c4` (in between) changes seven FAA
pages; the coordinator reports Fed, Our Flag, USGS and DGA output unchanged from `f15ab78`. An
`f15ab78` release binary (`30d783ef…`) produced the same Fed table pages used in the diagnosis. No
source PDF or EPUB is committed; each lane output was deleted after its comparison and page diff.

## #113.1: table titles read as one paragraph or as headings

### Diagnosis

Every Fed text table has a title band inside the table's box: a 10-pt title, an 8-pt description
at the title's left edge, then the header row (all seven source-derived fixtures agree). The PDF
tags title and description together as one `Caption` element, the sibling immediately before each
`Table` (see the survey below). `ShadedTableDetector` treated those lines as rows outside the grid
and left them to ordinary reflow, where the result depended on the page:

- The heading threshold is `max(page body × 1.25, prose-outside-boxes body × 1.1)`. On pages whose
  prose outside boxes is 9–10 pt (46, 47, 97, 109) the 10-pt title is not heading-sized and reads
  as prose: joined with the description in the same band into one `<p>` (46, 47, 97), or a
  separate `<p>` over the description (109, where the band holds only the title).
- On pages that are almost all table (64, 82, 83, 120, 121; body 8 pt, threshold 10 pt) the title
  becomes an `<h6>` and a navigation entry, and the description a paragraph.

### Change

- **`ShadedTableDetector.caption(above:bodySize:)`** (new). The lines inside the table's box above
  its first row are scanned upward from the table: body-sized description lines (within 10% of the
  table's median cell size, at most six), then one to three title lines at least 15% larger, all
  the same size. Each line must be alone on its row, share the first line's left edge (within one
  body size) and lie no more than two body sizes from the line below it. The scan stops at the first
  line that fits none of this (Box 3.5's own prose above Table A), and a scan that found no title
  line yields no caption. `Table` gains `title` and `description`; `lines` (what `TintDetector`'s
  ruled-table trial inspects) is unchanged, and `ownedLines` adds the caption.
- **`LayoutReconstructor`** removes `ownedLines` from the free lines, orders the table element by the
  union of its rows and caption, and `tableBlock` joins title lines and description lines like
  paragraph lines into `ReflowBlock.Table.caption` (default `[]`).
- **`EPUBTextEncoder.table`** writes `<caption><p>title</p><p>description</p></caption>` first in
  the `<table>`; `ReflowBlock.text` and `sourcePages` include the caption, so page-list entries for a
  boundary inside a caption still exist. `style.css` left-aligns captions.

### Before and after (`pagediff-fed-explained-2021.txt`, `navdiff-fed-explained-2021.txt`)

| Page | Baseline | Candidate |
| --- | --- | --- |
| 46 Table 3.1, 47 Table A, 97 Figure 6.5 | `<p>Title Description</p>` then `<table>` | `<table><caption><p>Title</p><p>Description</p></caption>` |
| 109 Figure 6.11 | `<p>Title</p><p>Description</p>` then `<table>` | caption with both paragraphs |
| 64 Figure 4.6, 82 Figure 5.7, 120 Figure 7.2 | `<h6>Title</h6><p>Description</p>` then `<table>` | caption with both paragraphs |
| 83, 121 (continuations) | `<h6>Title (continued)</h6>` (121: then `<p>(continued)</p>`) | caption `Title (continued)`; 121's `(continued)` is its second paragraph |

Each caption was compared with the source raster (60 DPI `mutool draw`) and with the PDF's
`Caption` element text: all ten match word for word, title and description split where the source
changes type size. Nothing else on these pages changed: `compare_conversion_runs` lists markup,
paragraph, table and (for the five heading pages) heading/anchor fields, the page text is equal,
and so are images and page markers. The table of contents loses exactly the five figure-title
headings (203 → 198 entries); every other heading keeps its level and the page list is identical
(135 entries). No other figure or table title in the book was a navigation entry. EPUBCheck passes.

## #113.2: tagged Table/TR/TH/TD structure

### Why the tags are rejected

`StructureTreeReader.walk` consumes only `P` and `H1`–`H6` groups whose ancestors are containers
(`Document`, `Part`, `Art`, `Sect`, `Div`), with `Span`/`Link` inside a group. Any other role met
outside a group (`Table`, `TR`, `TH`, `TD`, `THead`, `TBody`, `Caption`, `L`, `Figure`, `Note`, …)
calls `reject(nil)`: `Index.rejected` becomes true (the document-level `structureFallback`
warning), and the subtree is walked with `allowed = false`, so neither an MCID directly under a
`TD` nor a `P` inside a cell (Fed 64's first-column cells) forms a group. No line in a tagged table
ever carries a tag, and `LayoutReconstructor` separately rejects caption and list groups.

### Survey (`tag-survey.txt`, `tag-crosscheck-fed.txt`)

`tools/survey.swift` walks the structure tree of each book and, for every `Table`, records its rows
(through `THead`/`TBody`/`TFoot`), cells with `ColSpan`/`RowSpan`/`Scope`, and the native lines
(`NativeTextReader` with column joints, as the pipeline extracts them) that each cell's MCIDs
anchor to, using the show origins of `MarkedTextReader`'s own scan (`tools/make-anchors.py` derives
that copy). A line anchored by two cells is shared; a cell MCID shown from an unknown origin is counted.

| Book | Tagged tables | Pages |
| --- | ---: | --- |
| Fed | 11 | 46, 47, 54, 64, 77, 82, 83, 86, 97, 109, 120–121 |
| FAA | 1 | 131 (inside a `P`) |
| Our Flag, DGA | 0 | — (no element maps to `Table`) |

| Fed page | Tags | Geometry today | Cross-check |
| --- | --- | --- | --- |
| 46, 47, 82, 83, 97, 109, 120–121 | clean: no shared lines, no unknown origins except one MCID on 120 | table | every tagged row equals an emitted row, in order |
| 64 | 12 unknown-origin MCIDs, in first-column cells with `P` and `Link` children | table | every row equal, in order |
| 54 | clean, 1 header + 1 body row | preserved crop | Figure 4.2 is a diagram of four coloured boxes tagged as a table |
| 86 | 3 unknown-origin MCIDs; body cells hold lists | preserved crop | Figure 5.8, the Basel Accords table |
| 77 | `Rating system CAMELS RFI/C(D) LFI` shared by 4 header cells; a list line shared by 2 cells | preserved crop | not consistent |
| FAA 131 | 3 lines each shared by 2 cells (label and value on one PDFKit line) | prose, rows interleaved | not consistent |

The cross-check compares rows with spaces and hyphens ignored; it would not see a cell boundary
moving within a row, which the `tableCells` contracts check instead. The Fed tags mark first-column
cells `TH` with `Scope /Row`; geometry emits them as `td`, and joins the tags' separate regulation
letter and name cells (82, 83, 109) into one cell as the printed header "Regulation (by letter and
name)" does.

### Recommendation: not implemented

Accepting table tags is not bounded in these books, so the geometry path stays as is:

1. On every table the geometry reads, the tags add no cell the geometry lacks.
2. The tagged tables the geometry does not read either lie inside preserved figures (54, 86) or are
   inconsistent with PDFKit's lines (77, FAA 131). Emitting 54 or 86 would mean removing their crop
   in `graphicsWithLabels` (whole-figure seeding, outside this area) and reading lists inside cells.
3. Doing it at all needs a per-cell tag index (spans from attribute dictionaries or arrays, `P`,
   `L` and `Link` descendants), association with a cell as the rejection unit, and a geometry check
   (no shared lines, no unknown origins, rows in vertical bands, columns aligned across rows), for
   at most two tables in four books. Our Flag and DGA have none.

The survey tools are kept so the question can be reopened when a book with ruled tables and no
shaded header band appears (the record for #65 found none in the five books).

## #114.1: spanning label/amount headers in `tableCells`

`tools/table_cells.py`:

- A column may be `{"header": <path>, "span": n ≥ 2, "column": 1..n}`: some header cell whose
  header path ends in it must carry exactly that colspan, and `column` selects one grid column
  beneath it. `grid_from_table` now records each written cell's `(row, first column, colspan)`, so
  a spanning cell is told apart from equal text repeated in adjacent cells.
- A row's `labelColumn` (1-based into `columns`) names where its label is found; the default is still
  the first grid column. Table A's `U.S. Treasury, General Account` row has an empty asset side.
- An optional `caption` lists the table's caption paragraphs; they must equal the `<p>` texts of that
  table's `<caption>` (or its whole text), in order. `check_corpus_content.py` treats `caption` as a
  block, so caption paragraphs are page paragraphs, words stay separate, and they are never headings.

Page 47's four ordered amount phrases became one `tableCells` expectation with the four spanning
columns and all five rows. Negative controls (`tools/test_table_cells.py`): headers without colspan,
a header spanning three columns, amounts exchanged between sides, a label merged with its amount,
the Treasury row on the asset side, a missing row, the string form (duplicate columns rejected);
for captions, none, title and description merged, title only, reversed; invalid schemas (span 1,
column 0 or past the span, boolean or float span, empty header, missing or extra keys, duplicate
columns, `labelColumn` 0, past the columns, boolean or string, caption `[]`, `['']`, a string or
non-strings). Run against the committed `table_cells.py` and `check_corpus_content.py`, the five new
tests error on the new schema and the nine existing tests pass (`negative-old-checker.log`).

## #114.2: `fed-77` and `fed-109` fixtures

Recaptured with `tools/capture-layout-fixture.swift` (`tools/fixdiff.py` compares). Against the
committed files:

| Fixture | Change |
| --- | --- |
| `fed-77` | `paints` added (0 → 34; the old capture predates #54's paint recording); the header line `Depository institutions Bank holding companies (BHCs)` splits at the rule grid's joint (#65); 3 lines gain the tags the pipeline now applies (H5 `Examination Report`, a two-line P). Clustered `graphics` and `attributedLines` are identical. |
| `fed-109` | `paints` added (0 → 39); `J` splits from `Collection of Checks …` at the joint; 11 lines gain tags (an eight-line P, H4 `Expedited Funds Availability Act`, a two-line P). `graphics` and `attributedLines` identical. |

The tests that load them (`HeadingTests.modestSourceSectionHeadingsSurviveSmallTableText`,
`graphicDominatedFedPagesRetainBodyAsParagraphs`, `runningHeaderRuleIsDecorationOnEveryFedFixture`)
pass unchanged. With `paints`, `content()` now composes tints: 109's regulation table reads as a
table with its caption, and 77's ratings grid stays a crop. No expectation changed. To show they pass
for the geometric reasons they were written for, `recapturedFed77And109KeepTheirEvidenceWithoutTags`
strips every tag and still finds the headings and body paragraphs, 77's grid inside a crop and
109's table caption. `fed-47` and `fed-97` are new captures from the same tool.

## Tests

`Tests/PDFReflowLibTests/TableCaptionTests.swift`, 6 functions (12 cases):

| Test | Reproducer / control |
| --- | --- |
| `fedTableTitlesAndDescriptionsAreTheTablesCaption` | Fed 46, 47, 64, 83, 97, 109, 120: one table, caption title (and description), neither text anywhere else, rows untouched. |
| `boxProseAboveTableAStaysOutsideItsCaption` | Fed 47: Box 3.5's title and paragraphs stay outside Table A's caption; header spans `[2, 2]`; the note follows the table. |
| `captionIsATitleAndItsDescriptionDirectlyAboveTheTable` | Synthetic title + two-line description; two-line title alone. |
| `linesThatAreNotACaptionStayOutOfIt` | Controls: no title-sized line, nothing above, a row of two lines, a description off the title's edge or in another size, a wide gap, seven description lines, four title lines; prose and a larger box title above end the scan without costing the caption. |
| `captionParagraphsSerializeInsideTheTable` | Markup, escaping and styles in `<caption>`, text and source pages include the caption, no navigation entry, page-list entry for a boundary inside it, no `<caption>` without one. |
| `recapturedFed77And109KeepTheirEvidenceWithoutTags` | See #114.2. |

Updated: `TintedBoxTests.fedEntityTableReadsAsTwoColumnsWithItsHeader` and
`RuledTablesAndHeaderRulesTests.fedTable31ReadsAsAThreeColumnTableWithItsHeader` asserted the title
(and 64's description) as blocks before the table; they now assert the caption and that no other
block holds it. `shadedRowsWithRulesReadAsATableWithTheTitleOutsideIt` is unchanged: its title is
outside the tinted bands, and it stays a paragraph.

**Negative control** (`negative-no-caption-scan.log`): with the caption scan replaced by an empty
caption, all seven source cases, the Box 3.5 test, both updated tests and the fixture test's 109
caption fail (41 issues); the rule and serialization tests, which call the function and encoder
directly, pass.

## Contracts (`corpus/regressions.json`, Fed)

- **46, 47, 64, 83, 97 (new entry), 109, 120:** `tableCells` with `caption`. 97 and 109 add cell rows;
  120 adds a cell row (its table has no header row, so the checker reads the first section row,
  `General banking`, as the spanning header of both columns).
- **47:** columns are the four spanning columns with all five rows; `orderedText` removed.
- **64, 83, 120:** `headings` removed (the only entry each: the figure title, now the caption).

The baseline lane fails exactly the seven caption checks (`lane-summaries/base-fed-explained-2021.json`);
its Table A cells already satisfy the spanning columns. The candidate passes every check.

## Verification

- `swift build`, `swift build -c release`: clean. `swift test`: 527 pass (521 at `9bf4e76` + 6).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 210 pass.
- `scripts/check-all.sh --fast`: exit 0 (527 Swift, 210 Python, 8/8 fresh concurrency processes,
  6 fixture conversions, 13 policy conversions and 22 rejection/cleanup cases, 6 byte-identical
  repeat conversions).
- Corpus lane, one case per call (`tools/case.py`: `run_corpus_regressions.py --epubcheck
  /opt/homebrew/bin/epubcheck --environment-probe <probe> --execution-context host-terminal` for
  base and cand, then `compare_conversion_runs.py --allow-different-converters`, outputs deleted).
  No memory-gate failure; 37–38 GB free throughout.

  | Case | Baseline | Candidate | compare_conversion_runs |
  | --- | --- | --- | --- |
  | fed-explained-2021 | fails 7 new caption checks | pass | 9 pages (46, 47, 64, 82, 83, 97, 109, 120, 121), all reviewed above; navigation on 64, 82, 83, 120, 121; images and markers equal; no OCR change |
  | faa-phak-8083-25c | pass | pass | no changes |
  | gpo-our-flag-2003 | pass | pass | no changes |
  | usgs-mcs2025-copper | pass | pass | no changes |
  | dga-2025-2030 | pass | pass | no changes |

## Remaining gaps and defects to file

1. **Fed 97's header row is body cells.** `Credit transfer` / `Debit transfer` sit on two half-width
   coloured bands, so the detector's full-width header band test fails and they emit as `<td>`; the
   tags mark them `TH`.
2. **Row headers are `td`.** The Fed tags first-column cells `TH /Scope /Row` (46, 47, 64, 109, 120);
   the table model has no row-header cell, so that semantics is lost.
3. **Figure titles around preserved crops are prose.** Fed 54's `Figure 4.2. …` title and description
   are two plain paragraphs above a crop captioned "Preserved region from page 54"; 86's Figure 5.8
   title is inside its crop. Only tables get source captions.
4. **Fed 86 (Basel Accords) and 54 stay images** although tagged as clean tables; 77's ratings grid
   header is still one PDFKit line across four cells (no rule joints in that row).
5. **Document-wide `structureFallback`.** Any unsupported role (a `Table`, a `Caption`, an `L`) sets
   the book-level warning, so every tagged Fed/FAA conversion reports it.
6. **`tableCells.title` is an unchecked label.** It reads like a caption check but only names the
   expectation; `caption` is the checked field.
7. **FAA 131's borderless load-factor table reflows scrambled.** The two-column `CATEGORY` / `LIMIT
   LOAD FACTOR` table reads `CATEGORY LIMIT LOAD FACTOR Normal1 3.8 to –1.52`, `Utility (mild
   acrobatics,`, `4.4 to –1.76`, `including spins) Acrobatic 6.0 to –3.00` as four paragraphs. Its
   tags cannot repair it: PDFKit puts label and value on one line.
