# The line the marker is not on

Measured under [#256](https://github.com/vocaro/PDFReflowLib/issues/256), baseline `ec7e943`,
2026-09-20, macOS 27.0 (26A428) / Xcode 27.0 (27A266a), Apple M5 Max, 36 GB, release CLI at
library defaults. The two halves before this one are the [parent record](../record.md), for a
marker drawn larger than its item, and [smaller-marker](../smaller-marker/record.md), for one
drawn smaller. The last of those ends by naming what it did not fix, which is this.

## The mechanism, from the page

IRS Publication 596 sets a footnote band under each page of its EIC table. Captured from source
page 27 with `tools/probes/capture-layout-fixture.swift`, in PDF page space:

| line | x | y | width | size |
| --- | ---: | ---: | ---: | ---: |
| `★ 如果您的报税身份是已婚分别申报，…请使用此栏。` | 54.00 | 109.90 | 277.94 | 8.00 |
| `* 如果您要从工作表中查找的金额至少为 19,100 美元, 但低于 19,104 美元，…则您` | 42.00 | 97.90 | 523.06 | 8.00 |
| `如果您要从工作表中查找的金额不低于 19,104 美元，…则您不能享受抵免。` | 54.00 | 85.90 | 422.80 | 8.00 |

The page's own body is 5.69 points — its table rows carry 6,748 of its 7,201 characters — so its
heading threshold is 125% of that, 7.11, and every line of the 8-point band clears it. The first
of the two starred lines is an item, because [#254](https://github.com/vocaro/PDFReflowLib/issues/254)
reads the star as a list marker. The second is the rest of that same footnote, and it carries no
marker at all: the star is on the line above it. Nothing about its opening says it is not a
heading, so `isTitleSized` admitted it, on four pages — 27, 28, 32 and 34.

What the page does say is where the line stands. It is set at the marked line's size, its box
begins 0.16 points below that line's, and it hangs 12.00 points in from it — 1.5 of its own
sizes, which is where the star and its space leave the footnote's text.

## The rule that landed

**A line hanging under a bulleted line is the rest of that item**, and is no more a heading than
the item is. `LayoutReconstructor.hangsUnderBullet` asks the page for all of it: the line opens
with no marker of its own; the line above it opens with one of `• * − – — -` and a space; the two
are set at one size; the gap between their boxes is between −0.6 and 0.8 of that size, the
leading `continuesBrokenItem` already joins a broken item on; and the line stands between 0.8 and
3 sizes in from the marked line's left edge, the hanging-indent window `NumberedNoteDetector`
reads for the continuation of a numbered note. The marked line must also be at least twelve of
its own sizes wide, because a line that wrapped is a line that ran out of room — a short bulleted
item above an indented one is two items, not one item over two lines.

Only the heading reading goes. The line keeps its own block, its own words and its own place;
this is the relationship [#39](https://github.com/vocaro/PDFReflowLib/issues/39) and
[#238](https://github.com/vocaro/PDFReflowLib/issues/238) already read for a wrapped marked line,
read here for a line that has no marker to read, and as there it moves nothing the page printed.

The other way the issue offered — recognizing the whole band at the foot of the page as
footnotes, as `NumberedNoteDetector` does for numbered notes — was not taken. That detector earns
its group from a page that prints `NOTES TO CHAPTER n` and from a numbered sequence it can
follow; this band prints no heading and its notes are keyed by symbols, so a band detector here
would have to be built on position alone, which is the evidence a running foot and a folio also
satisfy. The hanging indent is the page's own statement about these two lines and needs nothing
inferred about the band.

## What it costs

One book moves, by four. Headings from `read_pages`, over all eighteen covered cases:

| book | before | after | book | before | after |
| --- | ---: | ---: | --- | ---: | ---: |
| arxiv-replay-clocks-2023 | 3 | 3 | irs-p596-zhs-2025 | 102 | **98** |
| cdc-zombie-pandemic-2011 | 86 | 86 | nbs-jres-geltman-1977 | 0 | 0 |
| census-rrs2002-01 | 25 | 25 | ntrs-20180003024-earthdata-slides-2018 | 20 | 20 |
| cia-blue-book-14-1955 | 0 | 0 | scotus-loper-bright-2024 | 6 | 6 |
| dga-2025-2030 | 14 | 14 | uscis-m618-arabic-2015 | 102 | 102 |
| faa-phak-8083-25c | 635 | 635 | usda-ars-agresearch-2012-11 | 29 | 29 |
| fed-explained-2021 | 189 | 189 | usgs-mcs2025-copper | 0 | 0 |
| gpo-911-2004 | 73 | 73 | wallace-algebra-2010 | 174 | 174 |
| gpo-our-flag-2003 | 54 | 54 | **corpus** | **1,512** | **1,508** |
| gpo-warren-1964-suspect-text-excerpt | 0 | 0 | | | |

The four that leave are exactly the four the issue names:

```
如果您要从工作表中查找的金额不低于 19,104 美元，并且您没有任何持有效的 SSN 的合资格子女，则您不能享受抵免。
如果您要从工作表中查找的金额不低于 26,214 美元，并且您没有任何持有效的 SSN 的合资格子女，则您不能享受抵免。
如果您要从工作表中查找的金额不低于 50,434 美元，并且您有 1 个持有效的 SSN 的合资格子女，则您不能享受抵免。
如果您要从工作表中查找的金额不低于 68,675 美元，并且您有 3 个持有效的 SSN 的合资格子女，则您不能享受抵免。
```

Every page of every covered book is identical in non-whitespace characters against the baseline:
the four lines are still in the book, as text, and nothing else moved. The corpus lane passes 18
of 18, read case by case from each evaluation's own `runPassed` rather than from the run's exit
code.

The issue, and the record that filed it, say this book has 84 headings. It had, at `ff74b33`.
`840ec23` ("Stop a crop from taking the book's own prose") then freed the two-column pages whose
prose a crop had been taking, and that book's own record measures the gain at 18 headings.
84 + 18 = 102, which is the baseline measured here.

## What this does not fix

The same band's ★ legend — `★ 如果您的报税身份是已婚分别申报，并且您有资格申报 EIC，请使用此栏。` —
reads as a heading on ten of these pages and still does. #254's marker class is enumerated and
does not hold U+2605; this rule is about the line a marker is *not* on, and the legend is the
first line of its own note with nothing hanging under it. It is filed as
[#259](https://github.com/vocaro/PDFReflowLib/issues/259).

## How it was measured

```
swift build -c release
python3 tools/run_corpus_regressions.py \
    --converter "$(swift build -c release --show-bin-path)/pdf-reflow" \
    --epubcheck "$(command -v epubcheck)" --output /tmp/corpus-256 --jobs 4
```

Heading counts come from `read_pages` in `tools/check_corpus_content.py`, over the lane's own
book for the candidate and over the same source converted by a binary built from `ec7e943` for
the baseline. The page geometry above is a capture of source page 27 that is not committed, per
[decision 0006](../../../doc/decisions/0006-measurements-are-records.md); the probe command that
produces it is the one `doc/regression-testing.md` documents.
