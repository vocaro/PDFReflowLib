# Receipted before/after comparison (#36)

Both runs used `tools/run_corpus_regressions.py` with `--environment-probe` (compiled
`tools/probe-raster-environment.swift`) and `--execution-context host-terminal` on the same
macOS 27.0 (26A428) arm64 machine, Xcode 27.0 (27A266a), library defaults, cases
`usgs-mcs2025-copper`, `irs-p596-zhs-2025`, `nbs-jres-geltman-1977`, `gpo-our-flag-2003`,
`faa-phak-8083-25c`, `wallace-algebra-2010`, against the reviewed contracts in the working tree.

| Run | Converter SHA-256 | Result |
| --- | --- | --- |
| Baseline `56e70e2` | `851f3b1f9f88cdfaa11e5f49adf831f1d2f33b260279bfe3277a4f0b833af370` | USGS and NBS fail the new contracts (prose still inside crops); IRS, Our Flag, FAA, Wallace pass |
| Candidate (this change) | `fa951b7c6016fd6325343bbd6fce94f22601009780407edac47c83164528fed6` | all six pass: USGS 34 checks, IRS 12, NBS 13, Our Flag 58, FAA 57, Wallace 20 |

`tools/compare_conversion_runs.py` accepts both receipts as capability-compatible (no
provenance errors). It reports every page after the first changed page, because `image-N`
asset names shift once a page gains or loses an image, so the table below uses the page
reader's normalized text and image bytes matched by content hash instead
(`content-diff-final4.json` in the run directory; images counted per book).

| Case | Strict result | Pages whose text changed | Pages whose image count changed | Images before → after | Pages losing reflowed words |
| --- | --- | ---: | ---: | --- | ---: |
| USGS copper | changed | 2 (pages 1, 2) | 2 | 12 → 3 | 0 |
| NBS Geltman | changed | 1 (page 7) | 0 | 8 → 8 (one crop re-cut) | 0 |
| IRS Publication 596 (control only) | changed | 17 | 9 | 139 → 140 | 0 |
| Our Flag | identical | 0 | 0 | 147 → 147 (byte-identical) | 0 |
| FAA handbook | changed | 55 | 11 | 588 → 599 | 0 |
| Wallace algebra | changed | 63 | 35 | 2050 → 2047 | 0 |

## Control changes explained

No page in any of the six books reflows fewer words than before. Our Flag is byte-identical,
including page 27's two isolated heading rules and dot-leader table (`minimumImages: 3`).

FAA: the 55 changed pages gain 8,464 reflowed words in total; page markers and all 57 contract
checks (including the three page-121 figure references) are unchanged. Pages 19 (0 → 373
words), 78 (52 → 213), 101 (25 → 324) and 108 (8 → 398) were whole or half pages swept into one
crop by a figure's rule or Form XObject box chaining through tight leading; their prose now
reflows. Page 19 still keeps 27 prose lines inside its figure crop and reads with interleaved
columns; see the new defects in the record.

Wallace: the 63 changed pages gain 1,280 reflowed words; the 20 contract checks (including the
page-347 exercise reference and both page-26 exponents) and the 36 fraction crops on practice
page 16, 26 on page 17 and 7 on page 244 are unchanged or restored. What now reflows are
worked-example annotation lines ("Parenthesis first", "Exponents", "Multiply", "Our Solution")
and prose ("World View Note: …", "To graph each equation, we start at …") that used to be
absorbed by the neighbouring equation or fraction crop through overlapping line rectangles.
Inline `rise/run` in the page-137 prose is the one spotted regression: its numerator is merged
into the prose line, so the bar is decoration and "run" reflows on its own; before, the
whole sentence was inside a crop.

IRS (control only, not diagnosed): 17 pages change, none loses words; page 3 goes from 4 to
118 reflowed words. Its contract (page-1 catalog line, page-16 order) passes both before and
after.
