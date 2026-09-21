# The mark the page keyed its note to

Measured under [#259](https://github.com/vocaro/PDFReflowLib/issues/259), baseline `9dfbd4b`,
2026-09-21, macOS 27.0 (26A428) / Xcode 27.0 (27A266a), Apple M5 Max, 36 GB, release CLI at
library defaults. The three halves before this one are the [parent record](../record.md), for a
marker drawn larger than its item, [smaller-marker](../smaller-marker/record.md), for one drawn
smaller, and [hanging-continuation](../hanging-continuation/record.md), for the line a marker is
not on. The last of those ends by naming what it did not fix, which is this.

## The mechanism, from the page

IRS Publication 596 sets the same legend in the footnote band under eleven pages of its EIC
table. Captured from source pages 24 through 34 with `tools/probes/capture-layout-fixture.swift`,
in PDF page space; every page prints the same three lines, at the same three x positions:

| line | x | y | width | size |
| --- | ---: | ---: | ---: | ---: |
| `★` | 115.99 | 710.45 | 6.50 | 6.50 |
| `★` | 381.99 | 710.45 | 6.50 | 6.50 |
| `★ 如果您的报税身份是已婚分别申报，…请使用此栏。` | 54.00 | 85.90 | 277.94 | 8.00 |

The two bare stars are the table's two column headers, at the head of the page; the legend
explains them, at its foot. Every one of those pages sets its table rows at 5.69 points — 5,154
of page 24's 5,656 characters, 6,748 of page 27's 7,201 — so the page's heading threshold is
125% of that, 7.11, and the 8-point legend clears it on size alone, exactly as
[hanging-continuation](../hanging-continuation/record.md) measured for the starred notes beside
it. Ten of the eleven pages were read as headings: source pages 24 through 32 and 34. Page 33's
legend was already prose at the baseline and stays prose; that page carries 605 characters at 8
points where the others carry 180, which is the only thing that distinguishes it in these
captures, and no further reading of it was taken.

**The table is a preserved region on all ten pages.** `<figure><img alt="Preserved region from
page 24"/>` stands where the rows were, so a crop has taken the two header stars and they are not
among the lines that still reflow, while the legend beneath the crop is. This is why the search
below reads everything the page printed rather than the reflowable set: what a page keyed its
note to is what the page drew, whether or not the converter kept it as text.

## The rule that landed

The obvious move is to put U+2605 in #254's bullet class. It was not taken, because the class is
an enumeration — `• * − – — -` — and one more glyph in it would say nothing about why a glyph is
a marker. The page is asked instead.

**A line is a note, not a heading, where it opens with a glyph the page keys its own material
to.** Three things the page states, together, in
`LayoutReconstructor.opensWithKeyedMark`:

- **a glyph standing alone before a measure of text.** `openingMark` reads one character that is
  no letter and no digit, then a space, then text. This is not a new marker class: it is exactly
  the shape `NativeTextReader.sizeAfterListMarker` has read since #183 when it refuses to let an
  opening glyph state the line's size. The two halves of one rule disagreed about what a marker
  is — the reader read any such glyph, the assembler read six — and that gap is the defect;
- **the same character printed by itself, higher up the page.** The reference the note explains.
  A heading that opens `§` or `★` on a page that keys nothing to that glyph is read by its size,
  as every heading is;
- **a line that filled its measure**, at least twelve of its own sizes wide — the width
  `hangsUnderBullet` already asks of a line that wrapped. A note keyed to a mark runs on; a
  decorated heading is short.

The rest of such a note, hanging under it, is read the way #256 reads the rest of a bulleted
item: `hangsUnderBullet` now takes the same marker class. No page in the corpus wraps the legend,
so that half moves nothing here; it is the same relationship, read for the same reason.

The second way the issue offered — recognizing the footnote band at the foot of the page, as
`NumberedNoteDetector` does for numbered notes — was declined for the reason
[hanging-continuation](../hanging-continuation/record.md) already gives: a band detector built on
position alone reads a running foot and a folio too. The star in the column header is the page's
own statement and needs nothing inferred about the band.

## What it costs

One book moves, by ten. Headings from `read_pages` in `tools/check_corpus_content.py`, over the
lane's own book for the candidate and over the same lane run by a binary built from `9dfbd4b` for
the baseline, all eighteen covered cases:

| book | before | after | book | before | after |
| --- | ---: | ---: | --- | ---: | ---: |
| arxiv-replay-clocks-2023 | 3 | 3 | irs-p596-zhs-2025 | 95 | **85** |
| cdc-zombie-pandemic-2011 | 86 | 86 | nbs-jres-geltman-1977 | 0 | 0 |
| census-rrs2002-01 | 25 | 25 | ntrs-20180003024-earthdata-slides-2018 | 20 | 20 |
| cia-blue-book-14-1955 | 0 | 0 | scotus-loper-bright-2024 | 6 | 6 |
| dga-2025-2030 | 14 | 14 | uscis-m618-arabic-2015 | 102 | 102 |
| faa-phak-8083-25c | 635 | 635 | usda-ars-agresearch-2012-11 | 29 | 29 |
| fed-explained-2021 | 189 | 189 | usgs-mcs2025-copper | 0 | 0 |
| gpo-911-2004 | 73 | 73 | wallace-algebra-2010 | 174 | 174 |
| gpo-our-flag-2003 | 54 | 54 | **corpus** | **1,505** | **1,495** |
| gpo-warren-1964-suspect-text-excerpt | 0 | 0 | | | |

The ten that leave are ten copies of one line, and nothing else leaves or arrives:

```
★ 如果您的报税身份是已婚分别申报，并且您有资格申报 EIC，请使用此栏。
```

Every page of every covered book is identical in non-whitespace characters against the baseline:
the legend is still in the book, as a paragraph on each of the ten pages, and nothing else moved.
The corpus lane passes 18 of 18, read case by case from each evaluation's own `runPassed` and
from each `content-assessment.json` — eighteen `passed: true`, zero errors — rather than from the
run's exit code.

[hanging-continuation](../hanging-continuation/record.md) measured this book at 102 headings on
`ec7e943`, and the corpus at 1,508. Sixteen changes landed on main between that baseline and
this one; the numbers above are both from `9dfbd4b`.

## What this does not fix

Nothing else in the corpus keys a note to a mark, so the rule is measured on one book. What it
would reach elsewhere is a page that prints `†`, `‡`, `§` or another glyph by itself and explains
it in a band — the shape the issue predicted — and what it deliberately does not reach is a
heading that merely opens with a symbol, which the tests pin with an opinion's `§ 706` heading
among its own section-sign citations, with the same IRS band stripped of its header stars, and
with a short `★ 详细示例` beneath a star the page does print.

## How it was measured

```
swift build -c release
python3 tools/run_corpus_regressions.py \
    --converter "$(swift build -c release --show-bin-path)/pdf-reflow" \
    --epubcheck "$(command -v epubcheck)" --output /tmp/corpus-259 --jobs 4
```

and the same command with a converter built from `9dfbd4b` into `/tmp/corpus-259-base`. The page
geometry above is a capture of source pages 24 to 34 that is not committed, per
[decision 0006](../../../doc/decisions/0006-measurements-are-records.md); the probe command that
produces it is the one `doc/regression-testing.md` documents.
