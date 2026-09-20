# A rule and a web address are not figures (#229, #227)

Two seeds of `LayoutReconstructor.graphicsWithLabels` were wrong, and the fixed-point whole-line
union turned each into a whole-column crop. The macOS 27 arm64 release CLI was built from
`f806309` for the "before" column and from the recorded change for the "after" column, both with
library defaults and reproducible packaging:

```sh
swift build -c release
.build/release/pdf-reflow corpus/cache/GPO-911REPORT.pdf book.epub \
  --package-identifier urn:uuid:test --modification-date 2026-01-01T00:00:00Z
```

Counts below come from the produced EPUBs: for each source-page marker (`id="page-N"`), the
whitespace-separated words of the following markup with tags and figure captions removed, and the
`<img>` elements attributed to that page. They are counts, not fidelity scores.

## The two defects

`gpo-911-2004` physical pages 161 and 526 print one underlined word each — `gain` and `risk` in
chapter 4's prose, `not` in "I do not believe a proposal of this magnitude" in note 136 — and the
book paints those underlines as rules 4 pt high after `GraphicsReader`'s padding (20.9 × 4 and
18.8 × 4 pt; 13.3 × 4 pt). Each was its page's only graphic, and the crop grew over the page.
Pages 207, 219, 230 and 527 carry the same underlines. Rendered evidence was read with Poppler
(`pdftoppm -r 300`) over the rule coordinates the layout capture reports.

The notes pages 571 and 581-583 paint nothing at all. There the seed was the displayed-formula
rule: a cited web address such as `…/print.php3?ReportID=145` holds an `=` and leaves the note
line at twelve words or fewer, so the line read as a displayed relation.

## `gpo-911-2004`, whole book

| | before | after |
| --- | --- | --- |
| reflowed words | 282,913 | 288,980 |
| images | 110 | 100 |
| pages with no reflowed text | 19 | 12 |
| EPUB bytes | 21,635,317 | 18,438,516 |

No page loses words. The pages that change (words, images):

| page | before | after | seed |
| --- | --- | --- | --- |
| 161 | 0, 1 | 227, 0 | underlines under `gain` and `risk` |
| 207 | 0, 1 | 520, 0 | two underlines |
| 219 | 49, 1 | 513, 0 | underline |
| 230 | 187, 1 | 499, 0 | underline |
| 526 | 0, 1 | 794, 0 | underline under `not` |
| 527 | 0, 1 | 849, 0 | underline |
| 571 | 0, 2 | 856, 1 | `companies_list.asp?letter=a)` |
| 581 | 0, 2 | 799, 1 | `print.php3?ReportID=145`, `item_id=1645&…` |
| 582 | 0, 2 | 946, 1 | `display?theme=45&content=3498&…` |
| 583 | 545, 2 | 845, 1 | `newsflash.asp?Mode=View&…` |

Pages 219 and 230 were not in either issue's list. The remaining image on 571 and 581-583 is the
source-page reference that accompanies the reflowed text, not a figure the page prints; the
`minimumImages: 2` contracts on 581-583 counted the runaway crop and are corrected to 1.

## The other seventeen corpus documents

No page loses words in any of them. Changed books, before → after:

| case | reflowed words | images | pages with no reflowed text |
| --- | --- | --- | --- |
| `usgs-mcs2025-copper` | 271 → 933 | 12 → 3 | 0 → 0 |
| `faa-phak-8083-25c` | 233,675 → 242,071 | 586 → 596 | 14 → 5 |
| `cia-blue-book-14-1955` | 164,393 → 173,650 | 420 → 421 | 0 → 0 |
| `wallace-algebra-2010` | 70,812 → 72,304 | 2,152 → 2,150 | 8 → 7 |
| `census-rrs2002-01` | 5,237 → 5,707 | 47 → 50 | 0 → 0 |
| `irs-p596-zhs-2025` | 3,571 → 4,269 | 139 → 140 | 7 → 7 |
| `usda-ars-agresearch-2012-11` | 4,303 → 4,386 | 71 → 71 | 7 → 7 |
| `dga-2025-2030` | 2,317 → 2,374 | 27 → 28 | 1 → 0 |
| `arxiv-replay-clocks-2023` | 7,963 → 8,018 | 70 → 70 | 0 → 0 |
| `nbs-jres-geltman-1977` | 639 → 836 | 8 → 8 | 6 → 6 |

USGS is #36's own acceptance: page 1 reflows 355 words instead of 20 and page 2 578 instead of
251, while the salient-statistics, tariff and world-production tables keep their reviewed crops.
`fed-explained-2021`, `gpo-our-flag-2003`, `cdc-zombie-pandemic-2011`, `scotus-loper-bright-2024`,
`uscis-m618-arabic-2015`, `ntrs-20180003024-earthdata-slides-2018` and
`gpo-warren-1964-suspect-text-excerpt` are unchanged in words, images and empty pages.

## Gates

`scripts/check-all.sh --fast` passes with 328 Swift tests, and all 18 `corpus/regressions.json`
cases pass (`tools/run_corpus_regressions.py`, EPUBCheck 5.x from Homebrew), run twice.

`RuleAdjacentProseTests` holds fifteen tests over seven pinned source-layout fixtures. Restoring
the old seeds and the old expansion in `graphicsWithLabels` and `statesAnEquation`, with the new
helpers left in place, fails ten of them (USGS, NBS, 9/11 pages 161, 526 and 571/581-583, and the
synthetic underline, column-rule, borderless-table and end-to-end cases). The five that pass
either way are the positive controls: Wallace's quadratic-formula page keeps its displayed
equations as crops, Wallace's practice page keeps every fraction bar with its terms, the Fed
book's ruled figures keep their crops beside an unchanged running-head rule, Our Flag's heading
rules and dot-leader table are unchanged, and a synthetic fraction bar still crops both terms.

## Limits

Counts are not fidelity. The crops these pages no longer take were reviewed only where named
above; the whole-page reading order of the recovered pages is not re-qualified here, and the
underlining the source prints is lost when the line reflows as prose — the word reflows, its rule
does not. `isWebAddress` recognizes a scheme, a `www.` host and a `?`/`&` query pair, not every
address a document might cite.
