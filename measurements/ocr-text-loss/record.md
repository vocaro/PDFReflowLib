# Recognition that drops whole paragraphs, measured and reported (#116)

Tier: Vision, which is not deterministic across compiled model sets (#94, #173). macOS 27.0
(26A428), Xcode 27.0 (27A266a), arm64, release build, library defaults unless stated. Date
2026-09-19, on `9c76ba9` ("Cite #143 as history now that its decoding is on main").

#116's fix was never on `main`: it was closed by `458a2e9` on the abandoned coordination branch,
which `dd160b4` merged with the `ours` strategy without changing `main`'s tree
([decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md), #231). `main` already
carried `OCRTextCoverage`, but only as `PageDiagnosis`'s pre-recognition ink test for #93/#176:
nothing measured what Vision had actually returned. This is the hand-port, adapted to `main`'s
split between `RecognitionPolicy` deciding and `ConversionWarnings` wording, which the branch did
not have. Nothing below was copied from the branch's record; every number was re-measured.

## The instrument

[`tools/probes/probe-ocr-text-loss.swift`](../../tools/probes/probe-ocr-text-loss.swift) verifies
the corpus source's SHA-256, rasterizes each page as the conversion does, and calls the shipped
`OCRReader.recognize`, `OCRReader.completeReading` and `OCRTextCoverage` — so what it reports is
the library's behaviour, not a reimplementation. [`run-probe.sh`](run-probe.sh) builds it from the
one source list the gates read and runs it over a list of corpus cases;
[`summarize.py`](summarize.py) reduces its per-page JSON to [results.json](results.json).
[`recognized_pages.py`](recognized_pages.py) converts a book and reports which pages recognition
replaced, so the measurement covers pages the conversion actually recognizes.

## What is being dropped, before the fix

`OCRTextCoverage` finds rows of glyph-sized ink standing on clear background — the shape of
printed or typed writing — and measures how much of that ink lies outside every recognized line.
The uncovered rows are the evidence: writing the page draws and the reading does not account for.

| Book | Pages probed | Pages the first reading left writing on | Uncovered share there |
| --- | --- | --- | --- |
| `cia-blue-book-14-1955` | 312 | 63 | 0.20–1.00, median 0.31 |
| `gpo-warren-1964` pages 850–880 (endnotes) | 31 | 16 | 0.21–0.67 |
| `gpo-warren-1964` pages 95–115 | 21 | 2 (pages 100, 104) | 0.64, 0.83 |
| `gpo-warren-1964-suspect-text-excerpt` | 5 | 1 (excerpt page 2) | 0.22 |
| `cdc-zombie-pandemic-2011` | 42 | 0 | — |
| `census-rrs2002-01` | 20 | 0 | — |
| `ntrs-20180003024-earthdata-slides-2018` | 21 | 0 | — |
| `nbs-jres-geltman-1977` | 7 | 0 | — |
| `gpo-our-flag-2003` | 56 | 0 | — |

**The ink is writing that is there, not writing the page lacks.** Blue Book page 121 is a
statistical table; the first reading returned 237 lines and 365 words and its recognizable text
begins `TRBLERT / EVALURTIRO. / DE ALL`. The uncovered rows stand down the left edge of the table.
Recognized again in bands, the same page returns the stub column the first reading never touched —
`0-Balloon`, `1-Astronomical`, `2-Aircraft`, `3-Light Phenom.`, `4-Birds`, `5-Clouds, Dust, etc.`,
`6-Insuffic. Info.`, `7-Psychological`, `8-Unknown`, `9-Other`, `Total` — and the page's heading as
`TABLE AZ / EVALVATION / OF ALL / SIGHTINGS`. The page's own inherited OCR layer, read with
`pdftotext -f 121 -l 121`, independently contains `Evaluation`, `Balloon` and `I-Astronomical`: the
column is on the page, and the first reading dropped it.

## The rule

A reading is incomplete when **at least 8 uncovered rows hold at least 20% of the page's
text-shaped ink** (`OCRTextCoverage.minimumUncoveredRows`, `minimumUncoveredFraction`). Both
conditions are needed, and the corpus says why:

- **The share alone** would flag the CDC comic's cover (page 1: four uncovered rows, share 1.00)
  and Our Flag's cover (page 1: one uncovered row, share 1.00). A cover's few pieces of lettering
  are all the text-shaped ink it has, so anything the reading misses there is all of it. Neither
  is flagged, because neither reaches eight rows.
- **The row count alone** would flag the NBS paper's page 7 (24 uncovered rows, share 0.098),
  where marginal notation and equation fragments stand beside a reading that covers the prose.

No page of the 146 control pages (CDC comic, Census, the NASA slides, the NBS paper, Our Flag) is
flagged. These are the false-positive controls #116 asks for: the comic's pages are mostly
artwork, and their ink is a drawing rather than writing.

## What the retry recovers

A flagged page is recognized once more in two bands, the top and bottom 60% of the page, sharing
the middle fifth so that a line one band's edge cuts is whole in the other. Lines are kept from
the band holding their centre, so the shared strip is not transcribed twice. The banded reading is
kept only when it leaves less of the page's text ink uncovered, compared with both readings'
tables ignored, so a retry cannot win by finding a larger table region — which would move ink out
of the measurement and text into an image without reading a word more.

| Book | Retries kept | Words before | Words after | Uncovered share after |
| --- | --- | --- | --- | --- |
| `cia-blue-book-14-1955` | 63 of 63 | 90,460 | 106,900 (+18%) | 0.001–0.259, no page over 7 uncovered rows |
| `gpo-warren-1964` 850–880 | 16 of 16 | 13,307 | 21,547 (+62%) | 0.013–0.078 |
| `gpo-warren-1964` 95–115 | 2 of 2 | 5,238 | 6,091 | 0 on both pages |
| `gpo-warren-1964-suspect-text-excerpt` | 1 of 1 | 1,151 | 1,184 | 0 |

On this machine's models the retry recovered every flagged page: **no page in the corpus remains
incomplete after it**, so `incompleteRecognition` does not fire on any corpus book. The warning is
the contract for the case the retry cannot fix — #108's lossy compile lost about 40% of Census
lines, and nothing establishes that bands recover that particular loss — and its behaviour is
covered by tests with canned readings rather than by a corpus page.

## Cost

Blue Book, all 312 pages, this machine: first recognition **148.3 s**, coverage check **3.1 s**
(2.1%, about 10 ms a page), band retry on 63 pages **94.5 s** (+64%). Warren's endnote pages, where
half the pages retry, cost **+89%**. A retried page costs roughly three times a first recognition,
not the 1.2 page-areas its geometry suggests, because Vision returns far more lines from a band of
a dense table than from the whole page.

**The retry is bounded per page and is not bounded per document, deliberately.** One page is
recognized at most twice; `readInBands` runs exactly two recognitions and never recurses, so the
worst case for any page is one extra reading over 1.2 page areas. A per-document cap on how many
pages may retry was considered and rejected: it would spend the budget on whichever lossy pages
came first and silently withhold the protection from the rest, and it would make a page's text
depend on the pages before it. The cost is proportional to how much of a book is actually being
dropped, and a book losing nothing pays only the 2% coverage check.

## Determinism

Three runs of the probe over the same 312 Blue Book pages, on the same machine and models, flagged
61, 61 and 63 pages; the third run's first reading of the whole book returned 285 fewer words than
the first run's, and pages 6 and 111 were flagged only in it. That is #173 item 1 restated: which
pages a reading drops is a property of Vision, not of the run, and not stable even within one
compiled set. Nothing here should be read as "page N reads incompletely"; the stable claim is the
shape of the distribution — dense tables and handwritten endnote pages lose text, clean prose and
comic artwork do not.

The library's own tests therefore never run Vision for this behaviour. `RecognitionPolicy.resolve`
is given canned `OCRReader.Result` values with `uncoveredTextFraction` already set;
`PDFReflowLibPipeline.reconstruct` is given a canned recognizer; the loss rule is exercised on
synthetic rasters with known rows; and `OCRReader.mergeBands` is a pure function tested on band
coordinates alone.

## What this does not establish

- Whether bands recover the specific loss of #108's compiled model set. That set has not recurred
  here and cannot be summoned on demand.
- That a retried page's transcription is *correct*. It covers more of the page's writing, which is
  the only thing measured. Blue Book table cells are handwritten and read poorly either way.
- The rule's behaviour on books not declared English, on right-to-left scripts, or on pages whose
  writing is not printed rows.
- **That the rule catches every lossy page.** It does not. Warren's endnote pages 856–877 are one
  uniform run whose inherited layers each hold 950–1,200 words; Vision's first reading of each
  holds 300–600, and eight of the twenty-two are under the 20% ink share and so are neither
  retried nor reported. Page 865 (50 uncovered rows, share 0.197) and page 876 (40 rows, 0.201)
  differ by four thousandths and only one is caught. Filed as #240 with the page-by-page evidence;
  20% is kept here because it is the value the original 505-page survey chose and this port's
  false-positive control is 146 pages.
