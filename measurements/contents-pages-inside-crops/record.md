# Contents pages inside image crops, and the two items of #207 that were already answered

Measured under [#207](https://github.com/vocaro/PDFReflowLib/issues/207), baseline `b474f64`,
2026-09-21, macOS 27 / Xcode 27, arm64, release CLI at library defaults. The baseline binary is
built from `b474f64` itself; the changed binary is that tree plus this commit and nothing else.
Character counts of a page's extraction are the characters of every line PDFKit returns for it;
character counts of a converted book are `outputTextCharacters` as the corpus lane reads it.

#207 names three items. Two of them are already answered on `b474f64` and are recorded here as
measurements rather than changes; the third is real, and this commit is its fix.

## Item 1: the 9/11 report's abbreviations list (page 448) does not run entries together

Physical page 448 prints the second half of Appendix A, `NORAD` through `WTO`. PDFKit merges
fifteen of its twenty rows into one line each (`NTSB National Transportation Safety Board`) and
reads five apart (`NORAD` at x=39.66 and `North American Aerospace Defense Command` at x=129.66,
on one baseline). Converted at `b474f64`, the page's twenty entries are twenty `<pre>` blocks,
each carrying its abbreviation and its expansion:

```
<pre> 'NORAD North American Aerospace Defense Command'
<pre> 'NTSB National Transportation Safety Board'
…
<pre> 'WTO World Trade Organization'
```

No block holds two abbreviations, and page 447 — `CAP` through `NMCC`, with `CAPPS` and `FDNY`
read apart — is the same. The page's own order is kept, including the two places the report
itself prints out of alphabetical order (`DIA` above `DCI` on 447, `NTSB` second on 448), which
`pdftotext -layout` confirms are the page's and not the converter's.

The issue says the row-edge split from #199 cannot find its evidence here. That split is not on
this tree at all: `1335cd1` is an ancestor of `main` through the `ours` merge of the abandoned
coordination branch ([decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md)),
and `rowEdges`, `splitAtRowEdges`, `splitBorderlessTables`, `splitColumnGrids` and
`unprintedLineEndHyphen` appear nowhere in `Sources/`. Main's answer to this page is the
same-row join (#57), which is enough because the abbreviation and its expansion are the only two
pieces of the row.

Pinned by `theAbbreviationsListKeepsOneEntryPerBlock` over a fresh capture of the page
(`Tests/PDFReflowLibTests/fixtures/911-448-layout.json`). That test passes on the baseline too,
which is the point of it.

## Item 2: the 9/11 report's flight timelines (pages 50–51) are read column by column

Each page sets two timelines side by side, thirteen and ten entries on page 50, eleven and eleven
on page 51. PDFKit merges the time with its event on some rows (`7:59 Takeoff`, one line) and
reads them apart on others (`8:19` at x=39.66 beside `Flight attendant notifies AA of` at
x=75.66). Converted at `b474f64`, every entry is one block carrying its own time, and the left
timeline is read whole before the right one opens:

```
<pre> '7:59 Takeoff'
<pre> '8:14 Last routine radio communication; likely takeover'
…
<pre> '9:24 NEADS scrambles Langley fighter jets in search of AA 11'
<pre> '8:14 Takeoff'
…
<pre> '9:20 UA headquarters aware that Flight 175 had crashed into WTC'
```

All forty-five entries of the two pages were read against `pdftotext -layout` of the source: none
is missing, none is split, none is woven into the other column. The issue's note that an early
looser version of #199's split interleaved them describes a rule this tree never had.

One thing on those pages is still wrong, and it is not what the item describes. PDFKit merges the
*second* heading row — `(AA 11)` and `(UA 175)` — into one line spanning the gutter
(x=39.66, width 199.63, where the two columns' other heading rows are read apart at x=39.66 and
x=195.67). That merged line bridges the two columns, so no whitespace cut separates the heading
group, and it then takes the left column's `Boston to Los Angeles` into its own paragraph and
strands the right column's. Fixing it means cutting a line PDFKit merged, which this tree has no
facility for, so it is filed as [#270](https://github.com/vocaro/PDFReflowLib/issues/270) rather
than forced here.

Pinned by `theTwoFlightTimelinesAreReadColumnByColumn` over the existing `911-50` and `911-51`
captures; it too passes on the baseline.

## Item 3: the climate assessment's contents pages

`noaa-nca5-2023` pages 9–18 are its table of contents. Each sets its entries from the left margin
to a page number at the right edge, with a painted leader between them, and each places the same
decorative line drawing over its top right corner — a placed raster XObject at
[358.5, 409.3, 433.5, 202.7] on a 792 × 612 page. Measured on `b474f64` with a probe that runs
`graphicsWithLabels` and `LayoutReconstructor.takes` over the page exactly as `blocks` does:

| page | lines | characters | lines in crops | characters in crops | share | crops before | crops after |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 9 | 45 | 1,491 | 31 | 1,085 | 73% | 4 | 1 |
| 10 | 45 | 1,551 | 31 | 1,136 | 73% | 6 | 2 |
| 11 | 43 | 1,672 | 19 | 793 | 47% | 6 | 1 |
| 12 | 37 | 1,337 | 20 | 776 | 58% | 6 | 3 |
| 13 | 37 | 1,362 | 20 | 776 | 57% | 4 | 1 |
| 14 | 43 | 1,608 | 22 | 970 | 60% | 5 | 1 |
| 15 | 45 | 1,801 | 20 | 1,017 | 56% | 7 | 2 |
| 16 | 34 | 1,299 | 19 | 891 | 69% | 3 | 1 |
| 17 | 35 | 1,239 | 22 | 828 | 67% | 5 | 1 |
| 18 | 43 | 1,448 | 27 | 1,009 | 70% | 5 | 1 |
| **total** | **407** | **14,808** | **231** | **9,281** | **63%** | **51** | **14** |

After this commit not one line of any of the ten pages stands inside a crop.

### Two mechanisms, read off page 9

**The drawing swallowed the rows it lies across.** The drawing's rectangle covers the right end
of the nine rows between y=411 and y=612 — `Chapter 4. Water … 4-1` runs from x=72 to x=556.57,
and the drawing starts at x=358.5. `takes` holds a line whose middle row a crop holds, with no
horizontal test at all, so every one of those rows was captured whole; the crop then grew to
x=70 and took the rest with it. No cut clears them, because the drawing stands in the middle of
the rows, so neither #255's prose release nor #246's edge band reaches the case.

**Nineteen leaders each seeded a figure of their own.** The page paints one leader per entry, a
rectangle 4 pt tall running from the end of the entry's text to its page number. Where the entry
is short PDFKit reads the whole row as one line (`Introduction \b 6-5`, x=90 to x=556.58) and the
leader lies inside that line's measure, so the existing rule already called it decoration. Where
the entry is long PDFKit reads the number apart, and the leader — for instance
[362.6, 397.5, 179.0, 4], beside `Key Message 5.1. Climate Change Threatens Energy Systems` which
ends at x=366.57 — reaches 175 points past its own line's right edge and owns nothing, so it
stayed an isolated graphic and seeded a crop that took the entry and its number.

### The rules

`LayoutReconstructor.reachesInto` answers the first. A crop neither captures, grows into, nor
takes a printed row a piece of which straddles the crop's edge, nor the pieces of that row
standing to that piece's right. Three conditions were arrived at by measurement, each after a
corpus run showed what the rule without it does:

| condition | measured cost of leaving it out |
| --- | --- |
| a piece must *straddle* the edge, not merely stand left of it | the Replay Clocks paper's six sub-captions share two baselines across three figure columns, and `(a) 𝛼 = 20 messages/s, 𝑛= 32.` freed `(b)` and `(c)` from their own figures' crops: +119 characters on that book |
| the crop must preserve a placed raster image | Wallace's fraction crops reach leftwards to the exercise numbers that are part of their expressions; without it page 187 gained `33) (zy2)4 2yzx2 2x4y4z` out of its own crop and pages 294 and 351 lost sixteen and six tokens into others |
| that image must not cover the page | the CIA report's crops sit on scans, and its rows begin outside them: +15,471 characters of `~,....,....,....r-T""S....,...,-100` and `:~::;~]!1111111111~~11111111111` into the prose, which is what #255 and #257 spent two commits keeping inside those pictures |

A table's column header is excluded as well, for the reason #257 gives: the CIA report's page 203
paints a rule across a header row that begins outside it, and that header labels the columns of
the picture the crop preserves.

`graphicsWithLabels` answers the second. A thin rule no single line owns is read against the
measure of the printed row it strikes through. The row must hold at least two pieces, each of
which the rule touches or abuts within a body — a page sets its columns further apart than that,
and without the distance test the Replay Clocks paper's algorithm rules were owned by the prose
column half a page to their right, which cost two junk rule-pictures and one joined paragraph on
its page 4. And a row may only take a rule *away* as decoration, never widen it to the row's
measure, which reaches across the page's columns: unioning a mathematical rule with it carried
Wallace's crops over the exercise beside their own, −795 characters on that book.

### End to end

Pages 9–18 cut out with `qpdf --pages … 9-18` and converted with both binaries (the excerpt is a
reading aid, not a pinned source; the full book is excluded from the lane for the image-output
ceiling, [noaa-output-policies](../noaa-output-policies/record.md)):

| | baseline `b474f64` | with this commit |
| --- | ---: | ---: |
| characters inside source-page markers | 5,501 | 14,717 |
| images | 61 | 24 |

Page 9 opens `Traceable Accounts 5-19 References 5-27 6-1 Introduction 6-5 …` on the baseline and
`Chapter 4. Water 4-1 Introduction 4-4 Key Message 4.1. Climate Change Will Continue to Cause
Profound Changes in the Water Cycle 4-6 …` with the change.

## The corpus

All eighteen cases pass on the baseline and on the change, read case by case from each case's own
`result.json`: `runPassed: true` and `memoryGate.status: passed` for every one, on both.

Seventeen of the eighteen books are unchanged to the character. One moves:

| book | characters | what moved |
| --- | ---: | --- |
| `gpo-our-flag-2003` | 80,948 → 80,919 (−29) | its title page draws a rule the width of the row beneath `108th Congress, 1st Session` … `H.Doc. 108-97`, which was preserved as a 310 × 4 pt picture; the picture and its `Preserved region from page 3` caption are gone and no word of the book moved |

The 29 characters are that caption. No book loses a word.

## Reproducing

```sh
swiftc -O Sources/PDFReflowLib/{AnchorMatcher,BlockAssembler,CGPDFObjects,CJKText,\
ChapterBoundaryReader,ContentStreamWalk,ConversionTypes,ConversionWarnings,DocumentEvidence,\
DocumentModel,EmbeddedImageReader,EnglishText,FractionRegionDetector,FurnitureDetector,\
GlyphIdentityReader,GlyphIndexDecoder,GraphicsReader,HyphenRepair,ImageContentClassifier,\
LayoutReconstructor,MarkedTextReader,NativeSpacingOwnership,NativeSpacingReader,NativeTextReader,\
NumberedNoteDetector,OCRReader,OCRTextCoverage,OutlineReader,PDFPageSource,PageDiagnosis,\
PageRasterizer,PageReader,PageTypography,RecognitionPolicy,ReflowDocument,SourceMetadata,\
StructureTreeReader,TableRegionDetector,TextEncodingCheck,TextLayerPlausibility,TextLineGeometry,\
XMLText}.swift measurements/contents-pages-inside-crops/tools/dump-page.swift -o /tmp/dump-page
/tmp/dump-page corpus/cache/noaa_61592_DS1.pdf 9,10,11,12,13,14,15,16,17,18 /tmp/noaa.json
```

`dump-page.swift` prints, per page, the crops `graphicsWithLabels` forms, the seeds it reads them
from, every line PDFKit returns with whether a crop takes it, and the blocks reconstruction makes.
It is diagnostic extraction only: no converter output, no rasters.
