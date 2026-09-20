# Charging a Form XObject what it draws, not what it might draw

`MarkedTextReader` refused a page's whole tag set whenever the page drew an XObject whose
`Subtype` was not `Image`, because a Form XObject can show text the reader never sees and so can
place a tagged line it cannot account for. The risk is real; refusing on the mere presence of a
form is the crudest possible reading of it.
[#241](https://github.com/vocaro/PDFReflowLib/issues/241) put a number on the cost: after
[#67](https://github.com/vocaro/PDFReflowLib/issues/67) and
[#91](https://github.com/vocaro/PDFReflowLib/issues/91) opened the gate
([tag-gate-scoping](../tag-gate-scoping/record.md)), this was by a wide margin the largest
remaining cause of a page-wide refusal, and the twelve FAA forms the issue sampled showed no
text at all.

## The rule

A `Do` is now followed into the form, with the same visitor, the same budget and the same
operator table, under the form's own `Matrix` and resources and inside the implicit `q`/`Q` the
operator carries. The page is charged what the form actually shows.

A form's marked content is numbered in the form's own namespace, which the structure tree can
reach only through an `/MCR` with a `/Stm` — and `StructureTreeReader` rejects every group that
holds one, before this reader runs. So **no tag that arrives here describes anything a form
draws.** A form's text is therefore page text that no group accounts for, and it costs exactly
what the page's own unmarked text costs:

- a form that shows nothing places no line and costs nothing, which is what a page's figure
  artwork is;
- inside a form an MCID identifies nothing, and only `/Artifact` still says the content is
  furniture — inherited from the `Do` if the page drew the form inside one;
- a show the form places costs the group of any line its origin falls in, the same rule that
  rejects a line collecting anchors from two groups;
- a show the form cannot place, outside an `/Artifact`, still refuses the whole page, because it
  could have drawn on any line.

## What is still refused

The page's whole tag set still falls back when the form cannot be followed at all:

- a `Do` inside a text object, which is not a placement this reader can follow;
- a `Matrix` that is not six finite numbers, or an XObject that is neither `Image` nor `Form`, or
  that names no subtype at all;
- nesting past twelve forms, the depth `GraphicsReader` already follows; the reader stops reading
  rather than trust tags it has stopped checking;
- a stream the scanner cannot read, or one that spends the page's 100,000-operation budget, which
  is shared with the page's own stream;
- a form whose own `q`/`Q` or `BT`/`ET` do not balance — a form that ends inside a text object has
  shown text from a state this reader cannot account for;
- a form that would close marked content its caller opened, or leave a section of its own open:
  marked content begins and ends in one content stream, and a form that closed the page's section
  and opened one of its own in its place would balance the stack while silently rewriting which
  content the page's own tags own.

## The census

The same harness as [tag-gate-scoping](../tag-gate-scoping/record.md): the real readers
(`GraphicsReader`, `NativeTextReader`, `StructureTreeReader.validates`, `MarkedTextReader`) run
page by page over the seven corpus documents that carry a usable structure tree, macOS 27 arm64,
library defaults. `census-before.tsv` and `census-after.tsv` hold one row per tagged page:
document, page, verdict, tag groups, groups rejected, facts. A group counts as rejected when no
line carries it; on a page-wide refusal that is every group on the page.

| verdict | before | after |
| --- | ---: | ---: |
| every group applied | 157 | 270 |
| some groups applied, some fell back | 413 | 660 |
| whole tag set refused before any group was examined | 363 | 3 |
| page never reached the tag phase (unsupported graphics) | 1 | 1 |
| **tag groups rejected, of 12,100** | **7,169** | **3,420** |

| document | tagged pages | before | after | groups rejected |
| --- | ---: | --- | --- | --- |
| `faa-phak-8083-25c` | 510 | 57 / 119 / 334 | 162 / 344 / 4 | 5,762 to 2,194, of 9,588 |
| `fed-explained-2021` | 118 | 67 / 49 / 2 | 68 / 50 / 0 | 84 to 78, of 611 |
| `scotus-loper-bright-2024` | 114 | 0 / 114 / 0 | 0 / 114 / 0 | 338 to 338, of 534 |
| `uscis-m618-arabic-2015` | 107 | 8 / 98 / 1 | 8 / 99 / 0 | 411 to 411, of 462 |
| `gpo-our-flag-2003` | 51 | 25 / 26 / 0 | 25 / 26 / 0 | 61 to 61, of 378 |
| `irs-p596-zhs-2025` | 25 | 0 / 7 / 18 | 2 / 23 / 0 | 384 to 330, of 398 |
| `dga-2025-2030` | 9 | 0 / 0 / 9 | 5 / 4 / 0 | 129 to 8, of 129 |
| **total** | **934** | **157 / 413 / 364** | **270 / 660 / 4** | **7,169 to 3,420** |

362 of the 363 page-wide refusals drew a form (the last, FAA page 365, shows text from an unknown
origin outside marked content, which is the rule working as intended). **360 of those 362 now
apply their tags.** The two that do not, FAA physical pages 367 and 371, refuse for that same
unmarked-unplaced-show rule, which the old code never reached because the first `Do` had already
refused the page: with the form charged honestly, both stop at an unmarked show whose origin this
reader cannot derive, exactly as page 365 does. FAA page 448 is the one page that never reaches
the tag phase, for unsupported graphics, before and after.

This census classifies at the reader; the earlier one also set aside four FAA pages (226, 286,
288 and 302) that the converted book leaves as page images, which is why its refused count reads
359 + 5 rather than 363 + 1. The applied and partly-applied counts are the same in both.

Across the corpus the reader now follows 8,856 form invocations and reads 311 shows inside them.
363 tagged pages draw at least one form; on 46 of them a form holds a text-show operator.

## Does charging the form's text ever bite?

`census-form-text-ignored.tsv` is the same census with one rule negated: forms are read, but what
they show is thrown away. One page in the corpus changes, and it changes for the better reading
of the evidence.

**FAA physical page 87** draws 96 forms; two of them, `Fm71` and `Fm77`, draw the tick labels of a
density-altitude chart ("4,400", "4,300", … "3,900") as real `Tj` shows. The page carries two tag
groups, the captions of Figures 3-21 and 3-22. One of those chart labels is drawn at (154.6,
126.9), inside the PDFKit line box of the Figure 3-22 caption (x 37–293, y 116–127), so that line
collects text the page's tags do not describe and its group is withheld; the Figure 3-21 caption
applies. Ignoring the form's text applies both. That is the whole difference the rule makes on
934 pages: one group of 12,100.

**No corpus page is refused outright because a form shows text this reader cannot place.** That
case is covered by a synthetic control instead (`anUnplaceableShowInsideAFormStillRefusesThePage`),
and the claim it rests on is that a form's continuation show is the same evidence as a page's, not
that the corpus contains one.

## What moved, per document

Whole-book conversions with the release CLI at library defaults, before and after, reading every
page's text out of the EPUB. All eighteen corpus books, not only the seven that carry tags.
`document-numbers.json` holds the per-page counts.

| document | words | headings | images | `structureFallback` |
| --- | --- | --- | --- | --- |
| `gpo-911-2004` | 299,358 → 299,358 | 73 → 73 | 101 → 101 | 0 → 0 |
| `faa-phak-8083-25c` | 246,772 → 246,771 | 635 → 635 | 619 → 619 | 541 → 691 |
| `cia-blue-book-14-1955` | 168,660 → 168,660 | 0 → 0 | 421 → 421 | 1 → 1 |
| `wallace-algebra-2010` | 70,141 → 70,141 | 174 → 174 | 2,151 → 2,151 | 0 → 0 |
| `scotus-loper-bright-2024` | 38,307 → 38,307 | 6 → 6 | 0 → 0 | 128 → 128 |
| `fed-explained-2021` | 29,881 → 29,881 | 189 → 188 | 317 → 317 | 68 → 67 |
| `uscis-m618-arabic-2015` | 18,947 → 18,947 | 102 → 102 | 213 → 213 | 100 → 100 |
| `gpo-our-flag-2003` | 13,277 → 13,277 | 54 → 54 | 147 → 147 | 37 → 37 |
| `arxiv-replay-clocks-2023` | 8,121 → 8,121 | 3 → 3 | 70 → 70 | 0 → 0 |
| `census-rrs2002-01` | 6,417 → 6,417 | 25 → 25 | 37 → 37 | 0 → 0 |
| `usda-ars-agresearch-2012-11` | 4,248 → 4,248 | 10 → 10 | 75 → 75 | 0 → 0 |
| `irs-p596-zhs-2025` | 4,216 → 4,216 | 101 → 99 | 140 → 140 | 26 → 24 |
| `cdc-zombie-pandemic-2011` | 2,706 → 2,706 | 86 → 86 | 42 → 42 | 0 → 0 |
| `dga-2025-2030` | 2,365 → 2,364 | 14 → 14 | 28 → 28 | 10 → 7 |
| `gpo-warren-1964-suspect-text-excerpt` | 957 → 957 | 0 → 0 | 5 → 5 | 0 → 0 |
| `usgs-mcs2025-copper` | 922 → 922 | 0 → 0 | 3 → 3 | 0 → 0 |
| `nbs-jres-geltman-1977` | 835 → 835 | 0 → 0 | 8 → 8 | 0 → 0 |
| `ntrs-20180003024-earthdata-slides-2018` | 477 → 477 | 20 → 20 | 21 → 21 | 0 → 0 |

`pageCount`, `reflowedPageCount`, `recognizedPageCount` and `imageCount` are identical for every
document, and no page's image count moves. The eleven books that carry no usable structure tree
are identical in every number, page by page, including their warnings.

**No page loses words.** Twenty-two pages, all in the seven tagged books, change their text at
all. Two word counts fall by one, and both are a hyphenated line break that now joins: DGA page 9
`nutrient- dense` → `nutrient-dense`, FAA page 37 `task- specific` → `task-specific`. Comparing
the two conversions character by character, ignoring whitespace, no page loses a single
character.

The other twenty changes are reading order, and the ones reviewed are plainly right. FAA page 100
read "Before proceeding further with the topic of lift and how it Straight-and-level flight in the
slow-speed regime provides can be controlled, velocity must be discussed." — two columns
interleaved line by line — and now reads each paragraph whole. FAA pages 37, 109 and 361 are the
same repair, and so are DGA pages 2, 8 and 10; DGA page 2's masthead reads "Secretary, U.S.
Department of Health and Human Services" where it read "Secretary, Health and U.S. Department of
Human Services".

Headings move on two pages. Fed page 20 joins "The Federal Open Market Committee:" and "Selection
and Function" into the one heading the source sets, which is the same repair the #67 record
reviewed on eleven other Fed pages. IRS Publication 596's cover page loses two: "596 号刊物"
(Publication 596), a masthead label above the title rather than a heading, and "目录" (Contents),
which heads the contents column and is a genuine loss. Both are the consumer limitation #67
recorded and did not fix: the page's tags name a heading elsewhere, so every paragraph role they
give is believed over the page's own typography, and catching this needs the document-wide
heading ranking this tree has no equivalent of.

`structureFallback` rises on the FAA handbook, from 541 to 691, although 105 more of its pages now
apply every group. The warning counts pages, not groups: a page that used to be refused once at
the reader now reports the same one warning for whatever still falls back, and the layout stage
adds its own warning when a surviving group crosses a barrier. Fed, IRS and DGA all fall.

### The two books #67 pinned as unchanged

The #67 work used IRS Publication 596 and the DGA as controls that must not move, and they did
not move there. They move here, and they are the point: #241's own census names them as the
documents this cause refuses wholesale — DGA 9 of 9 tagged pages, IRS 18 of 25. Both now apply
their tags (DGA 5 pages fully and 4 partly, 129 rejected groups down to 8; IRS 2 and 23, 384 down
to 330). DGA loses one word to a hyphen join and gains the masthead repair above; IRS's words and
images are identical and it loses the two cover headings described above. Nothing about them was
pinned as unchanged by a test; what #67 recorded is that #67 did not move them.

## Tests

Source-derived, captured from the pinned FAA handbook with `tools/capture_tag_fixture.py`, which
now captures each Form XObject's own content stream, `BBox`, `Matrix`, fonts and nested XObjects,
and the `/MCID` of each `/Properties` entry a `BDC` can name. `SourceTagFixture` replays them, so
the tests read the source's own form bytes rather than a stand-in for them:

- `faa-16`: two forms, one nesting a third and selecting a font, and not one show between them.
  Physical page 16's prose is entirely in its own stream; four of its six groups now apply, where
  the page was refused at the first `Do`.
- `faa-373`: `Fm2` shows "Not to be used for navigation" across a chart, rotated. The reader reads
  it, gives it no identifier, and its origin falls in none of PDFKit's lines, so the page's one
  group applies.

Synthetic controls cover the rest of the rule: a text-free form costs nothing; a form's placed
show rejects the line it lands in and no other; an unplaceable show inside a form refuses the page,
and costs nothing inside an `/Artifact`; a form may not close its caller's marked content, leave
its own open, or swap one for the other; nesting is followed to twelve and refused at thirteen; an
XObject that is neither image nor form still refuses. `ContentStreamWalkTests` pins the driver's
half: a form's `Matrix` composes with the caller's transform and does not survive the return, a
form must balance its own state and text objects, the depth is capped, and the form's operators
are charged to the page's budget.

Every rule was negated in turn and the tests that fail are the tests that name it:

| negation | tests that fail |
| --- | --- |
| a form's text is ignored | `formTextRejectsTheLineItLandsInAndNoOther`, `anUnplaceableShowInsideAFormStillRefusesThePage`, `aFormDrawnInsideAnArtifactCostsNothing`, `aFormsWatermarkIsReadAndDescribesNothing` |
| a form's MCID names a page group | `formMCIDsCannotMasqueradeAsPageMCIDs` |
| a form may close its caller's marked content | `aFormMayNotCloseMarkedContentItsCallerOpened` |
| nesting is unbounded | `formNestingPastTheDepthCapRefusesThePage` |
| any XObject subtype is accepted | `anXObjectThatIsNeitherImageNorFormStillRefusesThePage` |
| the caller's transform is not restored | `aFormsOwnMatrixComposesWithTheCallerAndIsRestored` |
| a form need not balance its own state | `aFormMustBalanceItsOwnStateAndTextObjects` |

## Evidence

- `census-before.tsv`, `census-after.tsv`: one row per tagged page, both states.
- `census-form-text-ignored.tsv`: the same census with the form's text thrown away, which is what
  the FAA page 87 comparison rests on.
- `document-numbers.json`: the per-page word, heading and image counts behind the table above,
  for all eighteen corpus books.
