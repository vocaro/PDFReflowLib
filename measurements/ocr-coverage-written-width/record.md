# A reading measured by what it wrote, not by where it looked (#240)

Tier: Vision, which is not deterministic across compiled model sets (#94, #173). macOS 27.0
(26A428), Xcode 27.0 (27A266a), arm64, release build, library defaults unless stated. Date
2026-09-19, on `da544ad` ("Resolve the corpus contract conflict the running-head merge left
unresolved"). Extends [#116's record](../ocr-text-loss/record.md), which is hours old; every
number below was measured here, and #116's are quoted only where they are named as such.

#116 calls a recognition incomplete when at least 8 rows of the page's text-shaped ink lie
outside every recognized line and those rows hold at least 20% of that ink. #240 reported that
Warren's endnote pages 856–877 lose about half their words while eight of the twenty-two stay
under the 20% share, and asked what evidence would justify a different rule — not which number is
better.

**The answer is that no number on that signal is right, because the signal was measuring the
wrong thing.** A recognized line's box says where Vision looked. It does not say what Vision
wrote. On these pages Vision returns a box for a line it found and a transcription of part of it,
and coverage measured from the box alone reports the rest of that line as accounted for. The rule
now measures each line against the writing its own transcription can fill. **#116's thresholds are
untouched**: 8 uncovered rows, 20% of the page's ink, exactly as the original 505-page survey set
them.

## What the evidence had to settle first

[`tools/probes/probe-ocr-coverage-signals.swift`](../../tools/probes/probe-ocr-coverage-signals.swift)
verifies the corpus source's SHA-256, rasterizes each page as the conversion does, calls the
shipped `OCRReader.recognize`, `OCRReader.mergeBands` and `OCRTextCoverage`, and — unlike #116's
probe — **attempts the band retry on every page whether or not any rule asks for it**, recording
both readings and their line geometry. [`label_pages.py`](label_pages.py) then extracts each
page's own text layer with `pdftotext` and reports what share of the layer's tokens each reading
holds. That share is the ground truth: a rule is justified by whether the pages it flags are the
pages whose reading is missing the page's words, not by how many it flags.

**Warren's endnote run is not eight bad pages among twenty-two good ones. All thirty-one pages
850–880 are losing text, and the ink share does not distinguish them.**

| Page | Uncovered ink | Tokens held, first reading | Tokens held, banded | Gain |
| ---: | ---: | ---: | ---: | ---: |
| 859 | 0.670 | 0.07 | 0.69 | +0.62 |
| 852 | 0.272 | 0.24 | 0.72 | +0.48 |
| 865 | 0.197 | 0.27 | 0.66 | +0.38 |
| 856 | 0.155 | 0.37 | 0.72 | +0.35 |
| 853 | 0.088 | 0.44 | 0.79 | +0.35 |
| 878 | 0.054 | 0.48 | 0.76 | +0.28 |

Page 878 leaves 5% of its ink uncovered and is missing over half its layer's tokens; the banded
reading of it raises recall from 0.48 to 0.76 **and** precision from 0.70 to 0.84, so those are
words read, not words repeated. Lowering the 20% threshold would have caught some of these pages
and missed others for no reason connected to what they lost. That is why this is not a threshold
change.

## Why the boxes are wrong, measured

Every recognized line was measured against the page's own rows of writing: its box's width
divided by its character count and by the height of one row of that page's writing.

| Lines measured | p05 | p25 | median | p75 | p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 18,442 lines of readings their page's layer confirms complete (recall ≥ 0.95) | 0.42 | 0.51 | **0.555** | 0.597 | 0.875 |
| 1,796 lines of the Warren endnote readings | 0.725 | 0.805 | **0.868** | 0.958 | 1.171 |

A complete reading's line is **0.55 row heights wide per character** — a typographic fact about
Latin text, not a fitted constant, and stable across the corpus. The Warren endnote readings'
lines are 0.87: half again as wide as their own text can fill. That gap is the loss, drawn as
geometry.

## The rule

`OCRTextCoverage.Line` now carries `advances`, the line's transcription in Latin character
widths, and a line covers only `advances × characterWidthInRows × (the page's own row height)` of
the row it lies on. `characterWidthInRows` is **0.6**: above the median and the third quartile of
complete readings, so a line that transcribed its row still covers it. A fullwidth or ideographic
character counts as two, because it is drawn about twice as wide (`advances(of:)`); without that,
a sound reading of a Chinese page measures like one that dropped half of it — see the IRS case
below. The page's own text layer, measured before any recognition for #93 and #176, carries no
`advances` and is believed for its whole box, so that path is unchanged.

`OCRReader` keeps a banded reading only when it covers more of the page's writing **and does not
return fewer words** (`bandsAreKept`). The always-retry probe found the hazard is real — Our Flag
page 54 and Blue Book pages 28, 274 and 293 have banded readings that cover more ink with fewer
words — though under this rule none of those pages is flagged.

### Why 0.6, and what the other values do

| Per-character width | Of the 146 control pages, flagged | Highest control share | Of the 31 Warren endnote pages, flagged |
| ---: | ---: | ---: | ---: |
| 0.4 | 26 | 0.738 | 31 |
| 0.5 | 2 | 0.241 | 31 |
| **0.6** | **0** | **0.150** | **30** |
| 0.7 | 0 | 0.105 | 24 |

0.6 is derived from the complete readings, not from this table; the table is the check. It is
also the most sensitive value the 146-page control permits, and the record says so rather than
implying the two agreed by luck. At 0.5 two NBS pages flag; at 0.7 six Warren endnote pages that
are losing half their words are missed.

### The claim that justifies it

On the Blue Book, the 280 pages with a usable inherited layer split three ways
([calibration.json](calibration.json)):

| Pages | First reading's recall | Banded recall | Median gain | Gaining over 5 points |
| --- | ---: | ---: | ---: | ---: |
| 61 flagged by #116's rule | 0.124 | 0.332 | **+0.206** | 60 of 61 |
| 59 flagged by the written width only | 0.143 | 0.355 | **+0.199** | 57 of 59 |
| 160 flagged by neither | 0.706 | 0.765 | +0.012 | 56 of 160 |

**The pages the new rule adds are as lossy as the pages the old rule already caught, and the
pages it still leaves alone gain nothing from being read again.** That is the justification: the
rule is not tuned to flag more, it is measured to flag the right ones.

## The distribution, before and after

Both rules applied to the same readings, so nothing here is Vision's run-to-run variation
([rules-compared.json](rules-compared.json), [`compare_rules.py`](compare_rules.py)):

| Book | Pages | Flagged before → after | Retried before → after | Reflowed words before → after |
| --- | ---: | --- | --- | --- |
| `cia-blue-book-14-1955` | 312 | 61 → 121 | 61 → 120 | 106,992 → 120,461 (+12.6%) |
| `gpo-warren-1964` 850–880 | 31 | 16 → 30 | 16 → 30 | 21,547 → 26,330 (+22.2%) |
| `gpo-warren-1964` 95–115 | 21 | 2 → 2 | 2 → 2 | 6,091 → 6,091 |
| 146 control pages | 146 | 0 → 0 | 0 → 0 | 27,460 → 27,460 |

Run through the shipped `OCRReader.completeReading` by
[#116's own probe](../ocr-text-loss/run-probe.sh). The control books and the Warren endnote pages
were run twice and came out identical; the Blue Book, Warren 95–115 and the excerpt once:

| Book | Pages | Flagged | Retries kept | Still `incompleteRecognition` | Words |
| --- | ---: | ---: | ---: | ---: | --- |
| `cia-blue-book-14-1955` | 312 | 125 | 124 | 1 (page 33) | 90,460 → 120,534 (+33%) |
| `gpo-warren-1964` 850–880 | 31 | 30 | 29 | 6 | 13,307 → 26,028 (+96%) |
| `gpo-warren-1964` 95–115 | 21 | 2 | 2 | 0 | 5,238 → 6,091 |
| `gpo-warren-1964-suspect-text-excerpt` | 5 | 2 | 1 | 2 | 1,151 → 1,184 |
| `cdc-zombie-pandemic-2011` | 42 | 0 | 0 | 0 | 2,686 unchanged |
| `census-rrs2002-01` | 20 | 0 | 0 | 0 | 6,883 unchanged |
| `ntrs-20180003024-earthdata-slides-2018` | 21 | 0 | 0 | 0 | 545 unchanged |
| `nbs-jres-geltman-1977` | 7 | 0 | 0 | 0 | 4,214 unchanged |
| `gpo-our-flag-2003` | 56 | 0 | 0 | 0 | 13,132 unchanged |

`incompleteRecognition` now fires on corpus pages, where under #116 it fired on none. That is not
a regression: those readings really are still missing writing — the six Warren pages that report
it hold 715–956 words against layers of 1,000–1,150 — and saying so is the warning's contract.

**No page lost words.** Across all 515 pages of the shipped runs, and all 1,319 pages of the
always-retry probe under the new rule, no page's final reading holds fewer words than its first.

### The Warren endnote run, page by page

[warren-endnote-run.json](warren-endnote-run.json) has these as data. "Before" is the same run's
first reading judged by #116's rule; "after" is the shipped conversion.

| Page | Layer | Before: words / share / flagged | After: words / share / flagged / retried / incomplete |
| ---: | ---: | --- | --- |
| 856 | 960 | 477 / 0.155 / no | 821 / 0.247 / yes / yes / no |
| 857 | 946 | 343 / 0.427 / yes | 728 / 0.507 / yes / yes / no |
| 858 | 1164 | 400 / 0.311 / yes | 824 / 0.407 / yes / yes / no |
| 859 | 1197 | 111 / 0.670 / yes | 968 / 0.739 / yes / yes / no |
| 860 | 1016 | 432 / 0.195 / no | 715 / 0.319 / yes / yes / yes |
| 861 | 1000 | 442 / 0.189 / no | 817 / 0.256 / yes / yes / no |
| 862 | 1013 | 477 / 0.210 / yes | 850 / 0.275 / yes / yes / no |
| 863 | 1109 | 361 / 0.398 / yes | 777 / 0.470 / yes / yes / no |
| 864 | 1198 | 289 / 0.372 / yes | 894 / 0.514 / yes / yes / no |
| 865 | 1154 | 433 / 0.197 / no | 888 / 0.368 / yes / yes / no |
| 866 | 1043 | 347 / 0.324 / yes | 901 / 0.428 / yes / yes / no |
| 867 | 1028 | 518 / 0.106 / no | 863 / 0.241 / yes / yes / no |
| 868 | 1068 | 388 / 0.283 / yes | 914 / 0.396 / yes / yes / no |
| 869 | 1183 | 396 / 0.248 / yes | 958 / 0.367 / yes / yes / no |
| 870 | 1149 | 408 / 0.363 / yes | 956 / 0.484 / yes / yes / yes |
| 871 | 1125 | 473 / 0.176 / no | 970 / 0.311 / yes / yes / no |
| 872 | 1120 | 371 / 0.277 / yes | 960 / 0.414 / yes / yes / no |
| 873 | 1051 | 383 / 0.258 / yes | 968 / 0.418 / yes / yes / no |
| 874 | 1014 | 326 / 0.371 / yes | 836 / 0.483 / yes / yes / no |
| 875 | 1016 | 519 / 0.127 / no | 820 / 0.287 / yes / yes / yes |
| 876 | 1002 | 419 / 0.201 / yes | 829 / 0.341 / yes / yes / yes |
| 877 | 1044 | 604 / 0.074 / no | 946 / 0.237 / yes / yes / no |
| **856–877** | **23,600** | **8,917 words, 14 of 22 flagged** | **19,203 words, 22 of 22 flagged and retried** |

All eight pages #240 named are now flagged, retried and recovered. Page 853, outside the named
range, is the run's one page the rule still misses: 0.176 of its ink uncovered, and its reading
holds 0.44 of its layer where the bands hold 0.79.

## The control

**Not one of the 146 control pages #116 established is flagged**, in four measurements of them
(two probe runs of the signals, two of the shipped rule), and their reflowed words are unchanged
to the word. The highest written-width share any control page with at least 8 uncovered rows
reaches is 0.150, on the NBS paper's page 7 — the page #116 named as the reason the share is
needed at all.

The control was also widened by 809 pages across twelve more corpus books, probed the same way:

| Book | Pages | Flagged before → after |
| --- | ---: | --- |
| `wallace-algebra-2010` 1–100 | 100 | 0 → 0 |
| `gpo-911-2004` 1–100 | 100 | 0 → 0 |
| `faa-phak-8083-25c` 1–100 | 100 | 0 → 1 |
| `noaa-nca5-2023` 1–60 | 60 | 0 → 1 |
| `fed-explained-2021` | 135 | 0 → 3 |
| `scotus-loper-bright-2024` | 114 | 0 → 0 |
| `uscis-m618-arabic-2015` | 116 | 0 → 0 |
| `irs-p596-zhs-2025` | 36 | 2 → 2 |
| `usda-ars-agresearch-2012-11` | 24 | 0 → 0 |
| `arxiv-replay-clocks-2023` | 12 | 1 → 1 |
| `dga-2025-2030` | 10 | 0 → 0 |
| `usgs-mcs2025-copper` | 2 | 0 → 0 |

Five new flags in 809 pages. Four are real: FAA page 58 (0.84 → 1.00 recall from the bands), Fed
pages 67 (0.65 → 0.77) and 89 (0.85 → 1.00), and the arXiv paper's page 12 (0.52 → 0.78). The
fifth, NOAA page 33, is a twelve-token slide read perfectly by both. Fed page 126 flags at a
recall already 0.99, and its retry adds a hundred words of figure text; that is the weakest flag
in the set.

`irs-p596-zhs-2025`, a Chinese publication, is why `advances(of:)` weights fullwidth characters.
Counting every character as one Latin advance flagged **24 of its 25 sound pages** (recall 0.81 to
1.00). Weighted, none of them flags, and the rule still catches the two tax-table pages #116
caught — pages 24 to 34 of that book lose 70–80% of their text and only two are caught either way,
which this change does not fix.

## Cost

The coverage check itself is unchanged at 6–10 ms a page: the same measurement with each line's
box cut before it is painted. The retry is what costs, and it now runs on more pages, in
proportion to how much of a book is being dropped:

| Book | Retry cost, #116 | Retry cost here |
| --- | ---: | ---: |
| `cia-blue-book-14-1955` (312 pages) | +64% of recognition | **+126%** |
| `gpo-warren-1964` 850–880 | +89% | **+166%, +169%** (two runs) |
| `gpo-warren-1964` 95–115 | — | +22% |
| `gpo-warren-1964-suspect-text-excerpt` | +27% | +54% |
| the 146 control pages | 0% | **0%** |

A book losing nothing still pays only the coverage check. The Blue Book's recognition cost roughly
doubles and returns 30,000 more words; the Warren endnote pages cost about two and a half times a
single reading and return twice the words.

## Determinism

Which pages a reading drops is a property of the compiled Vision models, not of the run (#173),
so every number above says how many runs it rests on. The shipped rule was run twice over the 146
control pages and the Warren endnote pages: both runs flagged 0 and 30, kept 0 and 29 retries,
reported the same six pages incomplete, and returned identical word counts. The Blue Book was run
once through the shipped rule and once through the always-retry probe. The calibration rests on
one probe run of 1,111 pages; the Blue Book recall table on one run of its 312.

The library's tests never run Vision for this behavior, as #116 established.
`OCRTextCoverage.measure` is exercised on synthetic rasters with known rows and canned line
boxes, `advances(of:)` on strings, and `OCRReader.bandsAreKept` on numbers alone.

## What this does not establish

- **Right-to-left writing.** A clipped line keeps the part at its box's leading edge, which is
  where left-to-right writing starts. `uscis-m618-arabic-2015` flags no page either way, so
  nothing here is evidence about Arabic beyond that.
- **That a flagged page can be recovered.** Blue Book page 33 is flagged, its retry is refused
  (the bands cover no more of it and return one word fewer), and it reports
  `incompleteRecognition`: 35 words against a layer of 167 tokens, recall 0.13 either way. The
  warning is all the rule can do there.
- **That the rule catches every lossy page.** It does not. Warren page 853 holds 0.44 of its
  layer where the bands hold 0.79 and is not flagged, and the Chinese tax tables lose far more
  than the two flagged pages of them show.
- **That a retried page's transcription is correct.** It covers more of the page's writing and
  holds more of the page's own words; neither is a claim about accuracy. Warren endnote pages
  still read at 0.6–0.8 of their layer after the retry.
- **The per-character width on writing that is not printed rows of characters** — handwriting,
  monospaced tabulation and mathematics all draw differently, and the Blue Book's flagged pages
  are largely the first of those.
