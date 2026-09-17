# Rejoined list markers inside tag groups (#81) and why the tag reader rejects pages (#75)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0, release CLIs.
The work started on `04efe85` and was carried onto `5bf5e59` (#63/#73) by patch, applied cleanly.
Every before/after figure on `5bf5e59` compares these binaries (SHA-256):

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `git archive 5bf5e59` | `b955b98b…` |
| candidate | this tree (#81) | `31bae01e…` |
| form proposal | this tree plus `textless-form-proposal.patch` (#75, not applied) | `806a3d6f…` |
| earlier | `04efe85` (this worktree before any change) and `git archive b9efcc9` | `3e8c8eba…`, `1a1b09b9…` |

Pinned conversions (`tools/digest.py`, `tools/compare.py`) use `--package-identifier
urn:uuid:00000000-0000-4000-8000-000000000001 --modification-date 2026-01-01T00:00:00Z`, so EPUB
bytes compare directly. `MarkedTextReader` and `StructureTreeReader` are identical at `04efe85` and
`5bf5e59`. The census below holds for both. No source PDF or EPUB is committed.

## #81: rejoined bullets made tagged FAA pages fall back

### Diagnosis

The FAA handbook tags each bullet item, marker and text, as one `P`. `tools/marker-groups.swift`
applies the tags to FAA page 29's native lines:

```
45.0 719.6  g1072 o3438 n3  •
63.0 719.6  g1072 o3438 n3  Affected Location (the identifier of the affected facility
63.0 707.1  g1072 o3439 n3  or location)
```

The marker piece and its text share one group, so `joiningMarkerPieces` (#69) joins them into
`• Affected Location…`. Two things then broke the group:

1. `structuredOrder` marks every group that holds an `isList` line as unsafe ("Caption, list or
   oversized heading tags…") and strips its tags. The rejoined line is a list line.
2. The group's `lineCount` (3) still counted the absorbed marker piece. Without the first rule, the
   run check (`counts[group] != lineCount`) would have rejected the group anyway.

Before #69 the lone `•` was not a list line, so the same group passed.

`marker-groups/*.tsv` (tags applied, then the join, per page) confirms the scope. FAA has 88
pages with an unsafe group before the join and 111 after. Every group the join makes unsafe holds
exactly one list line, which opens the group, and treating only those groups as safe returns
exactly 23 pages. Fed, Our Flag and DGA have no such group. A broader rule, "any
paragraph group that is one list item", would also change 29 FAA pages whose bullets PDFKit never
split. That rule is not part of this change (see recommendations).

### Change

`Sources/PDFReflowLib/LayoutReconstructor.swift` and `DocumentModel.swift`. No public API or default
changed.

- `joiningMarkerPieces`: when both pieces carry a structure (the join already requires one group),
  the joined line keeps the text piece's tag, with the earlier of the two orders. Every line of
  that group counts one line fewer per absorbed piece and records
  `TextStructure.opensWithSplitMarker`.
- `structuredOrder`: a paragraph group is exempt from the list rule when it holds exactly one list
  line, that line carries `opensWithSplitMarker`, and it opens the group: lowest tag order, first in
  spatial order among lines sharing that order. Captions, oversized headings, two items in one
  group, an item that does not open its group and an unsplit bullet still fall back.
- `blocks` (`flushTagged`): such a group is emitted as `.preformatted`, the list item the same
  text becomes untagged, rather than `.paragraph`.
- Docs: `doc/architecture.md` (the fallback sentence), `doc/regression-testing.md` (test count,
  already stale at 349; now 361).

### Before and after, FAA (`faa-phak-8083-25c`)

Fallback pages by message ("reader" = could not be matched unambiguously, "run" = groups intersect
barriers, "unsafe" = caption/list/oversized heading, "tree" = document-wide):

| | `b9efcc9` | `04efe85` | `5bf5e59` | candidate on `5bf5e59` |
| --- | ---: | ---: | ---: | ---: |
| Warnings | 1,450 | 1,473 | 1,473 | 1,450 |
| `structureFallback` pages | 480 | 484 | 484 | 480 |
| reader / run / tree / unsafe | 456 / 2 / 1 / 86 | 456 / 1 / 1 / 110 | 456 / 1 / 1 / 110 | 456 / 2 / 1 / 86 |

The candidate's page sets equal `b9efcc9`'s in every category. It drops the unsafe warning on pages
29, 35, 36, 38, 39, 51, 141, 148, 167, 172, 190, 191, 238, 239, 241, 273, 301, 316, 328, 399, 410,
425, 435 and 436. Page 191 returns to its `b9efcc9` "run" fallback: it was reported "unsafe" only
because the unsafe check runs first. The same comparison on `04efe85` gave identical page sets
(`page-diffs/faa-04efe85-vs-candidate-on-04efe85.txt`).

Against `5bf5e59` (`page-diffs/faa-5bf5e59-vs-candidate.txt`):

- **Every page's text is identical, and so are the word multiset, the 599 images and the 203
  navigation titles and levels.** Reading order is therefore unchanged on all 522 pages, including
  the 24. One navigation anchor id shifts (`heading-315-22` → `heading-315-21`), because page 315
  has one block fewer.
- The #69 improvements stay: the split bullets are list items, and every `runway/taxiway`-style
  slash join and page 27/191/365 contract passes.
- Blocks change on 5 pages, each reviewed against a 70–80 DPI `mutool draw` render:
  - 30: the `Weight-shift-control` bullet runs from the foot of the left column to the top of
    the right. The tag keeps it one item; before, its continuation was a paragraph.
  - 48: `What lights are available…` crosses the column in the same way and is now one item.
  - 315: TAF item `3. Synopsis…` is one item with its wrapped second sentence.
  - 316: METAR item `4. Modifier…` had fused its indented second paragraph (`When the modifier
    "COR" is used…`), and the tags now separate it. The render sets that paragraph as a separate
    indented block. #69 settled the same shape on 9/11 page 365 (an item's second paragraph
    follows it as a paragraph).
  - 372: `• Aeronautical Information Manual (AIM)—www.faa.` keeps its wrapped URL line in the item.
    The existing space join after `www.faa.` is unchanged (see defects).

Against `b9efcc9` the candidate differs exactly where #69 (list items, slash joins) and #47/#56 did.
That is 30 text pages, all slash joins, and 113 block pages (`page-diffs/faa-b9efcc9-vs-04efe85.txt.gz`
records the `04efe85` side of that comparison).

### Reproducer and controls

`Tests/PDFReflowLibTests/TaggedMarkerPieceTests.swift` builds a synthetic tagged page. It has two
bullet items whose `•` and text are separate shows in one `P`, with FAA page 29's geometry
(marker x 45, text x 63), plus a closing `P`. It uses the independent-geometry pattern of
`StructureTests`.

| Test | `5bf5e59` | candidate |
| --- | --- | --- |
| `aTaggedItemWithASplitMarkerKeepsItsGroupAsOneListItem`: no fallback, two list items, three tag groups | fails (3 issues) | passes |
| `tagOrderStillOrdersRejoinedItems`: tree order puts `Beta` before `Alpha` | fails (2) | passes |
| `theRejoinedLineSortsAtTheEarlierPieceOrder`: MCIDs 0, 2, 1 | fails (1) | passes |
| `aGroupHoldingTwoRejoinedItemsStillFallsBack` (negative control) | passes | passes |
| `aRejoinedItemThatDoesNotOpenItsGroupStillFallsBack` (negative control) | passes | passes |
| `anUnsplitBulletInsideAParagraphGroupStillFallsBack` (negative control) | passes | passes |

`negative-control-5bf5e59-tests.txt` records that run (the new tests against the `5bf5e59`
reconstructor). `mutations.txt` removes one part of the change at a time; each removal is caught:
no line-count decrement (3 tests fail), no list-item emission (2), no earlier order (1), no
opening check (1).

## #75: census of tag rejections

`tools/census-main.swift` runs, per tagged page, what `extractPage` runs: the
page-image/synthetic-style gates, `StructureTreeReader.validates`, then an instrumented copy of
`MarkedTextReader` (`tools/CensusReader.swift`, generated by `tools/gen-census-reader.py`). The
copy records the operator that first invalidated the page and each rejected group's reasons.
Tables: `census/*-before.tsv` (the shipped reader) and `census/*-proposal.tsv` (the reader with
the textless-form patch). `tools/CensusReader.swift` is the proposal reader's generated copy, with
anchor-byte sampling and the split "MCID not shown" reasons added by hand. The before tables came
from the same generator run on the shipped reader. The tools keep this session's scratch paths:
edit the paths at the top of each before rerunning. Compile a probe with `tools/build-probe.sh
<main.swift> <output>`.

### Per page, shipped reader

| Book | Tagged pages | Whole page invalid | Some groups rejected | All groups apply | Not attempted | Lines tagged |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| FAA | 510 | **328 Form XObject**, 1 unmarked unplaceable show | 127 | 49 | 5 (page image) | 11,886 / 32,153 |
| DGA | 9 | **9 Form XObject** | 0 | 0 | 0 | 0 / 380 |
| Fed | 118 | 2 Form XObject (20, 103), 1 `3 Tr` (131) | 43 | 72 | 0 | 1,891 / 3,984 |
| Our Flag | 51 | 0 | 26 | 25 | 0 | 1,000 / 1,471 |

No page fails `validates` (the ParentTree owner check), and no page is image-backed with invisible
text. **The pages #72 found with zero tagged lines (DGA 3–5 and FAA's 23 image-backed pages
16…423) are all Form XObject rejections**, and so are the other six DGA tagged pages. The page-sized
graphic is incidental. The reader's `Do` handler accepts only image XObjects, so any form
invalidates the page, whatever it draws.

What the forms draw (`tools/forms.py` walks each `Do` and its nested forms, recording mark context
and whether any text-showing operator runs; `census/*-forms*.txt`):

| Book | Pages | Forms that show no text | Forms that show text |
| --- | ---: | --- | --- |
| DGA | 9 | all 38 (19 unmarked, 19 inside `/Artifact`) | none |
| FAA | 328 | only textless forms on 297 pages (unmarked, or inside an MCID section such as `/Figure`) | 20 pages paint one unmarked (454, 456, 458 and every even page 478–510, in the back matter), 11 inside an MCID (87, 193, 214, 217, 220, 294, 343, 358, 373, 374, 447) |
| Fed | 2 | both (inside an MCID) | none |

Of FAA's 23 image-backed pages, 22 paint only textless forms; page 374 paints one that shows text.

Group-level reasons on pages the reader scans (shipped reader; FAA with the proposal in brackets,
which exposes the 297 pages):

| Reason | FAA | DGA (proposal) | Fed | Our Flag |
| --- | --- | --- | --- | --- |
| show of unplaceable origin inside the group's MCID (run-in style changes, #67's boundary) | 1,228 groups / 120 pages [1,752 / 297] | 4 / 1 | 64 / 42 | 59 / 25 |
| an MCID the tree assigns to the page that anchors no line | 1,177 / 89 [1,675 / 249] | — | 12 / 12 | — |
| … of which every show was unplaceable (same cause as the first row) | [1,607 / 239] | — | not split | — |
| … of which the marked content shows nothing placeable (figure-internal labels, e.g. FAA 221) | [68 / 11] | — | not split | — |
| origin inside no native line | 83 / 38 [160 / 73] | 24 / 8 | 2 / 2 | 1 / 1 |
| line shared with an ambiguous or unmarked show | 34 / 13 [54 / 31] | 2 / 2 | — | — |
| origin inside two lines with no single line starting there | 23 / 13 [37 / 22] | 2 / 2 | — | — |
| line shared by two groups | 2 / 1 [20 / 10] | — | — | — |

The anchors behind "origin inside no line" and "ambiguous"
(`census/*-rejected-anchors.txt.gz`, classified by `tools/samples.py`):

| Class | FAA [proposal] | DGA [proposal] | Fed | Our Flag |
| --- | --- | --- | --- | --- |
| a positioned show of only single-byte spaces past a line's end (PDFKit trims trailing spaces from line rectangles) | 145 anchors / 65 pages | 35 / 8 | 1 (page 36) | 0 |
| a text run with no line: text PDFKit places elsewhere or not at all (DGA page 7's CID sidebar runs) | 17 / 9 | 10 / 1 | 1 (44) | 3 (16) |
| a text run in two lines | 20 / 15 | 0 | 0 | 0 |
| a short show (≤ 3 bytes: superscript, note or index marker) with no line or in two lines | 27 / 10 (144, 328, 410 and back-matter pages 514–522) | 3 / 2 (`12` of `B12`) | 0 | 0 |

### Classification

1. **Form XObjects that show no text: rejection wrong, fix measured, not applied.** A form that
   runs no `Tj`/`TJ`/`'`/`"` cannot place or own a line. It accounts for all 9 DGA pages, 297 FAA
   pages and Fed 20/103. `textless-form-proposal.patch` scans each form, and every form it draws
   (depth 12, 2,000,000 counted operators per page, stream identity cache). Only a form that
   shows text still invalidates the page. With the patch applied to this tree, all 361 Swift
   tests pass. It adds no test of its own yet.
2. **Form XObjects that show text: rejection correct.** The reader does not follow a form's own
   matrix, resources or MCID namespace (FAA's 20 back-matter pages and 11 MCID pages).
3. **Run-in style changes (unplaceable origins): correct, documented boundary (#67).** The
   largest group-level class in every book. It needs glyph widths.
4. **Space-only shows past a line's end: rejection wrong, fix not implemented.** A single-byte
   space owns no visible text, so costing its group is unnecessary. A bounded fix ignores a
   positioned show whose string is only `0x20` bytes when its font is a simple (single-byte)
   font and its origin lies in no line. The reader does not track the font dictionary today.
5. **Invisible mode inside an artifact: rejection wrong, one page (Fed 131).** `3 Tr` is set inside
   an `/Artifact` that shows only spaces, and `0 Tr` resets it before tagged text. The reader rejects
   the mode when it is set rather than when invisible text is shown inside a marked section.
   Scoping it like #67's unknown origins (artifact costs nothing, MCID costs its group,
   unmarked costs the page) would apply 35 lines on that page.
6. **Superscripts and markers in two lines, text runs in no line or two lines: correct.** These are
   genuine geometric ambiguity or text PDFKit does not extract as a line.
7. **Figure-internal labels (FAA 11 pages): correct.** Their marked content shows nothing the
   reader can place (FAA 221: the labels of a `/Figure` placed PDF are drawn through a form).
8. **Tree validation, invisible render mode over scans, image-backed text: not causes here.** No
   tagged page fails `validates`. #72's image-backed path already keeps visible tags.

### The textless-form fix, measured (why it is not applied)

Superseded: the patch is applied together with the #84 heading fix and the paragraph-piece rules it
needed; see [the form and chapter-title record](../form-tags-and-chapter-titles/record.md).

Pinned conversions, candidate against candidate plus proposal (`page-diffs/`):

| Book | Tagged lines | Fallback pages | Navigation | Text / block pages changed | Images |
| --- | --- | --- | --- | --- | --- |
| DGA | 0 → 254 of 380 | 10 → 10 (reader 9; unsafe +4, +7) | 12 titles identical | 4 / 6 | identical |
| Fed | 1,891 → 1,903 | 57 → 56 (page 20) | 164 identical | EPUB byte-identical | identical |
| FAA | 11,886 → 24,351 | 480 → 469 (reader 456 → 367; unsafe 86 → 313) | **203 → 191** | 43 / 204 | identical |

DGA improves on every changed page (pages 2 and 3 reviewed against 60 DPI renders; 4, 5, 9 and 10
from the block diff). On pages 3, 9 and 10 the two-column
bullet lists were interleaved line by line (`+ Consume meat with no or limited added` / `foods as part
of a healthy dietary pattern.` / `sugars, refined…`); each bullet now reads whole. Pages 2, 4 and 5
separate fused bullets and the two signature blocks (`Secretary, U.S. Department of Health and Human
Services`, `Secretary, U.S. Department of Agriculture`).

FAA gains substantial reading-order repairs (page 89: `the viscosity of air. However…` no longer
interleaves the two columns, and the `Viscosity` section heads read in order). It also loses 12
navigation entries on chapter openers, which fails the acceptance bar:

- Pages 88, 98, 231 and 335 lose `Chapter N` and the chapter title. The source tags both as `P` in
  heading type. #67's paragraph-type rule drops such a tag only when the next text in the column is
  ordinary body, and here the next line is the `Introduction` heading, so the tags stand and the
  titles become paragraphs.
- Page 203 loses `FlightChapter 8 Instruments`, `Introduction` and `Pitot-Static Flight
  Instruments`: `Introduction` fuses into its paragraph and the title trails the page.
- Page 473 loses the appendix heading `C-1`.
- Page 96 reorders `A Third Dimension` before `Chapter Summary`.

These are the chapter-opener headings #73 just placed. Fixing them is heading territory, so the
patch is left for the coordinator (see recommendations).

## Verification

- `swift test`: 361 tests pass (355 at `5bf5e59` plus 6).
- `scripts/check-all.sh --fast`: exit 0 (361 Swift, 186 Python, 6 fixture conversions, 13 policy
  conversions with 22 rejection/cleanup cases, 8/8 concurrency processes).
- Corpus lane, `tools/run_corpus_regressions.py --converter <CLI> --epubcheck /opt/homebrew/bin/epubcheck
  --execution-context host-terminal --case <id>`, one case per call, candidate and `5bf5e59`
  (`lane-summaries/`). Every run passes EPUBCheck, the structural, progress and memory gates and
  every content check:

  | Case | Checks | Peak RSS MiB (base / cand.) | Warnings (base / cand.) | `structureFallback` pages |
  | --- | ---: | --- | --- | --- |
  | faa-phak-8083-25c | 118 | 804 / 805 | 1,473 / 1,450 | 484 / 480 |
  | dga-2025-2030 | 14 | 104 / 101 | 33 / 33 | 10 / 10 |
  | fed-explained-2021 | 127 | 280 / 299 | 528 / 528 | 57 / 57 |
  | gpo-our-flag-2003 | 67 | 93 / 93 | 103 / 103 | 33 / 33 |
  | arxiv-replay-clocks-2023 | 55 | 164 / 166 | 48 / 48 | 0 / 0 |

  The Fed candidate lane run took 32.3 s against 6.5 s under a host load average near 6 from other
  agents' runs. The pinned Fed conversions of both binaries took 6 s and 7 s.
- Controls, pinned conversions against `5bf5e59`, EPUBs **byte-identical**: DGA `dc29e65f…`, Fed
  `5e2fcfe6…` (navigation 164, 57 fallback pages), Our Flag `4f8bb64b…`, Replay Clocks `28548a43…`,
  9/11 `c9012158…`, Wallace `14f3b769…`. NOAA fixtures run in `swift test` and `check-all`.
- CoreGraphics logged one unverbose "PDF has logged an error" line during census runs of both
  readers on FAA, and of the proposal reader on DGA. `CG_PDF_VERBOSE` showed only document
  teardown messages. It was not diagnosed, and every conversion exited 0.

## Recommendations

1. **Textless forms (DGA's whole problem, most FAA rejections).** Apply
   `textless-form-proposal.patch` together with a fix for P-tagged chapter-opener titles, owned by
   the heading work (#73): a run of `P` groups in heading typography followed by a heading-type line
   that itself introduces body (FAA 88, 98, 203, 231, 335; appendix 473). Gate on FAA navigation 203
   and the DGA/FAA page diffs above. Expect FAA's unsafe fallback to rise from 86 to 313 pages: those
   pages' tags now apply, and their lists and captions reach the #43 rule.
2. **Space-only shows.** Track the current font's subtype in `MarkedTextReader` and let a
   positioned single-byte space show with no line cost nothing. Measure on FAA (65 pages), DGA (8)
   and Fed 36.
3. **Invisible render mode.** Apply the mode when text is shown, scoped by mark (Fed 131).
4. **One-item paragraph groups generally.** Extending #81's exception to unsplit bullets (a `P` group
   whose only list line opens it) would stop 29 more FAA pages falling back. Emitting those groups as
   list items needs its own page review.
5. Leave run-in style changes, text-bearing forms, genuine ambiguity and figure labels as fallbacks.

## Defects to file

1. **URL wrapped after a period joins with a space.** FAA page 372: `• Aeronautical Information
   Manual (AIM)—www.faa.` / `gov/air_traffic/publications/atpubs/aim/` reads `www.faa. gov/…`.
   Expected `www.faa.gov/…`. This predates the change: `5bf5e59` has the same text. It is a sibling
   of #69 record defect 1 (underscore).
2. **P-tagged chapter-opener titles become paragraphs when their tags apply.** FAA pages 88, 98, 203,
   231, 335 and 473 with the textless-form patch: `Chapter 4` / `Principles of Flight` are emitted
   as paragraphs, and on page 203 `Introduction` fuses into its paragraph. Expected: headings, as
   untagged. This is latent today, because those pages' tags are rejected. It blocks recommendation 1.
