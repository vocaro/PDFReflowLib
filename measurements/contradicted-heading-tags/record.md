# A page whose tags contradict themselves about one type size

`corpus/regressions.json` requires the Fed Explained's page 21 (printed 13) to carry the heading
"Advisory Councils". It stopped doing so when
[#67](https://github.com/vocaro/PDFReflowLib/issues/67)/[#91](https://github.com/vocaro/PDFReflowLib/issues/91)
opened the structure-tag gate and the book went from 1 page with tags applied to 67. The contract
was written on a base without that change, against the rendered source, and it is right; the
output was wrong.

## What distinguishes the line

Read straight off the source with the real readers (`GraphicsReader`, `NativeTextReader`,
`StructureTreeReader`, `MarkedTextReader`), page 21 is a ten-point page whose heading threshold is
12.5 pt. It draws four headings and tags three of them:

| line | size | tag |
| --- | ---: | --- |
| Other Significant Entities Contributing to Federal Reserve Functions | 16 pt | `H3`, two lines, one group |
| FOMC Responsibilities | 14 pt | `H4` |
| Depository Institutions | 14 pt | `H4` |
| **Advisory Councils** | **14 pt** | **`P`** |

So the distinguishing fact is not that the line is large relative to the body — two other lines of
the page are exactly as large — but that it is set in a size *this same page's own tags call a
heading*, while its own element carries the plain paragraph role. The page has not decided that
fourteen-point display type is body text; it has said both things at once. The Fed's `RoleMap`
sends `Sub_Title`, `Title` and `Table_Sub_Head` to `P`, which is the same lossy-producer root
cause as the FAA's `AC_heading_1`…`AC_heading_5` → `P`; on page 21 the element's role is the bare
`P` rather than a mapped style, but the loss is the same shape.

That is also why the FAA's 171 protected headings cannot be put at risk by reading the
contradiction: **no FAA page's tags name a heading at all**, so the rule added by #67 already
decides every one of them and the new rule is unreachable there.

## What a size-based refinement would do to every tagged page

Seven corpus documents have tagged pages (the census in
[tag-gate-scoping](../tag-gate-scoping/record.md)). A probe over every page of each, using the
real extraction pass, the real `DocumentContext` and the real `role(of:)`, listed every line whose
tag calls it a paragraph while the page's typography reads it as a heading, on a page whose tags
do name a heading somewhere:

| document | candidates | set at a size the page's tags call a heading |
| --- | ---: | ---: |
| `fed-explained-2021` | 2 | 1 |
| `gpo-our-flag-2003` | 6 | 0 |
| `faa-phak-8083-25c` | 0 | 0 |
| `scotus-loper-bright-2024` | 0 | 0 |
| `uscis-m618-arabic-2015` | 0 | 0 |
| `irs-p596-zhs-2025` | 0 | 0 |
| `dga-2025-2030` | 0 | 0 |

The six candidates with no size match are all one page: Our Flag page 3, the title-page imprint
("JOINT COMMITTEE ON PRINTING", "UNITED STATES CONGRESS", "U.S. GOVERNMENT PRINTING OFFICE",
"WASHINGTON : 2003", "108th Congress, 1st Session", "H.Doc. 108-97"), set in nine- and
twelve-point type over a seven-point body. The seventh is the Fed cover's "PUBLIC EDUCATION &
OUTREACH". None of them heads anything, and no tag on either page calls those sizes a heading.

**So plain size against the page body is not enough**: it would add seven headings the source does
not draw as such and break the reviewed control that Our Flag page 3 stays at one heading, "OUR
FLAG". Requiring the page's own tags to name a heading at that exact size leaves both pages alone
and reaches exactly one group in the corpus.

The document-wide heading ranking the #67 commit named is therefore not needed for this page. It
would be needed for the general problem — a book whose tags never state the level a display size
means — but page 21 states it, on the page, twice.

## The rule

A paragraph-tagged group is read as a heading only where all of:

- the same page's tags call a line of that exact type size (to the half point) a heading;
- every line of the group also reads as a heading by the page's own typography (`role(of:)`), so
  one line of prose refuses the whole group and no paragraph can be swallowed;
- the group holds fewer than 200 characters, the ceiling `structuredOrder` already applies to a
  tagged heading.

The level is the shallowest the page's own tags give that size — `H4` here — so the promoted
heading nests as the sibling of "Depository Institutions" rather than at the spatial path's fixed
level 2, which would have placed it above its own parent.

## What moved, per document

Whole-book conversions with the release CLI at library defaults, pinned identifier and date,
before and after, reading every page's text, headings and images out of the EPUB, with the
`structureFallback` counts from each conversion report. The 18 `corpus/regressions.json` cases.

| document | headings | words | images | `structureFallback` | pages with no reflowed text |
| --- | --- | --- | --- | --- | --- |
| `faa-phak-8083-25c` | 635 | 246,772 | 619 | 541 | 10 |
| `wallace-algebra-2010` | 174 | 70,141 | 2,151 | 0 | 7 |
| `gpo-911-2004` | 73 | 299,358 | 101 | 0 | 12 |
| `fed-explained-2021` | **189 → 190** | 29,881 | 317 | 68 | 12 |
| `dga-2025-2030` | 14 | 2,365 | 28 | 10 | 0 |
| `gpo-our-flag-2003` | 54 | 13,277 | 147 | 37 | 1 |
| `cdc-zombie-pandemic-2011` | 86 | 2,706 | 42 | 0 | 4 |
| `cia-blue-book-14-1955` | 0 | 168,660 | 421 | 1 | 0 |
| `usgs-mcs2025-copper` | 0 | 922 | 3 | 0 | 0 |
| `scotus-loper-bright-2024` | 6 | 38,307 | 0 | 128 | 0 |
| `census-rrs2002-01` | 25 | 6,417 | 37 | 0 | 0 |
| `uscis-m618-arabic-2015` | 102 | 18,947 | 213 | 100 | 9 |
| `irs-p596-zhs-2025` | 101 | 4,216 | 140 | 26 | 8 |
| `nbs-jres-geltman-1977` | 0 | 835 | 8 | 0 | 6 |
| `arxiv-replay-clocks-2023` | 3 | 8,121 | 70 | 0 | 0 |
| `ntrs-20180003024-earthdata-slides-2018` | 20 | 477 | 21 | 0 | 0 |
| `gpo-warren-1964-suspect-text-excerpt` | 0 | 957 | 5 | 0 | 3 |
| `usda-ars-agresearch-2012-11` | 10 | 4,248 | 75 | 0 | 8 |

Every page of every book was compared, not only the totals. **One page in the corpus changes**:

    fed-explained-2021 p21: words 339 -> 339, headings 3 -> 4, images 2 -> 2
        + Advisory Councils

**No page loses a word**, anywhere, and no page's image count moves. #67's gate behavior does not
move: every document's `structureFallback` count is identical, including the FAA's 541 and the
Fed's 68.

Positive controls, all from real pages and all unchanged: the FAA handbook entire (635 headings,
246,772 words — the 171 headings the #67 rule protects and the 100 it recovers are untouched,
because the new rule cannot reach a page whose tags name no heading); Our Flag's two-line title
kept as one heading and its title-page imprint still at one heading (54 headings, unchanged); the
Fed's other genuine section titles (189 of the 190 are the same blocks, and the one addition is
the missing sub-heading); IRS Publication 596 and the DGA heading-for-heading, word-for-word
unchanged.

`document-numbers.json` holds every document's before and after totals.

## Evidence

- `document-numbers.json`: per-document headings, words, images, `structureFallback`, reflowed
  pages and pages with no reflowed text, before and after.
- `Tests/PDFReflowLibTests/fixtures/fed-21-tags.json`, captured from the pinned source with
  `tools/capture_tag_fixture.py`: the page's content stream, fonts, and the structure elements its
  `ParentTree` names — `H4` for MCIDs 2 and 5, `P` for MCID 9 ("Advisory Councils").
- `Tests/PDFReflowLibTests/fixtures/fed-21-layout.json`, the page's native extraction.
- `aPageThatTagsOneOfItsOwnSubHeadingsAParagraphKeepsIt` replays both and asserts the four
  headings, their levels and that the page's word count is unchanged;
  `aDisplayLineNoTagOnThePageCallsAHeadingStaysAParagraph` pins that a display size no tag on the
  page calls a heading stays a paragraph, that a group with one prose line is refused whole, and
  that a page whose tags name no heading states no size.

## One capture-tool fix this needed

`tools/capture_tag_fixture.py` kept an integer kid of a captured element whenever that MCID
appears anywhere in the page's `ParentTree`, not only where the `ParentTree` names *that* element
as its owner. Page 21's list continues onto page 22, so its `LBody` carries the next page's MCID 0
as well as this page's MCID 15; captured, the replayed one-page document held MCID 0 twice and the
reader correctly rejected the whole tree, which no real reading of the book does. The prune now
requires `owners[mcid] == element`. Recapturing `fed-109-tags.json` with the fix reproduces the
committed fixture byte for byte, so no existing fixture is affected.
