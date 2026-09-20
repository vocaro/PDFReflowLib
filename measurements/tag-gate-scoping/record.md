# Scoping the tag gate to what each show can describe

`MarkedTextReader` validates a page's structure tags against what its content stream actually
shows and, before this change, refused the page's whole tag set whenever it could not account for
one show. Two of those refusals fire on ordinary, valid documents:
[#67](https://github.com/vocaro/PDFReflowLib/issues/67), an `/Artifact` running head whose last
show carries no positioning operator, and
[#91](https://github.com/vocaro/PDFReflowLib/issues/91), space-only shows past the end of a line
PDFKit trims and invisible render mode inside an `/Artifact`.

## The census first

Every corpus document was read for a usable structure tree before anything changed. Four of the
books that grep finds a `StructTreeRoot` in — the 9/11 report, Wallace's algebra, the Warren
Commission report and Blue Book 14 — yield no tagged page at all, so seven documents carry the
whole question: 934 pages with at least one supported tag group, holding 12,100 groups.

The harness ran the real readers page by page (`GraphicsReader`, `NativeTextReader`,
`StructureTreeReader.validates`, `MarkedTextReader`) and recorded each page's verdict and the
reason for it. `census-before.tsv` and `census-after.tsv` hold one row per tagged page:
document, page, verdict, groups, rejected groups, reasons.

| verdict | before | after |
| --- | ---: | ---: |
| every group applied | 78 | 157 |
| some groups applied, some fell back | 16 | 413 |
| whole tag set refused before any group was examined | 835 | 359 |
| page never reached the tag phase (page image) | 5 | 5 |
| **tag groups rejected, of 12,100** | **10,785** | **7,145** |

Per document (tagged pages; applied / partial / refused, then groups rejected):

| document | tagged pages | before | after | groups rejected |
| --- | ---: | --- | --- | --- |
| `faa-phak-8083-25c` | 515 | 48 / 6 / 451 | 57 / 119 / 329 | 8,437 → 5,738 |
| `fed-explained-2021` | 118 | 1 / 0 / 117 | 67 / 49 / 2 | 608 → 84 |
| `scotus-loper-bright-2024` | 114 | 0 / 0 / 114 | 0 / 114 / 0 | 534 → 338 |
| `uscis-m618-arabic-2015` | 107 | 8 / 2 / 97 | 8 / 98 / 1 | 446 → 411 |
| `gpo-our-flag-2003` | 51 | 21 / 1 / 29 | 25 / 26 / 0 | 247 → 61 |
| `irs-p596-zhs-2025` | 25 | 0 / 7 / 18 | 0 / 7 / 18 | 384 → 384 |
| `dga-2025-2030` | 9 | 0 / 0 / 9 | 0 / 0 / 9 | 129 → 129 |

The Fed Explained is what #67 describes: one page of 118 applied its tags, and the running head
refused the other 117. The census also shows the two causes are not the whole problem. 476 of the
835 page-wide refusals are #67's and #91's; the remaining 359 are not, and 358 of those are one
further cause the two issues never name — the page draws an XObject whose subtype is not `Image`,
which the reader refuses because a Form could draw text it never sees
([#241](https://github.com/vocaro/PDFReflowLib/issues/241), which records that none of the twelve
FAA forms sampled shows any text at all);
the last of the 359, FAA page 365, shows text from an unknown origin outside any marked content,
which is the rule working as intended.

Which relaxation each of the 476 needed (a page can need more than one):

| rule | pages | by document |
| --- | ---: | --- |
| unplaceable show inside a marked section costs only its MCID (#67) | 459 | FAA 118, Fed 102, Loper 114, M-618 96, Our Flag 29 |
| space-only show costs nothing (#91) | 311 | Fed 113, FAA 102, M-618 94, Loper 2 |
| invisible render mode inside an artifact costs nothing (#91) | 115 | Loper 114, Fed 1 |
| unplaceable show inside an artifact costs nothing (#67) | 24 | Fed 20, FAA 4 |

## What is still rejected

A show this reader cannot place still costs everything it could have described, and no more:
nothing inside an `/Artifact`, which carries no structure; the enclosing MCID's group inside a
marked section; and the whole page outside marked content, where the text could belong to any
line. Invisible text outside an artifact still refuses the page, clipping render modes still
refuse it, and duplicate or missing MCIDs, ambiguous geometry, unbalanced marked content, Form
XObjects and a line collecting anchors from two groups all reject exactly what they did before.
A show is called blank only on the font's own evidence: a one-byte `bfchar` entry for exactly
U+0020, or code 32 under a named standard encoding with no map at all.

## What moved, per document

Whole-book conversions with the release CLI at library defaults, before and after, reading every
page's text out of the EPUB. Reflowed words, images and pages with no reflowed text are the
regression numbers; headings are the navigation numbers.

| document | words | headings | pages with no reflowed text | images | reflowed pages | `structureFallback` |
| --- | --- | --- | --- | --- | --- | --- |
| `fed-explained-2021` | 29,884 → 29,881 | 153 → 189 | 12 → 12 | 315 → 315 | 123 → 123 | 118 → 68 |
| `faa-phak-8083-25c` | 240,582 → 240,582 | 522 → 622 | 5 → 5 | 596 → 596 | 517 → 517 | 482 → 537 |
| `gpo-our-flag-2003` | 13,276 → 13,276 | 51 → 54 | 1 → 1 | 147 → 147 | 55 → 55 | 37 → 37 |
| `scotus-loper-bright-2024` | 38,326 → 38,325 | 5 → 6 | 0 → 0 | 0 → 0 | 114 → 114 | 115 → 128 |
| `uscis-m618-arabic-2015` | 18,947 → 18,947 | 102 → 102 | 9 → 9 | 213 → 213 | 107 → 107 | 100 → 100 |
| `irs-p596-zhs-2025` | 4,268 → 4,268 | 101 → 101 | 7 → 7 | 140 → 140 | 29 → 29 | 26 → 26 |
| `dga-2025-2030` | 2,365 → 2,365 | 14 → 14 | 0 → 0 | 28 → 28 | 10 → 10 | 10 → 10 |

No page loses words. Three counts fall: Fed pages 60 and 84 and Loper page 5, and each is a
hyphenated line break that now joins — `macro-prudential` → `macroprudential`, `li-quidity` →
`liquidity`, `mini-mum` → `minimum`, `in-tend` → `intend`. Two tokens became one word; no
character of the source was dropped. Every other page's word count is unchanged, and the image
counts and the pages that reflow no text are identical everywhere.

`structureFallback` rises on FAA and Loper although far more tags now apply, because the warning
counts pages, not groups: a page that used to be refused once at the reader now reports the same
one warning for the groups that still fall back, and the layout stage adds its own warning when a
group crosses a barrier. Fed's count falls from 118 to 68, which is the shape #67 predicted.

## Headings: what the tags cost, and the rule that stops it

Applying FAA's tags with nothing else changed **removed 171 headings on 74 pages and added none**.
The cause is in the tag consumer, not the gate: the handbook's `RoleMap` sends every
`AC_heading_1`…`AC_heading_5` style to `P`, and main believes a paragraph role over visible
typography, so every heading the page draws became a paragraph as soon as its tags applied. The
Fed's `RoleMap` does the same for `Sub_Title`, `Title` and `Table_Sub_Head`.

A page whose tags never name a heading has not said that its display lines are not headings; it
has said only what they contain and in what order. Where no tag on the page names a heading, a
line the page's own typography reads as a heading now keeps that reading and is left to the
spatial rules; where the page's tags do name a heading, every role they give is believed over
typography, exactly as before. With that rule the FAA loses no heading and gains 100 on 34 pages
that main had already demoted — physical page 81's "Advantages of Composites" and "Disadvantages
of Composites", page 59's six DECIDE-model steps — and the corpus gains no heading anywhere that
the source does not draw as one.

Reviewed against the rendered source:

- Fed page 21 (printed 13) draws four headings. Main produced five, splitting "Other Significant
  Entities Contributing to Federal Reserve Functions" across two. The tags join it, so the page
  now reports three: correct except for "Advisory Councils", a sub-heading the Fed tags call a
  paragraph on a page whose tags do name a heading elsewhere, so the rule above does not reach it.
  Eleven more Fed pages lose one heading each, and every one of those is the same join of a
  two-line heading the source sets as one: pages 12, 25, 26, 59, 61, 67, 85, 90, 92, 118 and 124,
  each read out of both conversions and against the render, "Overview of Key Federal Reserve
  Payment / System Functions" becoming one heading and so on.
- Fed gains 49 headings on 35 pages, all from `H` roles the source states: page 30's "Anticipated
  Factors" and "Demand Shocks", page 56's two, and so on.
- Our Flag gains three: the Flag Code's "§174. Time and occasions for display", "§175. Position
  and manner of display" and "§176. Respect for the Flag". Page 3's title-page imprint is
  unchanged at one heading, "OUR FLAG".
- The Arabic USCIS guide, IRS Publication 596 and the DGA are heading-for-heading unchanged.

The remaining loss is one heading, on one reviewed page, against 35 Fed pages and 34 FAA pages
that gain. Believing a paragraph role on a page that also names headings is the branch's
"a tagged level gives way to an untagged heading larger than every heading tagged at that level",
which needs a document-wide heading ranking this tree has no equivalent of; it is not ported here.

## One more consumer rule the census exposed

The FAA corpus contract requires the two-column paragraph at the foot of physical page 116 to
continue as one paragraph onto page 117 (#27). It stopped doing so as soon as page 117's tags
applied: main joins two pages' paragraphs only when their `structureGroup` values are equal, and
page 116 is one of the pages still refused outright, so it carries none while page 117 now carries
one. Two validated paragraph identities that differ are two paragraphs and must never join; one
identity against none is not that — a page whose tags were not applied states nothing about where
its last paragraph ends — so the geometric rule decides there, exactly as it did when neither page
carried a tag. With that, the FAA contract passes again and the synthetic control that two
different identities never join is unchanged.

## Evidence

- `census-before.tsv`, `census-after.tsv`: one row per tagged page, both states.
- `document-numbers.json`: the per-page word, heading and image counts behind the table above.
- Source-derived tests over the real pages: `fed-109` (artifact running head and space-only
  shows), `faa-81` (a space-only show past a line's end, and the heading rule), `faa-91` (an
  unplaceable show costing only its own group), `loper-1` (invisible text inside an artifact) and
  `faa-365` (unmarked text from an unknown origin, still refusing the page), each captured from
  the pinned source with `tools/capture_tag_fixture.py` and replayed by `SourceTagFixture`.
