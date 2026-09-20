# Marker-leading wrapped lines kept in their paragraphs (#39, #238)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI.
Baseline: repository `aeca662` ("Cite the ported spacing issues as history"), the tree this
change is measured against. `corpus-pre-blocks.json` holds the per-case numbers quoted below.

## What was wrong

`LayoutReconstructor.isList` matched `^(?:[•*−-]|[0-9]+[.)]|[A-Za-z][.)])\s` on each line by
itself, with no geometry, and `BlockAssembler` flushed every match into a standalone
`.preformatted` block. A *wrapped* body line that happens to begin with an initial (`W. Bush`,
`U. S. 967`, `F. 4th`), a citation abbreviation (`v. Moore`, `p. 785`) or a number carried over
from the line above (`on January` / `13.`, `since` / `2016.`) was therefore cut out of the
paragraph it belongs to, mid-sentence, and the hyphenated word it ended on was broken across the
two blocks.

#39 measured this on the Loper Bright slip opinion. #238 re-measured it after the missing-space
reader landed: restoring the word spaces the 9/11 report's source draws turned `W.Bush` into
`W. Bush`, so a second book began exhibiting it.

## What changed

`LineRole` gains `markedLine(MarkerColumn)`: a line opening with a number or a single letter and
a point is no longer the same role as a bullet. `LayoutReconstructor.role` measures the page's
half of the evidence, which only the page can supply — whether the line stands on the majority
left edge of its column of same-size lines, and the right edge at least three of them reach — and
the role carries it to the assembler, which supplies the rest from the line before it.
`BlockAssembler.continuesWrapped` joins the line into the open paragraph when, on top of the
ordinary column-and-leading test every prose line passes:

- the marker is no more than half a body right of the previous line's text start (an indented
  marker hangs a new item; an outdent under an indented opening line is an ordinary wrap);
- the line is on the column's majority left edge and the column is justified — three lines within
  a quarter body of its right edge, the previous line among them;
- the previous line does not end in `.`, `!`, `?`, `:` or `;` after closing quotes and brackets;
- the previous line reads as prose: three or more runs of two or more letters.

Bullets, asterisks, minus signs and hyphens keep the plain `listItem` reading and never join.
`isList` itself, the numbered-note detector, tag-group validation, code handling, the public API
and every default are unchanged. No list model is introduced: a line that opens an item is still
its own `<pre>` block, which is what #219 scopes.

## Source evidence

Five checksum-pinned extraction fixtures, captured with `tools/probes/capture-layout-fixture.swift`
from the cached corpus sources and read against the printed pages, never from converter output:

- `911-117` (9/11 report, folio 99): `…for President George` / `W. Bush, National Security Policy
  Directives. These documents and many oth-`, the page #238 quotes. 10.25 pt column at x 44.70,
  312 pt measure, no vertical gap.
- `loper-60`: `…Brand X Internet Services, 545` / `U. S. 967, 982–983 (2005). And those officials
  may even dis-` / `agree with…`; 10.98 pt, left edge 156.24, every wrapped line 299.4–299.6 wide.
- `loper-7`: `…under Chevron since` / `2016. But because Chevron remains on the books, litigants
  must con-`; 9 pt syllabus.
- `loper-13`: the indented opening line `A divided panel of the D. C. Circuit affirmed. See 45`
  (x 167.22) followed by `F. 4th 359 (2022). …` at the column edge (x 156.24): the outdent path.
- `loper-2`: `United States` / `v. Moore, 95 U. S. 760, 763. …`, `…Morton Salt Co., 338` /
  `U. S. 632, 644, …` and the short closing line `U. S. 134, 140.`; the page's four syllabus
  paragraphs must stay in order.

## Verification

`Tests/PDFReflowLibTests/LayoutEvidenceTests.swift` gains nine tests. The four Loper pages and the
9/11 page assert no preformatted block, the joined phrases inside one paragraph, and that the
page's non-whitespace characters are exactly the source lines'; Loper page 2 keeps its four
paragraphs with their openings and endings. Synthetic justified prose covers author initials, a
year and a `v.` line joining, and the controls that must not: a short introduction, full lines
ending in `:`, `.`, `.”`, `.)`, `?`, `!`, a paragraph gap, a marker indented 8 pt, a line the
reader marked as not wrapping, a ragged column, a right edge with only two supporting lines,
`•`/`−`/`-` markers, and a hanging-indent note where a dedented continuation is followed by an
indented `6.`. The corpus positive controls are `algebra-26` (every numbered Wallace exercise
stays its own block), `warren-50` under a synthetic text style, and `fed-77`/`fed-123` bullets.

With `continuesWrapped` forced to `false`, the same suite fails with 17 issues across seven tests
while both list-preserving controls still pass.

Commands on the final tree:

- `swift test`: 353 tests pass.
- `scripts/check-all.sh --fast`: all thirteen gates pass.
- `python3 tools/run_corpus_regressions.py --converter "$(swift build -c release --show-bin-path)/pdf-reflow"
  --epubcheck "$(command -v epubcheck)" --output <dir>`: all 18 gated cases pass, before and after.

The Loper Bright contract gains pages 2, 7 and 13 and a `paragraphs` check on page 60, and the
9/11 contract gains page 117; the lane grows from 462 checks on 105 pages to 477 on 109.

## Before and after

`<pre>` blocks, those between a `<p>` that does not end a sentence and a `<p>` opening lower-case,
and those ending in a hyphen, over every gated corpus case:

| Case | `<pre>` | interrupting a sentence | ending in a broken word |
| --- | --- | --- | --- |
| arxiv-replay-clocks-2023 | 5 → 2 | 2 → 1 | 0 → 0 |
| cdc-zombie-pandemic-2011 | 1 → 1 | 0 → 0 | 0 → 0 |
| census-rrs2002-01 | 17 → 17 | 0 → 0 | 0 → 0 |
| cia-blue-book-14-1955 | 667 → 666 | 35 → 35 | 16 → 16 |
| dga-2025-2030 | 8 → 8 | 4 → 4 | 0 → 0 |
| faa-phak-8083-25c | 508 → 505 | 107 → 106 | 1 → 1 |
| fed-explained-2021 | 81 → 81 | 25 → 25 | 14 → 14 |
| gpo-911-2004 | 1,321 → 1,291 | 79 → 57 | 198 → 190 |
| gpo-our-flag-2003 | 19 → 7 | 9 → 0 | 1 → 1 |
| gpo-warren-1964-suspect-text-excerpt | 2 → 2 | 0 → 0 | 0 → 0 |
| irs-p596-zhs-2025 | 60 → 60 | 1 → 1 | 0 → 0 |
| nbs-jres-geltman-1977 | 1 → 1 | 0 → 0 | 0 → 0 |
| ntrs-20180003024-earthdata-slides-2018 | 3 → 3 | 0 → 0 | 0 → 0 |
| scotus-loper-bright-2024 | 75 → 7 | 37 → 1 | 20 → 0 |
| uscis-m618-arabic-2015 | 6 → 6 | 0 → 0 | 0 → 0 |
| usda-ars-agresearch-2012-11 | 2 → 2 | 1 → 1 | 0 → 0 |
| usgs-mcs2025-copper | 0 → 0 | 0 → 0 | 0 → 0 |
| wallace-algebra-2010 | 2,911 → 2,909 | 15 → 14 | 4 → 4 |
| **total** | **5,687 → 5,568** | **315 → 245** | **254 → 226** |

Every one of the 119 removed blocks was reviewed against its source page. All are wrapped
continuations except the Blue Book one below. Two of the 9/11 removals read like note numbers and
are not: `13. The names they had were put on a watchlist…` ends the printed sentence "reported the
bad news on January 13", and `30. FBI report, "Hijackers Timeline,"…` ends "moving into a motel on
April 30".

No page loses words. Concatenating every block of every book and dropping whitespace and hyphens
gives byte-identical text before and after, for all 18 cases (4,655,902 characters); a join
only moves a line into the paragraph above it, where the existing hyphen policy may then close a
word the split had broken. All 4,367 image files in the 18 books are byte-identical.

Wallace keeps 2,909 preformatted exercise lines, the Fed book its bulleted lists, and the 9/11
report the 1,121 marker-leading blocks that are its table of contents and its endnote entries.

## Remaining gaps

- **Blue Book page 19 is a false join**, the one the branch's own port recorded. The page is an
  inherited-OCR scan (`unverifiedTextLayer`); `1132.01 representing an additional observer` and
  `1132. 02 representing an additional observer` are two entries of a serial-number code list
  whose equal-width lines satisfy the justified-column and prose tests, so the second is now
  appended to the first. Neither representation was right before — the entry was a lone `<pre>`
  line inside a run of them — and the rule consults neither the unverified text layer nor the
  shape of an enumerated code list.
- A marker-leading wrap after a line ending in an abbreviation (`Inc.`, `Tr.`) or a real sentence
  end stays split; punctuation alone cannot tell those apart. Four of Loper Bright's seven
  remaining blocks are this.
- Ragged-right columns and bibliography entries whose continuations hang under `[12]` keep the
  preformatted representation: the rule needs a justified measure and the majority left edge.
  #219 item 1 scopes that work.
- A marker line that opens a page after a running header depends on cross-page continuation
  (#45); two of Loper Bright's seven remaining blocks are this, and the seventh is its `* * *`
  separator.
- The rule joins lines. It builds no list model, so a line that opens an item is still a `<pre>`
  block and `ol`/`ul` are still not produced (#219).
