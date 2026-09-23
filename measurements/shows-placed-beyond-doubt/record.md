# A show the line can hold in only one place (#260)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: every cached source, with *Beginning and Intermediate Algebra*
(`Beginning_and_Intermediate_Algebra.pdf`, 489 pages) as the subject.
Build: `main` at `e4f9540` with this change, Xcode 27.0, macOS 27.0 (Darwin 27.0.0); release
executable SHA-256 `a78e7aa41ef82d343c69ad713e4c0e5aab2e507e8aaffc049087290741bd9807`.
Baseline: `e4f9540` alone, executable SHA-256
`58cfd80dd047ec49d5099b1ac35c323296a02af88695afb6f5d57069cdbfb614`.

## The question

[#258](https://github.com/vocaro/PDFReflowLib/issues/258) listed five Wallace fusions as one
defect and fixed three. [#260](https://github.com/vocaro/PDFReflowLib/issues/260) records that the
other two were never that defect: `owningShows` returns evidence for both lines, and each fails
later, in `segmentedInsertions`, for a different reason. It asks for an anchored start for one and
"a rule for a line the anchor cannot fit" for the other, without weakening the anchor on the lines
it protects.

## What the two lines are

Both were read directly off the source with a probe that prints a line's owning shows, their
spans in the source's own reading, and the boundaries the rules admitted.

**Page 223.** PDFKit splits the printed row at a wide gap, so the show `66` drawn at x 251.04 has
its first digit on the row above and this line holds the second:

```
EXTRACTED "6and− 1, split the middle term"
SOURCE    "66and−1,splitthemiddleterm"      BOUNDARIES [2, 8]
  show @251.04  src[ 0..< 2]  "66"
  show @280.32  src[ 2..< 5]  "and"
  show @301.20  src[ 5..< 6]  "−"
  show @312.48  src[ 6..< 7]  "1"
  show @318.36  src[ 7..< 8]  ","
  show @323.64  src[ 8..<26]  "splitthemiddleterm"
```

The walk opens at source 0 against extracted 0, where the two `6`s match by coincidence, so it
aligns the show's first digit with the line's second. It disagrees at the next character,
resynchronizes to source 2 — which is the boundary — and drops it, because a boundary at a
segment's opening stands against a disagreeing region's edge (#139 item 1). The alignment that is
right, source 1 against extracted 0, is the one position no test is applied to:
`resynchronize(source:at: 0, extracted:at: 0)` returns `(1, 0)` when it is asked, which is what
#260 proposed and what this confirms.

**Page 224.** Two shows the reader cannot decode are holes, so the source reads seven characters:

```
EXTRACTED "1· 6and 2· 3 "
SOURCE    "16and23"                          BOUNDARIES [2, 5]
  show @153.84  src[ 0..< 1]  "1"
  show @161.64  src[ 1..< 1]  <hole>
  show @166.92  src[ 1..< 2]  "6"
  show @174.72  src[ 2..< 5]  "and"
  show @195.60  src[ 5..< 6]  "2"
  show @203.52  src[ 6..< 6]  <hole>
  show @208.80  src[ 6..< 7]  "3"
```

Seven characters against an `anchorLength` of twelve. `resynchronize(1, 1)` returns nil — it runs
out of source before it can match twelve — so the walk ends at the first hole with nothing
applied, although the boundary at source 2 sits between two characters PDFKit also read.

## The rule

Neither line is answered by weakening the anchor, which is what #119 and #120 raised it for. Both
are answered by not needing one. Where a show's own text stands in exactly one place in PDFKit's
reading of the line, there is nothing to align: the characters are only there. Uniqueness is
stronger evidence than any run of matching characters, and it is read per show rather than per
line, so a line the walk owns keeps everything the walk gave it and gains only what the walk could
not reach.

`uniquelyPlacedInsertions` steps over PDFKit's own spaces, as everything else here does, so a show
is placed against the marks of the line and not its spacing, and a show of one mark is never
placed — one character standing once in a line is a coincidence the line is too short to rule out.
A show carrying whitespace of its own is not placed either: it would not line up mark for mark,
and PDFKit's spacing of it is not something this rule has anything to add to.

On page 223 the show `and` stands once in `6and− 1, split the middle term`, at the line's second
mark, so the boundary at its start is placed there: `6 and− 1, split the middle term`. The other
boundary, at `splitthemiddleterm`, is also uniquely placed and inserts nothing, because PDFKit
already spells a space there. On page 224 the show `and` stands once, at the fifth character:
`1· 6 and 2· 3`. Its other boundary, at the show `2`, is again already spaced.

## What moved, book by book

Every cached source was converted with both executables at `--no-ocr` and fixed packaging
(`--package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`), one book at a
time, and each XHTML document summarized by its SHA-256, block count, character count and hashes
of its tag-stripped text and of that text's marks with whitespace removed.
`GPO-WARRENCOMMISSIONREPORT` and `noaa_61592_DS1` are skipped: they exceed the default output
budget and write no book.

**Twenty-one of the twenty-two are byte-identical**, every document of every one. That includes
the two books whose lines set this rule's constraints: the 9/11 report, whose appendix rows
raised `anchorLength` from eight to twelve (#120) and whose justified pages #119 was measured on,
and Project Blue Book, which has more shows the reader cannot decode than any other. Also the FAA
handbook, the USCIS Arabic guide, the replay-clocks paper, the census paper, *The Fed Explained*,
IRS Publication 596 in Chinese, the DGA, *Loper Bright*, *Our Flag*, *Agricultural Research*, the
CDC graphic novel, the NASA slides, the two NTRS papers, the THM report, the Pro Se complaint, the
NBS paper, the USGS copper summary and the Warren suspect-text excerpt.

**Wallace is the one book that moves**, in one of its fifteen spine documents:

| | baseline | with this change |
| --- | ---: | ---: |
| spine documents | 15 | 15 |
| blocks | 6,931 | 6,931 |
| characters | 493,358 | 493,361 |

Three characters, which are three spaces. The hash of every document's text with whitespace
removed is unchanged, so no character is gained, lost or moved: the book's words are what they
were and three of them are now apart.

| page | before | after |
| ---: | --- | --- |
| 223 | `6and− 1, split the middle term` | `6 and− 1, split the middle term` |
| 224 | `1· 6and 2· 3` | `1· 6 and 2· 3` |
| 235 | `(x + 3)match!` | `(x + 3) match!` |

The third is not named by #260 and is the same defect. Page 235's line holds a spanning show from
the row beside it, so its source reads `+3)](x+3)match!` against PDFKit's `(x + 3)match!`, and the
walk resynchronizes on eleven matching characters where it asks for twelve — one short, with the
line exhausted. The show `match` stands in exactly one place, so the boundary the `)` closes is
placed at it.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. The corpus lane passes 18 of 18
covered cases, every case's `runPassed` and content assessment read from its own `result.json` and
`content-assessment.json`. All 675 Swift tests pass, including the twenty-two spacing tests, which
are the standing controls for #119, #120, #128, #139 and #258 and are unchanged.

Two tests are added to `Tests/PDFReflowLibTests/NativeSpacingTests.swift`, both citing #260: the
two pages read from checksum-pinned source captures (`algebra-223-spacing.json` with
`algebra-223-layout.json`, and the same pair for 224), and the rule itself with its refusals — a
show the line holds twice, a show of one mark, and a boundary PDFKit already spells with a space.

## What is not claimed

The three changed lines were read against the source's own shows; the rest of Wallace, and the
rest of every other book, is read only through the per-document hashes above. Uniqueness is asked
of a show against one PDFKit line, not against the page or the book, so this says nothing about a
show that recurs elsewhere on its page. And it adds no reading to a line the segmented walk
already owns: every insertion here is one the walk returned nothing for.
