# Crops stop admitting the book's own prose

Measured under [#255](https://github.com/vocaro/PDFReflowLib/issues/255), baseline `a55a85e`,
2026-09-20, macOS 27 / Xcode 27, arm64, release CLI at library defaults.

`LayoutReconstructor.expanded` trims a crop away from a line it merely touches. Where no cut
clears the line while still containing the region's core, the fallback admitted the line into the
crop instead, and `blocks` then dropped every line the crop took. [#246](https://github.com/vocaro/PDFReflowLib/issues/246)
restricted that fallback for full-measure bands at a page edge; it still applied everywhere else.

The rule now: **a crop never admits a line of the book's own prose.** Where no cut clears such a
line, the crop keeps its own extent instead of growing into it, exactly as #246's edge band does.
`takes` then leaves the line in the prose, so the picture loses nothing and the sentence is not
buried.

Prose is four or more words of two letters or more — `readsAsSentence`, the predicate the crop
rules already used — and, for a line written in the Latin alphabet in a book that declares
English, it must also read as English words.

## What it recovers

| Book | Non-whitespace characters | Gain |
| --- | --- | ---: |
| usda-ars-agresearch-2012-11 | 28,234 → 53,781 | **+25,547** |
| wallace-algebra-2010 | 360,438 → 369,575 | +9,137 |
| irs-p596-zhs-2025 | 35,332 → 39,807 | +4,475 |
| cia-blue-book-14-1955 | 685,711 → 688,530 | +2,819 |
| uscis-m618-arabic-2015 | 93,395 → 95,176 | +1,781 |
| faa-phak-8083-25c | 1,430,119 → 1,430,863 | +744 |
| census-rrs2002-01 | 33,774 → 34,513 | +739 |
| arxiv-replay-clocks-2023 | 41,072 → 41,584 | +512 |
| **total** | | **+45,754** |

Three quarters of the magazine's text was inside crops. What comes out is the articles —
`A strong alliance has long existed be-`, `interrupt malaria transmission in the South` — and in
Wallace the worked solutions' prose, in the Census paper `A record linkage process attempts to
classify pairs in a product space`, in the arXiv paper its figure captions.

The corpus lane passes 16 of 18 covered, with no content-contract and no structural failures.

## The word test, and why it is only for English

Without it the CIA Blue Book gains 6,560 characters instead of 2,819, and the extra is its
handwritten and typewritten tables' text layer: `0/iLE 1112£ E/(19U/,£r//?/Z/ <?E O,fJE(!r`.
Those lines pass the sentence shape, because splitting on non-letters makes junk tokens that are
two letters long, and recover nothing a reader wants.

Applying the same test to every line costs the two books whose text is not Latin: IRS Publication
596 drops from +4,475 to +9 and the USCIS guide from +1,781 to nothing, because the corpus lane
converts at library defaults, which declares English for them, and an English lexicon reads a
Chinese or Arabic line as no words at all. So the test runs only where the line is written in the
Latin alphabet. A book converted with its own `--language` never reaches it (#108).

## What this costs, and does not fix

**The magazine's recovered text is interleaved.** Its columns read
`A strong alliance has long existed be-` / `objectives was to determine how to` /
`tween USDA and DOD—as far back as`: one line of each column in turn, as one-line paragraphs. The
lines were always in that order; they were inside pictures, where no reader met them. This is
[#174](https://github.com/vocaro/PDFReflowLib/issues/174)'s defect — the whitespace cut cannot
separate that book's L-shaped columns — showing on text it used to hide, not a new one, and the
crop images are still there, so nothing a sighted reader had is lost. It is the largest single
reason this change was measured and left unlanded before, and it is recorded here rather than
argued away.

**Some of the CIA report's table text still comes out**, 63 paragraphs of it, including column
headers (`Number Per Cent Number Per Cent`) that belong to the picture of their table and a few
lines of handwriting the word test admits. Filed as
[#257](https://github.com/vocaro/PDFReflowLib/issues/257).

**It does not fix [#136](https://github.com/vocaro/PDFReflowLib/issues/136)**, the issue that led
to this measurement: the NBS paper's `subject to the initial condition` is still inside its crop,
because that crop takes it by capture rather than by the fallback this changes.

IRS Publication 596 gains 18 headings, of which two are the halves of one cover title that the
crop used to hide half of; a heading broken over two printed lines is not joined.
