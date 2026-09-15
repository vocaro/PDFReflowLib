# Cross-document regression gate

The complete `scripts/check-all.sh --corpus` run passes on macOS 27 arm64 with Xcode 27 and
release CLI defaults. All eight selected PDFs complete, pass EPUBCheck, remain within their
existing RSS budgets, preserve monotonic progress, and pass the new page-specific content gate.
[Summary](summary.json), [run identities and metrics](runs.json), and [full gate log](gate.log.gz)
retain the evidence. The converter is the issue-fix implementation `305cb14`, executable SHA-256
`5275579f7a238cf38ebc591b74315f37b1cf9256a1ff7fed826a2951aba3dc96`.

| Corpus | Complete source pages | Reviewed content pages | Targeted checks |
| --- | ---: | --- | ---: |
| FAA handbook | 522 | 16, 121 | 6 |
| Wallace algebra | 489 | 2, 12, 347 | 10 |
| 9/11 report | 585 | 15, 19 | 2 |
| The Fed Explained | 135 | 9, 45 | 8 |
| Dietary Guidelines | 10 | 2, 3 | 6 |
| Our Flag | 56 | 27, 33 | 9 |
| CDC comic | 42 | 5, 13, 39 | 10 |
| Blue Book | 312 | 74, 150 | 4 |

Total: 2,151 source pages converted; 55 content assertions on 18 selected pages. All source-page
boundaries are also required to appear once and in order, and semantic text must contain no
U+FFFC attachment placeholders. This is a regression baseline, not a whole-book fidelity score.
Images are checked for presence; their pixel contents and semantic associations are not globally
qualified. Page-specific text/ordering checks exclude navigation and generated image captions.

## Reviewed expectations

[corpus/regressions.json](../../corpus/regressions.json) records source identities, expected text,
selected order and image/warning requirements, with a written basis for each case. New source
reviews retain rasters for [FAA 16](faa-16.png), [algebra 12](algebra-12.png), [Fed 9](fed-9.png),
[DGA 2](dga-2.png), [Our Flag 27](flag-27.png) and [CDC 39](comic-39.png). The 9/11 correct-spacing
expectations and other figure targets use the existing manually reviewed corpus references.
Blue Book 74/150 reference images are reviewed in the [issue-fix measurement](../quality-and-raster-fixes/record.md).

The algebra page reproduces *Beginning and Intermediate Algebra* by Tyler Wallace (2010),
licensed [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/),
[source textbook](http://wallace.ccfaculty.org/book/book.html). This development raster is a
scaled rendering of page 12, not a relicense of the textbook. Other sources retain their corpus
provenance and rights records.

Known interleaved columns, flattened exponents, incorrect headings and table loss are deliberately
not recorded as correct output. The contracts instead preserve source-verified behavior around
them, such as the algebra example's explanation order, the Fed's five functions, and the CDC
emergency checklist. Full Warren and NOAA are listed as not covered because their default
conversions hit the known image-output limit (#5); they are not counted as passing or silently
skipped. The Warren excerpt remains a separate targeted regression.

Count comparisons against earlier retained runs show unchanged reflow/OCR/image counts for
algebra, 9/11, DGA and the comic. Fed OCR attempts decrease from 29 to 7 (images 281 to 315);
Our Flag OCR attempts decrease from 5 to 2 (images 128 to 146). Removing image placeholders from
native text also removes them from the damaged-text trigger, so these pages retain native text
instead of needlessly replacing it with OCR. Fed page 9's source-verified wording and function
order now pass without the older OCR substitutions. These count changes are investigated signals,
not proof that every newly retained text region is correct.

## Gate validation and reproduction

The complete gate log includes 41 Swift tests, 42 Python tests and six synthetic EPUB conversions
before the eight real-document evaluations. The final Python suite has 45 passing tests after
adding three runner boundary tests ([log](python-tests.log.gz)). All 41 Swift tests also pass on
iOS 27 in the [issue-fix run](../quality-and-raster-fixes/record.md); this follow-up adds development
Python tooling and contracts, with no Swift runtime changes.

The 14 new Python tests exercise missing/reordered/misassigned text, missing images, wrong-page
warnings, changed source identity, missing/duplicated boundaries, inline boundaries and chapter
continuation, captions masquerading as text, malformed contracts, empty selections, missing
fixtures, and continued reporting after a failed case. The final runner's selected-case path is
also measured with DGA ([smoke log](runner-smoke.log.gz)); omitted cases remain explicit. The
empty-selection rejection is added after the eight-case run and checked by the final unit suite.

```sh
# Explicitly seed the ignored corpus cache first; see doc/corpus.md.
scripts/check-all.sh --corpus

# Inspect an existing complete evaluation without reconverting:
python3 tools/check_corpus_content.py --case fed-explained-2021 \
  --evaluation /path/to/evaluation/fed-explained-2021
```

The per-case directories retain evaluator results, reports, progress and memory samples as gzip,
and EPUBCheck/content assessments as text/JSON. Complete EPUBs and originals remain ignored.
[Contract/checker identities](content-contract-identities.json) identify the final definitions.
Timing figures are individual process measurements on a shared host; do not infer a performance
trend from differences between runs. RSS covers the converter process, not external Apple
services or physical-device budgets.
