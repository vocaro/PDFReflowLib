# A numbered item the page broke mid-word

Our Flag sets its flag-folding instructions as a numbered list and breaks the first item at a
printed hyphen. The converted book kept the halves in two blocks:

```
<pre>1. Two persons, facing each other, hold the flag waist high and horizon-</pre>
<p>tally between them.</p>
```

#245 already states the rule that covers this shape — an item the page broke mid-word keeps the
rest of its word — and it did not fire. This record measures why, and what changed across the
corpus when it did (#266).

Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max, 36 GB. Library source at `ecee3eb`
(`main`) and that source plus the #266 change. Measured 2026-09-22 with release CLIs at library
defaults, both lanes at four jobs.

## The page's own evidence

Physical page 26 of `CDOC-108hdoc97.pdf` (printed folio 20, SHA-256
`a47a3153…36bbd8`), captured with `tools/probes/capture-layout-fixture.swift` and checked in as
`Tests/PDFReflowLibTests/fixtures/flag-26-layout.json`:

| Line | Text | x | minY | maxY | Size |
| ---: | --- | ---: | ---: | ---: | ---: |
| 6 | `1. Two persons, … waist high and horizon-` | 55.00 | 363.14 | 372.00 | 9.00 |
| 7 | `tally between them.` | 55.00 | 351.14 | 360.00 | 9.00 |

Every condition #245 states is met: the item ends in U+002D, the line beneath opens in lowercase,
both are 9-point, and the gap between them is 3.14 points — well inside the 7.2 the rule allows at
that size. Sixteen lines stand on the x = 55 edge and seven of them carry a marker, so the page
sets a list there.

## Mechanism: which branch opened the block

The rule reads the item from `BlockAssembler.itemLine`, and only the `.listItem` branch set it.
A line is `.listItem` when it opens with a bullet, a minus or a hyphen; a line that opens with a
number or a letter and a point is `.markedLine` instead, because the same token also ends a
citation and only the page can say which it is (#39, #171). A numbered item reaches the same
`.preformatted` block through that other branch, which left `itemLine` nil — so the rest of the
broken word was never offered to it. The 9/11 report's recommendations, which #245 was measured
on, are bulleted; Our Flag's instructions are numbered.

The fix is that branch recording `itemLine` as the `.listItem` branch does.

## What becomes of the hyphen

#245 dropped the break character unconditionally. Extending the rule to numbered items puts it in
front of printed compounds for the first time, and dropping the character there welds two words
the book prints apart. Measured on `main` plus the `itemLine` change alone, the 9/11 report
produced `command-andcontrol`, `explosivesladen` and `terroristcontrolled`.

So the join is `HyphenRepair`'s, on the same evidence it reads inside a paragraph: the book's own
words, and the English lexicon where the document is English. `Febru-` + `ary` loses its hyphen
because the book prints `February`; `explosives-` + `laden` keeps it because neither the joined
form nor the compound is a word the book or the lexicon holds, and no space is added either way.

This also corrects a `.listItem` join that was already wrong on `main`: the FAA handbook's
`(“gethome-itis,”` is `(“get-home-itis,”` after the change.

## What moved, per book

Eighteen covered cases, converted by both binaries. "Letters" is every alphanumeric character of
the book's XHTML in order, with markup, punctuation and whitespace removed — a repair of a broken
word leaves it identical, and a join that drops or welds text does not.

| Case | Blocks | Characters | Letters | XHTML identical |
| --- | ---: | ---: | ---: | :---: |
| arxiv-replay-clocks-2023 | 294 → 294 | 50,795 → 50,795 | unchanged | yes |
| cdc-zombie-pandemic-2011 | 653 → 653 | 18,398 → 18,398 | unchanged | yes |
| census-rrs2002-01 | 454 → 454 | 42,997 → 42,997 | unchanged | yes |
| cia-blue-book-14-1955 | 23,630 → 23,630 | 858,544 → 858,544 | unchanged | yes |
| dga-2025-2030 | 187 → 187 | 17,118 → 17,118 | unchanged | yes |
| faa-phak-8083-25c | 10,153 → 10,153 | 1,698,087 → 1,698,088 | unchanged | no (1 document) |
| fed-explained-2021 | 1,254 → 1,252 | 209,717 → 209,709 | unchanged | no (2 documents) |
| gpo-911-2004 | 5,782 → 5,727 | 1,893,893 → 1,893,588 | same count, one move | no (16 documents) |
| gpo-our-flag-2003 | 798 → 797 | 82,256 → 82,254 | unchanged | no (1 document) |
| gpo-warren-1964-suspect-text-excerpt | 30 → 30 | 5,897 → 5,897 | unchanged | yes |
| irs-p596-zhs-2025 | 1,164 → 1,164 | 45,610 → 45,610 | unchanged | yes |
| nbs-jres-geltman-1977 | 62 → 62 | 4,302 → 4,302 | unchanged | yes |
| ntrs-20180003024-earthdata-slides-2018 | 234 → 234 | 5,154 → 5,154 | unchanged | yes |
| scotus-loper-bright-2024 | 853 → 853 | 237,782 → 237,782 | unchanged | yes |
| uscis-m618-arabic-2015 | 979 → 979 | 116,925 → 116,925 | unchanged | yes |
| usda-ars-agresearch-2012-11 | 1,063 → 1,063 | 63,794 → 63,794 | unchanged | yes |
| usgs-mcs2025-copper | 309 → 309 | 8,466 → 8,466 | unchanged | yes |
| wallace-algebra-2010 | 10,449 → 10,449 | 463,306 → 463,304 | unchanged | no (1 document) |

Thirteen of the eighteen books are identical document for document. The character counts fall
only by the hyphens the repairs removed and the block boundaries that closed.

The one letter-stream move is in `gpo-911-2004`: the caption of the page-490 scan used to stand
between `Estab-` and `lishment`, and now stands after the repaired word. Nothing is added or
lost — the count is 1,519,245 in both books.

`gpo-911-2004` also re-packs its spine by one page: source page 517's anchor moves from
`chapter-28.xhtml` to `chapter-27.xhtml`. Its 585 page-list entries are otherwise unchanged, and
the lane reports no spine boundary crossed in either run.

## Words no longer broken at a block boundary

Blocks whose text ends in a hyphen or a soft hyphen — a word the reader meets in halves:

| Case | Before | After |
| --- | ---: | ---: |
| gpo-911-2004 | 187 | 33 |
| usda-ars-agresearch-2012-11 | 54 | 54 |
| cia-blue-book-14-1955 | 85 | 85 |
| wallace-algebra-2010 | 22 | 21 |
| fed-explained-2021 | 14 | 11 |
| scotus-loper-bright-2024 | 8 | 8 |
| faa-phak-8083-25c | 6 | 6 |
| census-rrs2002-01 | 4 | 4 |
| gpo-warren-1964-suspect-text-excerpt | 2 | 2 |
| gpo-our-flag-2003 | 1 | 0 |

No book gains. The 9/11 report loses 154 of them, which is what the endnote lists were costing:
its notes are numbered, and every one of them the page broke mid-word was split into a `<pre>`
and a `<p>`.

The remaining 85 in the CIA Blue Book and 54 in the USDA magazine are not this shape at all —
neither book sets the split across an item boundary — and are untouched here.

## What the repair leaves behind

Three of the block ends counted above are new, in a shape the same repair creates: the item takes
one printed line, and where *that* line ends in a hyphen the line after it cannot always join —
it opens in uppercase, or it is the first line of the next page, where a `<p>` would have carried
on and a `<pre>` does not. `num-` / `bers` and `265A-NY-` / `280350-302` in the 9/11 endnotes and
`Fed-` / `Wire` in the Fed book are the three. Filed as
[#280](https://github.com/vocaro/PDFReflowLib/issues/280); the halves are the wrapped remainder of
an item, which is #172 and #265's subject rather than a second hyphen rule.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. The corpus lane passes 18 of 18
covered cases at four jobs, every `runPassed` read from its own `result.json` and every
`content-assessment.json` holding zero errors.

## Reproducing

```sh
swiftc $(python3 tools/pdfreflow_tools/swift_sources.py capture-layout-fixture.swift) \
  -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture gpo-our-flag-2003 26 /tmp/flag-26-layout.json
swift build -c release
python3 tools/run_corpus_regressions.py --converter "$(swift build -c release --show-bin-path)/pdf-reflow" \
  --epubcheck "$(command -v epubcheck)" --output /tmp/corpus-266 --jobs 4
```
