# Sentences split around figures at column and page breaks: recount and fix (#118)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0 (27A266a),
release CLI. The recount began on `be34d39`, was repeated unchanged on `a295f33` (#126/#127 change only FAA
pages 31, 57 and 364, none a split), and the final lane, mutations and gates ran on `277cbde` with this change
applied uncommitted. No PDF or EPUB is committed.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `277cbde` | `420e1d57…` |
| candidate | `277cbde` plus this change | `39c9bbc8…` |

Corpus: `faa-phak-8083-25c` (`247929ca…`); controls `fed-explained-2021`, `gpo-911-2004`, `dga-2025-2030`,
`wallace-algebra-2010`.

## Recount method

[`tools/recount.py`](tools/recount.py) walks the EPUB spine in reading order (headings, paragraphs, `<pre>`
items, figures, `Figure|Table N` captions, page markers) and lists every paragraph that ends without terminal
punctuation (past closing quotes, superscripts and a trailing `[Figure N]` reference) and is followed, past
figures, captions, headings and page breaks, by a paragraph. `--all` includes pairs with nothing but a page
break between. Candidates were read one by one; most uppercase hits are labels, leader rows and list items and
were set aside. A temporary trace ([`tools/trace-refusals.patch`](tools/trace-refusals.patch), reverted)
printed which guard refused each open pair on a full FAA conversion, and the blocking line
([lane/refusals-faa-before.txt](lane/refusals-faa-before.txt)); each case was then read on a `pdftoppm` render.

No heading, list, table or tag stood between any genuine pair, so those classes are empty.

## Before and after (FAA)

| Class (what blocked the join) | Before | After | Pages |
| --- | --- | --- | --- |
| A caption's wrapped 9-pt line competed as prose (same page) | 15 | 0 | 21, 25, 45, 65, 115, 136, 155, 164, 170, 193, 207, 216, 224, 344, 396 |
| The same, beside the anchor or above the head across pages | 9 | 0 | 19→20, 68→69, 154→155, 158→159, 159→160, 217→218, 223→224, 259→260, 441→442 |
| A page holding only a figure between the halves | 9 | 0 | 45→47, 60→62, 106→108, 251→253, 292→294, 326→328, 329→331, 331→333, 405→407 |
| Next line of the same column, a figure or caption beside it read between | 6 | 0 | 18, 230, 235 (two), 341, 391 |
| Continuation head lower than the foot, under the figure heading its column | 1 | 0 | 411 |
| Capital, digit or quote after a word that cannot end a sentence | 9 | 0 | 19, 109→110, 122→123, 126→127, 145→146, 251, 281, 286→287, 418→419 |
| Extraction reports the anchor line narrower than printed (not filling) | 2 | 2 | 221→222, 438→439 |
| Capital after a word that can end a sentence (proper noun split) | 1 | 1 | 24 (`The FAA` / `Safety Team (FAASTeam)`) |
| Capital inside an open parenthesis after a number | 1 | 1 | 169→170 (`(70 x 100/180 = 38.89` / `Celsius degrees)`) |
| A caption's wrapped line split into a body paragraph stands between | 2 | 2 | 341→342, 391→392 |
| **Total** | **55** | **6** | |

Of the 55, 51 have an image, caption or figure page between; 126→127, 418→419, 438→439 and 18 have only a
page break or nothing. The issue's ~90 predates e949bea, which joined 83 paragraphs and 5 list items.
Recount lists: [before](lane/recount-faa-before.txt), [after](lane/recount-faa-after.txt) (text-level
candidates, including the labels, leader rows and formula fragments set aside: 136 `can` / `.`, 208, 265, 266,
398 are displayed calculations).

## Change

`Sources/PDFReflowLib/LayoutReconstructor.swift`, `Sources/PDFReflowLib/PDFReflowLibPipeline.swift` (the
figure-page chain) and `tools/check_corpus_content.py` (`nextPage`). No public API, option, default or warning
changed; `appendPage` gains a defaulted internal parameter.

- **Wrapped caption lines** (`isProse`, both join rules). A line set smaller than the anchor (below 95% of its
  size) whose text lies inside a `Figure|Table N` caption block of its page does not compete, as the caption's
  first line already did not.
- **Figure-only pages** (`holdsOnlyFigures`, `appendPage`, `continuation`, pipeline). A reflowed page whose
  blocks are only images (at least one), captions and margin folios keeps the last body page as `previous`,
  for at most two such pages, unless it opens a chapter or a note continues; page-image fallback pages never
  qualify. The join also requires no prose line anywhere on a skipped page (#45's `isProse`, body-sized text
  inside its regions counting). On a join the skipped pages' markers precede the next page's at the text
  boundary, and their figures follow the joined paragraph with the next page's leading figures; page N's
  figures stay ahead of it as before.
- **Next line of the column** (`nextLineInColumn`, same page). The continuation's first line is the anchor's
  size, on its left edge within half a body, directly below at a pitch of at most 1.5 line heights, with no
  line between them.
- **Head beneath a column-head figure** (`continuesColumn`). The head may be lower than the foot when an image
  or box over the head (bottom no lower than half a body below the head's top), horizontally overlapping it,
  reaches above the foot's middle, and the two lines are the same size.
- **Openings** (`continuesSentence`, both rules). Besides lowercase, a capital, digit or opening quote when the
  previous text's last word is an article, preposition, conjunction, auxiliary, determiner (`the`, `of`, `and`,
  `is`, `every`, `those`…) or a possessive of at least two letters, and the first line is the anchor's size and
  fills its column or ends a sentence.
- **Section ceiling** (`continuesColumn`, #111's rule). The search above the head now stops at the top of the
  lowest gutter-crossing element rather than its bottom, setting that element itself aside, so body prose a
  crossing region swallowed still competes. Found when the caption excuse let the `faa-19` fixture (whose
  map crop takes the right column's first lines) join `…this system. The` to `standard beacon tower`. No lane
  output changed.

Guards added during the lane, each from a false join found in review: the same-size requirement for weaker
openings and for the lower head (FAA 341: `…the threshold for` / caption fragment `14 with collocated Taxiway
Alpha location sign.`), and the full-line requirement for weaker openings (9/11 302 and 306: `…response to an` /
the credit `The World Trade Center Radio Repeater System Rendering by Marco Crupi`; 9/11 246: `…presented a` /
the run-in title `Atta’s Alleged Trip to Prague`). A style guard was tried and dropped: neither title is bold or
italic in the output. The sentence-closing short line keeps FAA 127 (`87 percent, depending on how much the
propeller “slips.”`).

Designs considered and not built: joining across a split caption fragment (the defect is the fragment, a
reading-order and caption-assembly issue); accepting any capital after a noun (FAA 24 is indistinguishable from
a new sentence without vocabulary); widening `fillsColumn` for 221 and 438 (the extracted rectangles are wrong,
not the rule).

## Lane (`277cbde` → candidate)

`tools/run_corpus_regressions.py --converter <CLI> --epubcheck /opt/homebrew/bin/epubcheck
--environment-probe .build/raster-environment/probe --execution-context host-terminal --case <id>`, one case per
call ([`tools/lane.sh`](tools/lane.sh)), then `tools/compare_conversion_runs.py --allow-different-converters`
([`tools/compare.sh`](tools/compare.sh)), a per-page block diff and a join-boundary diff
([`tools/boundaries.py`](tools/boundaries.py)). Every run passed EPUBCheck, resource, progress and memory gates;
no memory-gate failure occurred. In every comparison images, navigation, page markers and report fields are
unchanged; FAA's word multiset, image count and headings are identical.

| Case | Contract | Joins gained / lost | Summaries |
| --- | --- | --- | --- |
| faa-phak-8083-25c | base fails exactly the 12 new expectations (498 checks); candidate passes | 49 / 0 | [base](lane/summary-base-faa.json), [cand](lane/summary-cand-faa.json), [compare](lane/compare-faa.json) |
| fed-explained-2021 | both pass | 5 / 0 | [compare](lane/compare-fed.json), [page diff](lane/pagediff-fed-explained-2021.txt) |
| gpo-911-2004 | both pass | 22 / 0 | [compare](lane/compare-911.json), [joins](lane/joins-gpo-911-2004.txt) |
| dga-2025-2030 | both pass | 0 / 0 (strict comparison passes) | [compare](lane/compare-dga.json) |
| wallace-algebra-2010 | both pass (180 checks) | 23 / 0 | [compare](lane/compare-wallace.json), [joins](lane/joins-wallace-algebra-2010.txt) |

**Review of every new join.**

- *FAA, 49* ([lane/joins-faa.txt](lane/joins-faa.txt), with class): each was read on a source strip with both
  anchor lines marked ([`tools/sheets.py`](tools/sheets.py), ten sheets): the anchor is the last body line of
  its column or page, the continuation the first body line of the next column or page past figures and
  captions, and the text runs on mid-sentence (`…take place in the` / `landing phase,`; `…further increasing
  the` / `AOA.`; `…health, fatigue, weather,` / `capabilities, etc.` past the full-page form on 46). Page 18's
  `P. E. Fansler…St. Petersburg,` / `approached Tom Benoist…` is correct text in a block already misread as a list
  item. The joined set was identical on `a295f33` and `277cbde`.
- *Fed, 5*: next-line joins of a `<pre>` item to its wrapped line: the `*` notes under figures 1.4 (13) and 7.1
  (117), Box 3.4's `2019.`/`2020.` paragraphs (44, with `bal-`/`ances` healed), the `•` bullet on 60 and the
  `1913.` paragraph on 92. All read on renders; 117's note already absorbed `HELOC Home equity line of credit.`
  in the baseline.
- *9/11, 22*: fifteen cross-page capitals or digits after an open word with only the page break between
  (67, 80, 99 `by` / `9/11 there were 34`, 102, 139, 142, 160, 199, 213, 241, 264 `from` / `August 13`, 347, 362,
  397 `Those` / `Conventions`, 398) and seven next-line joins of year- or number-led lines misread as items
  (146, 147 twice, 179, 206, 215, 229). 99→100 and 397→398 were read on renders; 397→398 appeared on `277cbde`
  because fbe5805 restored the space in `terrorists.Those`. The three false joins above were removed before the
  final run.
- *Wallace, 23*: twenty-two worked-example notes whose second line reading order had put after the table or
  formula crop beside them (72 `…information about` / `Adam, not Brian.`, 381 `Points B and C: x-intercepts:
  Where` / `the graph crosses…`), one paragraph split at a radical (337) and one cross-page capital (274→275
  `…is our` / `LCD will be…`). Pages 72, 337 and 381 were read on renders; the notes now precede their crops.
- *DGA*: no change.

## Tests and contracts

`Tests/PDFReflowLibTests/ColumnContinuationRecountTests.swift`, fourteen tests. Fixtures captured from the
checksum-pinned source with `tools/capture-layout-fixture.swift` as merged at `277cbde`:
`faa-{21,45}-continuation`, `faa-{46,47,68,69,230,286,287,341,411}` (lines and graphics identical to the
`be34d39` capture; runs now carry `bold`).

- Reproducers: `wrappedCaptionLineDoesNotCompeteWithAColumnJoin` (21), `wrappedCaptionLineDoesNotCompeteAcrossPages`
  (68–69), `figureBesideAParagraphDoesNotSplitIt` (230), `continuationBeneathTheFigureHeadingTheNextColumn` (411),
  `digitContinuesASentenceAfterAnOpenWord` (286–287), `paragraphContinuesPastAPageHoldingOnlyAFigure` (45–47, with
  the adjacent-pages control).
- Source negative controls: `captionFragmentDoesNotContinueASentence` (341) and
  `proseSwallowedByTheRegionOverTheHeadRefusesTheJoin` (the existing `faa-19` fixture).
- Synthetic controls: `sentenceContinuationNeedsLowercaseOrAnOpenWord`, `nextLineInColumnRequiresTheParagraphsOwnPitchAndEdge`,
  `columnHeadBelowTheFootNeedsAFigureOverIt`, `onlyCaptionTypeInACaptionIsExcusedFromCompeting`,
  `capitalOpeningAcrossPagesNeedsAFullLineInTheAnchorsType` (the 9/11 credit) and
  `figurePageWithProseIsNotSteppedOver` (prose inside the region, a body paragraph, a caption-only page, two
  figure pages with all markers inline, a third figure page).

Existing tests: `columnContinuationGuards`' uppercase control ended `…foot of the`, which now continues; it ends
`…of it all` instead and a positive capital-after-article case was added. `captionOfAColumnFigureStaysInItsColumn`
is unchanged (it failed only under the unguarded ceiling, which the ceiling fix corrected).

- Mutations ([mutants.log](mutants.log), [`tools/mutate.py`](tools/mutate.py), on `277cbde`): all 26 fail at least
  one test: the six rules switched off (the pre-change behavior for each class, the negative control) and twenty
  single guards. Five guards survived a first pass for want of isolating controls (the caption size guard,
  whose body-size caption merged with the head; the head-over guard, where a crop takes the head line, so the
  control became a tinted box; the same-page full-line guard; the crossing element's own exclusion; the inline
  markers for a second skipped page); controls were added and the whole set rerun.
- Contracts ([`tools/addcontract.py`](tools/addcontract.py), checked with [`tools/checkedits.py`](tools/checkedits.py)):
  FAA `paragraphs` on 19, 21, 230, 235, 341 and 411; `continuedParagraphs` on 68, 126, 145 and 286, and on 45 with
  `nextPage` 47; page 286's `orderedText` re-expressed with figure 12-2's caption ahead of the paragraph that now
  continues onto 287. The `277cbde` baseline fails exactly these 12 and nothing else.
- Checker: `continuedParagraphs` accepts an integer `nextPage` above N+1 when every page between exists and holds
  no text; `tools/test_corpus_content.py` adds the positive case and controls for a page between with text, a
  missing page, a split paragraph, the same output without `nextPage`, and invalid values (`2`, `1`, `0`, `'3'`,
  `True`, `3.0`).

## Verification (on `277cbde`)

- `swift build`, `swift build -c release`: clean.
- `swift test`: 638 tests pass.
- `python3 -m unittest test_corpus_content` (from `tools/`): 33 pass.
- `scripts/check-all.sh --fast`: exit 0 (638 Swift, 218 Python, fixture and policy conversions, 22
  rejection/cleanup cases, repeat-run identity).
- Corpus lane: the table above.

The tools in `tools/` were run from a scratch directory; paths inside them are those of the run.

## Remaining gaps

- FAA 221→222 and 438→439: PDFKit reports the anchor lines 214.6 of 237 pt and 225.5 of 237 pt wide (heights
  12.1 and 13.5 against 11.5), although both reach the justified edge in print, so `fillsColumn` refuses.
- FAA 24: `…education. The FAA` / `Safety Team (FAASTeam)`: `FAA` can end a sentence; no evidence short of
  vocabulary separates the proper noun from a new sentence.
- FAA 169→170: `(70 x 100/180 = 38.89` / `Celsius degrees)`: the open parenthesis is not used as evidence.
- FAA 341→342 and 391→392: split caption fragments (`on Taxiway Kilo.`, `14 with collocated Taxiway Alpha
  location sign.`, `distance, and direction.`) are body paragraphs at the column foot, so the page's last body
  paragraph is not the sentence that continues (`…the threshold for` / `Runway 36 is to the right.`; `…an hour is
  lost when` / `flying eastward…`).
- A continuation across a page-image fallback, across three or more figure pages, or into a page whose
  retained header opens it stays split.

## Defects to file

1. **A caption's wrapped line is read as a separate body paragraph.** FAA 341 (`on Taxiway Kilo.` under figure
   14-8, `14 with collocated Taxiway Alpha location sign.` under 14-9) and 391 (`distance, and direction.` under
   16-4): reading order interleaves the caption's second line with the other column, so it leaves the caption.
   Expected: each caption whole; the body joins then reach 342 and 392.
2. **Line rectangles narrower than the printed line.** FAA 221 (`compass. Errors in the magnetic compass are
   numerous,`, x 321.1–535.7 against a 558 edge) and 438 (`…the possession, sale,`, 225.5 wide). Expected:
   native line bounds reaching the justified edge (NativeTextReader).
3. **Year- and number-led lines are read as list items.** 9/11 179 `1995.`, 206 `1999.`, 215 `2001.`, 229 `1. Rice
   told us…`; Fed 92 `1913.`; FAA 18 `P. E. Fansler`. The join now keeps their text whole, but they remain `<pre>`
   items. Expected: paragraphs.
4. **Run-in titles and illustration credits reflow as body text without distinction.** 9/11 246 `Atta’s Alleged
   Trip to Prague Mohamed Atta is known…` (the title merged into its paragraph) and 302/306 credits `The World
   Trade Center … Rendering by Marco Crupi` (a paragraph, not a caption). Expected: a heading or run-in bold
   title, and a caption.
