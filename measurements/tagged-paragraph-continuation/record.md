# One paragraph in progress, tagged or not (#67, #238)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI.
Baseline: repository `929e8a9` ("Finish the wrapped-line merge: strip stray conflict markers and
refresh the snapshot"), the tree this change is measured against.
`document-numbers.json` holds the per-case numbers quoted below and every page that changed.

## What was wrong

Two changes developed against different bases landed on the same day and interact.

[#39](https://github.com/vocaro/PDFReflowLib/issues/39)/[#238](https://github.com/vocaro/PDFReflowLib/issues/238)
added `LineRole.markedLine` and `BlockAssembler.continuesWrapped`, which keeps a wrapped line
opening with an initial, a citation abbreviation or a year inside the paragraph above it. It reads
two things the assembler owns: `previous`, the last line appended, and a non-empty open paragraph.

[#67](https://github.com/vocaro/PDFReflowLib/issues/67)/[#91](https://github.com/vocaro/PDFReflowLib/issues/91)
scoped the tag gate to what each show can describe. Pages that used to have their whole tag set
refused now have it applied in part: the Loper Bright slip opinion went from 0 pages applied and
114 refused to 114 partly applied. A partly tagged page hands `LayoutReconstructor.blocks` tagged
and untagged lines of one printed paragraph in turn.

`BlockAssembler` held two parallel slots for text in progress — `tagged` for a structure group and
`paragraph` for the spatial rules — and each `append` flushed the other. So every crossing between
a tagged and an untagged line ended a block, and the open paragraph and `previous` that
`continuesWrapped` reads were cleared at the crossing.

Loper Bright page 13 (printed 5) is the measured case. Exactly one line of a nine-line paragraph
carries a `P` group — its first, `A divided panel of the D. C. Circuit affirmed. See 45` — because
the shows this reader still cannot place cost their own groups and no more. `appendTagged` took
that line into the `tagged` slot, leaving `previous` nil and `paragraph` empty; the next line,
`F. 4th 359 (2022). The majority addressed various provi-`, reads as a marker line, found no open
paragraph to test against, and became a `<pre>` block cutting the sentence and breaking `provi-`
from `sions`:

    <p>A divided panel of the D. C. Circuit affirmed. See 45</p>
    <pre>F. 4th 359 (2022). The majority addressed various provi-</pre>
    <p>sions of the MSA and concluded that it was not "wholly un-ambiguous" …</p>

Joining the marker line into an open tagged slot is not enough on its own, because the line after
it is ordinary prose and would flush the slot in turn: the paragraph is still cut, one line later.

## What changed

`BlockAssembler` keeps **one** paragraph in progress, and the structure group travels with it in
`paragraphTag` rather than in a second slot. `flushParagraph` emits the tagged paragraph or
heading it used to emit from `flushTagged`, with the same `structureGroup` and the same heading
identifier; `flushTagged` is gone.

- `appendTagged` flushes only when the open paragraph belongs to another group, which includes an
  untagged paragraph. A group the tags name is a paragraph boundary the source states, so it still
  always opens its own block, whatever the geometry says. It now records `previous`.
- `append(_:as:)` no longer flushes the tagged text unconditionally. A tagged **heading** still
  takes no untagged line: the tags said where that heading ends. A tagged **paragraph** is offered
  to the same `continuesParagraph` and `continuesWrapped` tests every untagged line passes.

Nothing else moved: `isList`, `isMarked`, `markerColumn`, the note detector, the tag gate,
`structuredOrder`, the heading rule, the public API and every default are unchanged.

## Verification

`Tests/PDFReflowLibTests/LayoutEvidenceTests.swift` gains two tests.

`aParagraphTaggedOnlyOnItsFirstLineStaysOneParagraph` reads Loper Bright page 13 from the source's
own bytes: `loper-13-tags.json`, captured with `tools/capture_tag_fixture.py`, replays the page's
content stream, fonts and structure subtree, and `loper-13-layout.json` carries PDFKit's lines for
the same checksum-pinned page. It asserts that the tags apply in part, that exactly one line — the
paragraph's first — is tagged at heading level 0, that the wrapped `F. 4th` line is not, that the
reconstruction produces no preformatted block and one paragraph holding the whole sentence, that
the block keeps the source paragraph identity, and that the page's non-whitespace characters are
exactly the source lines'.

`anUntaggedLineContinuesATaggedParagraphButNeverATaggedHeading` states the assembler's half
directly: a tagged paragraph takes the untagged marker-leading wraps that continue it into one
block carrying the group, while a tagged heading followed by prose stays two blocks with the
heading's identifier and group unchanged.

Both fail against `929e8a9` — the first with the `<pre>` block still present, the second with
three blocks instead of one — and pass here.

Commands on the final tree:

- `swift test`: 386 tests pass.
- `scripts/check-all.sh --fast`: all ten gates pass.
- `python3 tools/run_corpus_regressions.py --converter "$(swift build -c release --show-bin-path)/pdf-reflow"
  --epubcheck "$(command -v epubcheck)" --output <dir> --jobs 2`: all 18 gated cases pass.

## Before and after

Whole-book conversions with the release CLI at library defaults, reading every page out of the
EPUB. `<pre>` counts are #238's census: blocks, those between a `<p>` that does not end a sentence
and a `<p>` opening lower-case, and those ending in a hyphen.

| document | words | headings | images | `<pre>` | interrupting a sentence | ending in a broken word |
| --- | --- | --- | --- | --- | --- | --- |
| `arxiv-replay-clocks-2023` | 8,121 | 3 | 70 | 2 | 1 | 0 |
| `cdc-zombie-pandemic-2011` | 2,706 | 86 | 42 | 1 | 0 | 0 |
| `census-rrs2002-01` | 6,417 | 25 | 37 | 17 | 0 | 0 |
| `cia-blue-book-14-1955` | 168,660 | 0 | 421 | 666 | 37 | 16 |
| `dga-2025-2030` | 2,365 | 14 | 28 | 8 | 4 | 0 |
| `faa-phak-8083-25c` | 246,850 | 635 | 619 | 506 | 55 | 1 |
| `fed-explained-2021` | 29,920 | 189 | 317 | 81 | 19 | 14 |
| `gpo-911-2004` | 299,407 | 79 | 101 | 1,291 | 43 | 190 |
| `gpo-our-flag-2003` | 13,277 | 54 | 147 | 7 | 0 | 1 |
| `gpo-warren-1964-suspect-text-excerpt` | 957 | 0 | 5 | 2 | 0 | 0 |
| `irs-p596-zhs-2025` | 4,268 | 101 | 140 | 60 | 1 | 0 |
| `nbs-jres-geltman-1977` | 835 | 0 | 8 | 1 | 0 | 0 |
| `ntrs-20180003024-earthdata-slides-2018` | 477 | 20 | 21 | 3 | 0 | 0 |
| `scotus-loper-bright-2024` | 38,308 → 38,307 | 6 | 0 | **13 → 7** | **3 → 1** | **2 → 0** |
| `uscis-m618-arabic-2015` | 18,947 | 102 | 213 | 6 | 0 | 0 |
| `usda-ars-agresearch-2012-11` | 4,253 | 10 | 75 | 2 | 1 | 0 |
| `usgs-mcs2025-copper` | 922 | 0 | 3 | 0 | 0 | 0 |
| `wallace-algebra-2010` | 70,141 | 174 | 2,151 | 2,909 | 13 | 4 |
| **total** | **916,831 → 916,830** | 1,498 | 4,398 | **5,575 → 5,569** | **177 → 175** | **228 → 226** |

Loper Bright is back to the seven preformatted blocks, one interrupting a sentence and none ending
in a broken word that #238 measured, with #67's tags still applied.

**One page of the corpus's 2,508 changes, and no page loses words.** Loper Bright page 13 falls
from 316 words to 315, which is `provi-` and `sions` becoming `provisions` at a line break the
split had broken. Concatenating every block of every book and dropping whitespace and hyphens
gives a byte-identical digest before and after for all 18 cases (4,688,529 characters). Every
other page's word, heading and image counts are unchanged, and each book's converter report and
its complete warning stream — code, page and message, `structureFallback` included — are identical
before and after, so #67's gate behaviour is untouched.

Positive controls, all unchanged: Wallace keeps its 2,909 preformatted exercise lines, the Fed
book its 81 bulleted and numbered blocks, Our Flag its 54 headings, and the IRS and DGA books
every number they had. The suite's own controls for the same properties still pass:
`corpusListOpeningsKeepTheirOwnBlocks` (Wallace's numbered exercises, the Warren points under a
synthetic text style, the Fed bullets), `ourFlagTwoLineTitleUsesSingleSourceH3` (a tagged `H3`
whose two lines are one heading, over the whole page's words) and
`assemblerFlushesGroupsInOrderWithStableHeadingIdentifiers` (a tagged heading followed by prose,
with its heading identifier and group).

Page 13's paragraph now reads as the page prints it, and the paragraph above it still ends where
the source ends it, because a tagged group still opens its own block:

    <p>… deference to the agency's interpretation would be warranted under Chevron.
       544 F. Supp. 3d 82, 107 (DC 2021); see id., at 103–107.</p>
    <p>A divided panel of the D. C. Circuit affirmed. See 45 F. 4th 359 (2022). The majority
       addressed various provisions of the MSA and concluded that it was not "wholly
       unambiguous" … Id., at 375.</p>

## Remaining gaps

- The reverse crossing is still a break: a paragraph whose **later** lines are the tagged ones
  starts a new block at the first tagged line, because a group the tags name always opens its own
  block. That is deliberate here — the geometric test would otherwise have merged Loper page 13's
  two printed paragraphs, which it separates correctly today — but a page tagged that way keeps a
  split the source does not print. No corpus page exhibits it; finding one needs a producer that
  tags the tail of a paragraph and not its head.
- Everything #238 listed as remaining is unchanged: four of Loper Bright's seven blocks are marker
  wraps after a line ending in an abbreviation, two depend on cross-page continuation (#45), and
  the seventh is its `* * *` separator. Ragged-right columns and bibliography entries still keep
  the preformatted representation (#219 item 1), and no list model is built.
