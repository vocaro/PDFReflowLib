# A cell that closes a printed row is not a line the page broke (#285)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: every cached source, with Project Blue Book Special Report No. 14
(`CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf`, 312 pages) as the subject.
Build: `main` at `15b1ab1` with this change, Xcode 27.0, macOS 27.0 (Darwin 27.0.0); release
executable SHA-256 `062916e6c0812020c356d4c688510967f81785218686ebb303e59c4a52a27eb2`.
Baseline: `15b1ab1` alone, executable SHA-256
`8b6a6f8976f314998230ee5bfa41a3d91b6bcbb3a880e95644acf3841fa04bdb`.
A third executable was built to separate the two halves of the question: `15b1ab1` with
`readsAsOneLine` returning `rightToLeft`, the rule as #41 left it, which is the reading before
[#272](https://github.com/vocaro/PDFReflowLib/issues/272).

## The question

#272 let a printed row the extractor split stand for one line when the next line's column edge is
measured, and its own record closes by naming what it left behind: five rows of Project Blue
Book's statistical appendix take the row beneath them.
[#285](https://github.com/vocaro/PDFReflowLib/issues/285) asks what separates those five from the
joins the rule exists for, and offers two places for the answer — the scanned-table rule (#31,
#137), giving a page whose sizes are unreliable another way to state its rows, or a bound on how
unlike a paragraph a "paragraph" of this shape may be before its lines stop joining.

**It is the second, and the measure is the piece that closed the row.**

## The nine blocks #272 changes in this book, measured

Converting the Blue Book with the `rightToLeft` executable and with `15b1ab1` at `--no-ocr` and
fixed packaging (`--package-identifier urn:uuid:identity
--modification-date 2026-01-01T00:00:00Z`) and comparing block by block gives exactly nine
changes, which is what #272's record states. Instrumenting `readsAsOneLine` and
`continuesParagraph` on the same build prints the pair each one turned on:

| page | row's closing piece | the line that joined it | body | row start | line start |
| ---: | --- | --- | ---: | ---: | ---: |
| 112 | `Less` | `Than One Hundred Miles per Hour .` | 7 | 129.79 | 135.77 |
| 112 | `One` | `Hundred to Four Hundred Miles per Hour.` | 7 | 129.79 | 135.32 |
| 112 | `Over` | `Four Hundred Miles per Hour.` | 7 | 130.03 | 135.32 |
| 46 | `-` | `Not stated` | 12 | 364.78 | 364.05 |
| 182 | `26 JJ' S'I- ff.I /9.!i 5i.t. If j'_,` | `2·Aircraft q I s 2/./ ~.f ·?tJI ? I` | 9 | 82.06 | 81.33 |
| 195 | `/ff. 2, 2.1.1 / I .t, 5:1, 5.t II 1.` | `3-liihtPh-. / I :2. ;,/5 d5 ?. tJ I` | 9 | 88.05 | 88.25 |
| 241 | `-- .7/ {',t)' "EC't?IVP.5` | `Nuntier Per Cent Nllmber PerCml` | 10 | 340.90 | 351.03 |
| 242 | `~ 2(./ /.l,O .2/.I` | `I-Psychological £1 I I CUJ l.t, /,t,` | 10 | 80.83 | 80.86 |
| 242 | `✓.:-` | `2-Aircraft C, 2.. ,:2._ tJ. () 1(.2` | 10 | 81.82 | 81.33 |

The first four are right — three captions in the list of tables and the speed legend's "not
stated" — and the last five are the defect.

## What does not separate them

Each of these was measured on the nine pairs above and each fails, which is why the rule that
landed is about what the page wrote rather than where it wrote it:

- **The number of pieces the row was split into.** Every one of the nine is two pieces except
  page 241's three. The eight-column rows do not arrive as eight pieces: their cells stand wider
  apart than a gutter, so `continuesRow` never joins them, and the row this rule sees is the two
  cells that happened to fall within 0.75 of a body.
- **How often the page splits its rows.** Over the whole book the extractor splits 278 rows at a
  space in 312 pages, and on the appendix's own pages that is between none and three rows out of
  forty. A page of cells does not announce itself by splitting more rows than a page of prose.
- **The indent of the line beneath.** The captions' wraps stand 4.5 to 6.0 points in from the
  row's start (0.6 to 0.9 of a body); the five table rows stand between 0.7 points out and 10.1
  points in (−0.1 to 1.0 of a body). The two populations overlap.
- **How much of the row's measure the line beneath fills.** 37%, 45%, 54% and 76% for the four
  right joins; 38%, 54%, 93%, 100% and 100% for the five wrong ones.
- **The page's own leading.** `onStatedLeading` is already asked and is vacuous on both sides:
  this book gives every printed row a size of its own (#216, #137), so `prev.hasSize` is false on
  the table rows, and the page states no leading at all on page 46, where the legend join is
  right.

## What separates them

The reading already takes a split row's text and its wrap from the piece that closed it — that is
#272's own rule, because that is what the writing did. So that piece is what has to read as a
line of writing for the row to stand for one. `readsAsWriting` asks it: at least half of a piece's
marks are letters, in any script, and a piece of fewer than three marks is asked nothing, because
one character says nothing either way.

On the nine: `Less`, `One` and `Over` are all letters, `-` is one mark, and the five cells are
43%, 22%, 33%, 21% and 0%. The gap between the two populations is the whole middle of the range.

Against the pieces the rule exists for, which are prose: the 9/11 report's
`the 9/11 attack. At the time of their travel through` is 89% letters, the replay-clocks paper's
`occurred far later than` and the census's `Lambert, D.: … Journal of Official Statistics,`
higher. Nothing in this corpus closes a row this rule must read with a piece between a third and
a half.

## What moved, book by book

Every cached source was converted with both executables at `--no-ocr` and fixed packaging
(`--package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`), one book at a
time into a temporary directory, and each XHTML document summarized by its SHA-256, its block
count, its character count and hashes of its tag-stripped text and of that text's marks with
whitespace removed. `GPO-WARRENCOMMISSIONREPORT` and `noaa_61592_DS1` are skipped: they exceed the
default output budget and write no book, which is why the corpus lane excludes them too.

**Twenty-one of the twenty-two are byte-identical**, every document of every one: the NASA slides,
the two NTRS papers, *Loper Bright*, the replay-clocks paper, *Beginning and Intermediate
Algebra*, *Our Flag*, the Dietary Guidelines, **the 9/11 report**, the USCIS Arabic guide,
*Agricultural Research*, the THM report, the CDC graphic novel, the Pro Se complaint, the FAA
handbook, the NBS paper, the USGS copper summary, IRS Publication 596 in Chinese, the census
paper, *The Fed Explained* and the Warren suspect-text excerpt.

The 9/11 report is the control that matters most: page 259 is the join this rule was added for,
and its closing piece `the 9/11 attack. At the time of their travel through` is writing, so
nothing about it moves. The USCIS Arabic guide is the other: right-to-left rows return before
this test is reached, as #41's rule requires, and the book is unchanged.

**Project Blue Book is the one book that moves**, in 8 of its 20 spine documents:

| | baseline | with this change |
| --- | ---: | ---: |
| spine documents | 20 | 20 |
| blocks | 22,045 | 22,050 |
| characters | 829,471 | 829,481 |

Five blocks more, which are the five rows in the table above, each now standing apart from the
row it had taken. Against the `rightToLeft` executable — the reading before #272 — this build
differs in exactly four blocks, and they are the three captions and the legend: #272's gain is
kept whole and its residue is gone.

The book's letter stream is unchanged. Concatenating every spine document, stripping markup and
removing whitespace gives 613,732 marks in both builds, and the two agree character for character
once the document's own `CIA-UAP-015` stamp is removed — that furniture line sits one block
earlier or later where a block was split, which is the whole of the difference. No word of this
book, or of any other, is gained, lost or reordered.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. The corpus lane passes 18 of 18
covered cases, every case's `runPassed` and content assessment read from its own `result.json` and
`content-assessment.json`.

Two tests are added to `Tests/PDFReflowLibTests/ReadingOrderTests.swift`, both citing #285: the
Blue Book's row shape with its own control — the same geometry closed by writing, which still
joins — and the bound itself, including the pieces the rule must keep admitting and the two-mark
legend it asks nothing of. With `readsAsWriting` returning true unconditionally, the first fails
and the second's refusals fail, which is what a bound that does something should do.

## What is not claimed

The nine changed blocks were read against the book's own pages; the rest of it, and the rest of
every other book, is read only through the per-document hashes above. This rule says nothing about
whether the Blue Book's appendix should be *tables* — it is still nine hundred rows of prose, and
that is [#31](https://github.com/vocaro/PDFReflowLib/issues/31) and
[#137](https://github.com/vocaro/PDFReflowLib/issues/137), the other place #285 offered for the
answer. What it settles is narrower: a row of cells no longer lends a start it never had.

Half the marks is where these two populations separate on this corpus, with the whole middle of
the range empty between them; a book that set a table of words, or a line of prose that the
extractor split before a run of figures long enough to outweigh it, would not be told apart this
way, and nothing in the twenty-two does either.
