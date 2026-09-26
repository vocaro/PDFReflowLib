# A line broken after a closed em dash carries on with no space

Measured under [#315](https://github.com/vocaro/PDFReflowLib/issues/315), baseline `af18cfb9`,
2026-09-25, macOS 27.0 (26A428) / Xcode 27.0 (27A266a), arm64, release CLI, sources from the
pinned corpus cache. Every manifest document was converted with the flags its manifest entry asks
for (`evaluate_real_document.conversion_flags`) and pinned packaging
(`--package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`), once with
`af18cfb9`'s binary and once with this change, one book at a time: the two EPUBs were compared
with `tools/epub_identity.py`, then block by block where they differed, and discarded before the
next book. Both binaries ran under the same executable name, so the Vision pages of the OCR books
were not transcribed by different model caches.

## What was wrong

`HyphenRepair.joinOperation` closed up a line after a hyphen, a soft hyphen and, since #297, an
en dash closed against a letter or figure. Every other line end took a space, so a line the page
broke after a closed em dash came out with a space of the library's own after the dash. The 9/11
report printed `…An attendant has been stabbed—` over `and someone else up front may have been
killed.` and the conversion wrote `stabbed— and`; Loper Bright's `“other disposal” of coal—` over
`encompassed a transaction` came out `coal— encompassed`, and *NCA5*'s `adopting innovations—`
over `such as agroecological practices` came out `innovations— such`.

## What the corpus's own em dashes say

`pdftotext -enc UTF-8` reads every manifest source's text layer line by line. Inside a line, an
em dash with a letter or figure on both sides is closed; one with a letter or figure before it and
a space after it is spaced after:

| Book | closed inside a line | spaced after | line ends after a letter |
| --- | ---: | ---: | ---: |
| gpo-911-2004 | 751 | 0 | 48 |
| noaa-nca5-2023 | 705 | 0 | 31 |
| faa-phak-8083-25c | 1,462 | 3 | 15 |
| scotus-loper-bright-2024 | 125 | 0 | 15 |
| fed-explained-2021 | 109 | 0 | 3 |
| usda-ars-agresearch-2012-11 | 39 | 0 | 3 |
| gpo-our-flag-2003 | 12 | 0 | 3 |
| dga-2025-2030 | 9 | 0 | 1 |
| gpo-warren-1964 | 16 | 59 | 4 |
| gpo-warren-1964-suspect-text-excerpt | 0 | 2 | 1 |

Those are the 124 line ends #315 counts. The books that close the dash close it all but everywhere. After
punctuation too: every em dash in the born-digital sources that follows a closing parenthesis, a
quotation mark or a stop inside a line is closed (the FAA's 46 `)—`, 9/11's 19 `”—`, Loper
Bright's `here and there;—secondly`, `agency or court?—is`, `voila!—you`, *Our Flag*'s
`IN GENERAL.—The`).

Warren's text layer is its scan's OCR, and its 59 spaced dashes are the OCR's, not the page's:
page 70's `job— all` is `job—all` on the raster, and 46 of the 59 are the gathering signature
`730-900 0-64— 10` at a page foot. The pages close the dash, including after a run-in heading's
stop: page 680 prints `Speculation.—Mrs. Markham said`. `pdftotext` also reads 547 Warren lines
that are a dash alone, which PDFKit's reading of the same pages attaches to its words; no join the
conversion makes ends in a dash alone.

## Every join that reaches a line-final em dash

A probe build of `af18cfb9` that logged every join whose line ends in U+2014 ran over all 24
documents. The conversion makes 143 such joins, in ten books:

| before the dash | next line opens with | joins | books |
| --- | --- | ---: | --- |
| a letter | a letter | 106 | 9/11 46, NCA5 31, Loper Bright 12, FAA 8, USDA 3, Fed 2, Warren 2, DGA 1, *Our Flag* 1 |
| a figure | a letter or figure | 5 | 9/11 2, NCA5 2, Warren 1 |
| a letter | a figure | 1 | 9/11 |
| `)` | a letter | 5 | Fed 2, Loper Bright 2, NCA5 1 |
| `”` | a letter | 3 | 9/11 |
| `.` | a letter | 3 | Warren |
| a letter or `"` | a quotation mark | 6 | Warren 4, FAA 2 |
| a letter or `.` | `^` | 8 | Warren |
| a dash | a letter | 1 | Warren (a rule of dashes) |
| a space | anything | 5 | Hebrew Shakespeare |

The first seven rows, 129 joins, are the ones the rule below closes. Read against their sources,
128 of them are dashes the page sets closed. For the born-digital books the book's own usage
says so (the table above), and the dash after punctuation is no exception: *The Fed Explained*'s `(FOMC)—` over `make decisions`, 9/11's
`“newspapers”—` over `the Senior Executive Intelligence Brief`, Loper Bright's
`(emphasis added)—` over `even those involving ambiguous laws`. The FAA's contents page prints on
one line the `ATC Instructions—“Hold Short”` that its chapter's sub-heading breaks at the dash.
Warren's were read on the raster (`pdftoppm -r 200`): `individuals.—The Commission`,
`November 22.—In the early morning`, `charge.—Section 212(a)`, `stamp—“DR. A. J. HIDEEL`,
`talked—“dreaming,”`, `“Papa nas lubet”—“Daddy loves us,”`, `brown—“it wasn’t dark`,
`PKT 5—56:05` and `history—a role` (whose `a` the text layer lost). The one the page spaces is
Warren's page 322, below. Three of the 128 close a dash at a line the page does not run on, a
speaker's turn the conversion has joined to the next (below). *NCA5*'s poem on page 5 is not one
of them: `Species to species in the same blue air, smoke—` over an indented `wing flutter buzzing,
a car horn coming.` is one long line and its turnover (the pair's rows 14 pt apart, the poem's
lines 18.5 pt), and it now reads whole, `smoke—wing flutter buzzing`. Four of that poem's other
lines come out split at their turnover
([#321](https://github.com/vocaro/PDFReflowLib/issues/321)).

The last three rows are left as they were. Warren's `^` is its OCR layer's stray mark at the head
of eight lines (`Speculation.—` over `^Mrs. Markham said`, which page 680 prints
`Speculation.—Mrs. Markham said`); the character after the dash is not the text that follows
it, and the join does not guess. The
rule of dashes stands above a footnote, and the Hebrew study's `1877 . — — —` are spaced ditto
dashes in its bibliography.

## The rule

`LayoutReconstructor.breaksAtClosedEmDash`: a line ending in U+2014 whose character before the
dash is neither a space nor a dash, joined to a line opening with a letter, a figure, `_` or an
opening quotation mark (a straight `"` or `'`, or a character Unicode classes as initial
punctuation, `“`, `‘`, `«`), joins with no space. Everything else keeps the space: a spaced
dash, a dash alone, a rule of dashes, a next line opening with a marker, a bracket or a dash. The en dash keeps its own narrower rule (#297): a range or compound's en dash
is closed only against a letter or figure, and its next line may not open with a quotation mark.
Neither dash is looked up in the vocabulary or ever raises `uncertainHyphen`.

A book-level test (does this book close its em dashes inside its lines?) was not needed: the
dash's own left attachment separates every case the corpus has. Inside a line, a dash closed
before and spaced after is rare and never at a line end: three entries of the FAA's acronym list
(`RCIU— Remote Control Interface Unit`, among neighbours set `AAI —arrival aircraft interval`)
and one CDC checklist line (`W ater— one gallon`).

## What it moves across the corpus

Every manifest document, baseline against candidate:

| Book | joins closed | anything else |
| --- | ---: | --- |
| gpo-911-2004 | 52 | none |
| noaa-nca5-2023 | 34 | none |
| scotus-loper-bright-2024 | 14 | none |
| faa-phak-8083-25c | 10 | none |
| gpo-warren-1964 | 10 | none |
| fed-explained-2021 | 4 | none |
| usda-ars-agresearch-2012-11 | 3 | none |
| dga-2025-2030 | 1 | none |
| gpo-our-flag-2003 | 1 | none |
| the other 15 books | 0 | byte-identical EPUBs and reports |

**129 joins, and not one other character of any book changed.** 80 chapter files differ, each
smaller by exactly the number of spaces its joins lost (129 bytes in all); read as raw text, each
differs from its baseline only by those spaces (two of them stood after the FAA figure titles'
`—</strong>`, the rest directly after the dash). No block moved between spine files, no report
changed, and the 129 are exactly the probe's first seven rows.

## The 124 line ends #315 counted

- **105 now read closed.** 101 match word for word. Four more were spaced at baseline too, where
  `pdftotext`'s reading differs from the page's: 9/11 page 143 ends `sensitive—` and the
  conversion carries the sentence onto page 144's `on the battlefield`; its pages 184 and 520
  read `training.Atta—` and `others,“Malaysia—` without the page's space; *NCA5* page 591 reads the
  running foot `12-25` after `climate change—`, where the conversion continues with `especially`.
- **10 never reach a join: the conversion ends a block at the dash.** 4 are list items whose
  wrapped line the conversion sets as a paragraph of its own: FAA pages 57 and 362 (`• Another
  important tool—overlooked by many pilots—` over `is a good post-flight analysis`), 162
  (`1. Cylinder arrangement with respect to the crankshaft—` over `radial, in-line…`) and 9/11
  page 205 (`• addressing the problem of migrants—possibly including terrorists—` over `who
  destroy…`), a defect of list items, not of dashes
  ([#319](https://github.com/vocaro/PDFReflowLib/issues/319)). 3 are Loper Bright
  sentences a page breaks, which the conversion does not carry onto the next page: `APA—` ends
  page 37 and page 38 opens `the statute that lays out…`, one of the boundaries #309 counts;
  `decisis—` ends page 113 and page 114 opens with its running head, `KAGAN, J., dissenting`,
  kept as a paragraph; `Congress—` ends page 90's body above a footnote carried over from page
  89, which the cross-page join deliberately does not step over (#306). 2 are
  *Our Flag*'s statute, `the lesser of—` over `(1) 550,000 copies` and `As used in this
  subsection—` over `(1) the term “half-staff”`, whose numbered paragraphs are rightly blocks of
  their own. The tenth is Warren page 239's `HT—`, a label in Commission Exhibit No. 2179.
- **9 are not in the text as prose.** FAA pages 127, 151 and 165 are figure callouts set on a slant
  (`spee`/`d—`, `Roll`/`on—`/`Ailer`); FAA page 413's worked example `the aircraft is—` over its
  calculation sits in a preserved crop, as does *The Fed Explained*'s Figure 2.2 (`all governors—`
  over `including the Chair`); Warren pages 553, 557 and 566 and the Warren excerpt's page 2 are
  OCR text drawn over exhibits (`i<<Vv—`, `Name—` over `RACE`).

## What the rule cannot see

- **9/11's transcripts.** Pages 49 and 60 set each speaker's turn as a line of its own, and the
  conversion runs some turns together into one paragraph. Three turns end in an interrupted
  sentence's dash, and their joins now read `confirmation—FAA: He did not land.`,
  `divert—Controllers: DO…` and `but—Floor Leadership:` where `af18cfb9` wrote a space. Neither is
  what the page prints; the join cannot see that the next line is a new speaker, and a test for a
  speaker's label would also take *NCA5*'s `Savaqatigivlugich—Working with communities: Evolving…`,
  which the source prints closed. The turns running together is the defect:
  [#320](https://github.com/vocaro/PDFReflowLib/issues/320).
- **Warren's OCR layer.** Page 322 reproduces an advertisement that spaces its dashes (`Tito —
  Moscow's Trojan Horse — just`), but the text layer reads both dashes closed, so the join after
  the second now matches the first, `Horse—just`. Page 451 prints `history—a` over `role as the
  "great man"`; the layer lost the `a`, and the join, spaced or closed, cannot restore it.

## Tests

`Tests/PDFReflowLibTests/HyphenRepairTests.swift`, three tests:

- `aLineBrokenAfterAClosedEmDashCarriesOnWithNoSpace`: the issue's three joins, a capital and a
  figure on either side of the dash, a dash closed against `)`, `”` and a run-in heading's stop,
  and a next line opening with `“` or `"`; no warning.
- `aSpacedOrStrandedEmDashKeepsTheSpaceAfterIt`, the controls: Warren's spaced advertisement, the
  Hebrew study's ditto dashes after a stop, a dash alone, a rule of dashes as either line, a next
  line opening with a bullet or a bracket, a line with no dash.
- `aParagraphBrokenAfterAClosedEmDashReadsTheDashClosed`: 9/11 page 25 through
  `LayoutReconstructor.blocks`, with a spaced-dash paragraph beneath it as the control.

Disabling the rule fails 12 expectations in the first and third tests; the controls pass either
way. One existing test expected the old space: #306's
`aParagraphThatRanIntoTheNotesRuleIsNotJoinedPastTheNotes` joins a paragraph ending
`…follow the rule—` past its page's notes to `carries on here.` as its control, and now expects
`rule—carries on here.`; what it tests, that the join steps over the notes, is unchanged.

## Contracts

`corpus/regressions.json` orders each closed join and forbids its spaced form, from the source's
text layer: 9/11 pages 25 (`stabbed—and`) and 108 (`“newspapers”—the`), *NCA5* pages 56
(`innovations—such`) and 1624 (`(NDCs)—emissions-reduction`), Loper Bright pages 19
(`coal—encompassed`) and 22 (`(emphasis added)—even`), the FAA handbook's pages 128
(`Physics—for`) and 367 (`ATC Instructions—“Hold Short”`), and, from the raster, Warren page 349
(`individuals.—The Commission`). `af18cfb9`'s output holds each forbidden form (the sweep above).
With the change, the corpus lane passes all nine books whose output moved, one case at a time:
`runPassed` and no content-assessment error for 9/11 (105 content checks), *NCA5* (435), Loper
Bright (43), the FAA handbook (103), Warren (102), *The Fed Explained* (130), *Agricultural
Research* (75), DGA (24) and *Our Flag* (64).

## Commands

```sh
swift build -c release --product pdf-reflow
pdftotext -enc UTF-8 corpus/cache/<file>.pdf <out>.txt     # every cached source
pdftoppm -r 200 -f <page> -l <page> -x 0 -y <y> -W <w> -H <h> -png \
  corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf <out>      # Warren pages 70, 174, 322, 349, 451, 477, 605, 680, 715, 754, 794, 885
.build/release/pdf-reflow corpus/cache/<file>.pdf <out>.epub <manifest flags> \
  --package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z
python3 tools/epub_identity.py --baseline-epub <before>.epub --candidate-epub <after>.epub
pdftotext -bbox-layout -f 5 -l 5 corpus/cache/noaa_61592_DS1.pdf -   # the poem's row positions
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck "$(command -v epubcheck)" --output <lane> --jobs 1 --case <id>
  # gpo-911-2004, noaa-nca5-2023, scotus-loper-bright-2024, faa-phak-8083-25c, gpo-warren-1964,
  # fed-explained-2021, usda-ars-agresearch-2012-11, dga-2025-2030, gpo-our-flag-2003
```
