# Real-document development corpus

`corpus/manifest.json` pins every external PDF by byte count and SHA-256. PDFs and generated
EPUBs remain local; routine tests download nothing. Rights declarations, owner confirmations and attribution are recorded per source in the
manifest. Retain the applicable attribution and license. The original six synthetic fixtures remain
in `Tests/PDFReflowLibTests/fixtures` and run without any external documents. A small CC BY 3.0
text/geometry extraction of Wallace algebra page 17 accompanies them for offline layout regression;
its source PDF remains in the ignored cache. See [regression testing](regression-testing.md).

Fetch all registered originals explicitly with Python 3.11+:

```sh
python3 tools/fetch_corpus.py --all
# Or select one document:
python3 tools/fetch_corpus.py --case wallace-algebra-2010
```

Downloads live in gitignored `corpus/cache/`. The fetcher checks byte count and SHA-256 on
both downloads and cache hits. It publishes downloads atomically; a failed refresh preserves
the existing copy. `--refresh` verifies the remote copy again, and `--cache-dir` selects another
location. A changed publisher file fails verification instead of silently replacing a fixture.
The manifest separates source/attribution URLs from direct `downloadURL` values. Cached files
work offline. Tests and conversion never fetch sources automatically.

| Case | Pages | Coverage | Initial Mac peak-RSS ceiling |
| --- | ---: | --- | ---: |
| `faa-phak-8083-25c` | 522 | Columns, illustrations, diagrams, tables, glossary | 1,280 MiB |
| `wallace-algebra-2010` | 489 | Fractions, radicals, powers, examples, exercises, answer keys | 256 MiB |
| `gpo-warren-1964` | 920 | Scans, noisy existing OCR, notes, index, large image output | Unset: default conversion fails |
| `gpo-911-2004` | 585 | Untagged digital text, alternating headers, tracked lettering, endnotes | 256 MiB |
| `fed-explained-2021` | 135 | Tagged text, recurring tables, organization charts and flow diagrams | 768 MiB |
| `dga-2025-2030` | 10 | Illustrated section bands, gradients, bullet columns and callouts | 192 MiB |
| `noaa-nca5-2023` | 1,834 | Large tagged report, mixed orientations, 32 chapter starts, uneven graphics | 1,280 MiB |
| `gpo-our-flag-2003` | 56 | Structure-tree inconsistencies, flag illustrations, drop capitals, one visible table | 192 MiB |
| `cdc-zombie-pandemic-2011` | 42 | Comic artwork, noisy inherited text, image-only dialogue, panel order | 512 MiB |
| `cia-blue-book-14-1955` | 312 | Scanned statistical tables, inherited OCR, negative warning/refusal contract | 512 MiB |
| `nbs-jres-geltman-1977` | 7 | Scanned two-column academic paper, footnotes, OCR-damaged equations | 512 MiB |
| `arxiv-replay-clocks-2023` | 12 | Born-digital ACM two-column paper, pseudocode, figures, math | 256 MiB |
| `usgs-mcs2025-copper` | 2 | Borderless tables, indentation-only row groups, spanning headers | 128 MiB |
| `scotus-loper-bright-2024` | 114 | Page-bottom footnotes continuing across pages, dash separators | 128 MiB |
| `census-rrs2002-01` | 20 | Born-digital text layer with no Unicode mapping (shifted letters); 2 pages decoded natively, 17 recognized by default | 512 MiB |
| `uscis-m618-arabic-2015` | 116 | Right-to-left Arabic with embedded Latin and numbers | 256 MiB |
| `irs-p596-zhs-2025` | 36 | Simplified Chinese mixed with Latin identifiers and amounts | 256 MiB |
| `uscourts-pro-se-1-2016` | 5 | Fillable AcroForm: field labels beside blanks, checkboxes, push buttons | 128 MiB |
| `ntrs-20200002975-gwl-2020` | 20 | Microsoft Word export: tagged IEEE two-column paper, Symbol-font characters | 256 MiB |
| `usda-ars-agresearch-2012-11` | 24 | InDesign magazine: wrapped photos, sidebars, pull quotes, two-page index | 512 MiB |
| `ntrs-20190030725-dasc-2019` | 10 | pdfTeX IEEEtran paper: small-caps headings, Computer Modern math, algorithm steps | 128 MiB |
| `ntrs-20180003024-earthdata-slides-2018` | 21 | Google Slides export: slide titles, numbered lists, shape-and-text-box diagrams | 128 MiB |
| `ntrs-20210020887-techport-thm-2021` | 5 | Chromium web print: header band, sidebar, bullet lists, tables, print footer | 128 MiB |

These are regression limits for release CLI processes on macOS arm64, not physical-device
budgets or guarantees about Apple service memory. Each evaluation verifies exact input identity
before conversion and records progress, timing, memory, output structure and optional EPUBCheck.

Peak resident size is a noisy measure: purgeable pages Apple frameworks leave mapped (Vision's
IOSurfaces) stay resident while the machine is not under pressure, so identical conversions of
one book differ by about 100 MiB and a ceiling near a book's peak flaps (#140). The gate
therefore takes the lowest peak of up to `--memory-attempts` conversions (default 2): the
repeat runs only when the first peak exceeds the ceiling, converts with the same options purely
to measure, and its output is deleted rather than checked. Every attempt is recorded in
`memoryGate.attempts`, so a regression that raises each attempt still fails, and
`--memory-attempts 1` gates on the checked conversion alone. Each receipt also records
`converterPeakPhysicalFootprintBytes`, the kernel's exact lifetime peak physical footprint (the
measure iOS memory limits count), read from the exited process before it is reaped; it is more
stable than resident size on a book without band retries (CDC over eight runs: 325–337 MiB
footprint against 419–443 MiB resident) and no more stable on one with them (Blue Book
`--ocr always`: 468–603 against 548–593). `sampledPeakPhysicalFootprintBytes` remains the
0.1-second sampling, which can miss a peak by 60–90 MiB. Measured spreads are in the
[run-to-run variance record](../measurements/run-to-run-variance/record.md).
The seven [#30 cases](#issue-30-coverage-expansion) are gated with reviewed contracts; their
selection and download identities are in [their record](../measurements/corpus-candidates-30/record.md).
The [Pro Se 1 form](#complaint-for-a-civil-case-pro-se-1), the
[Word-exported NASA paper](#ground-wind-loads-paper-word-2013), the
[Agricultural Research magazine](#agricultural-research-magazine-indesign), the
[IEEEtran NASA paper](#arrival-scheduling-paper-pdftex-ieeetran), the
[Google Slides deck](#earthdata-cloud-analytics-slides-google-slides) and the
[TechPort web print](#tank-health-monitoring-techport-web-print) are gated the same way.

## Comparing conversion runs

Builds launched from different execution environments can produce different rasters and OCR
results on the same Mac. The [controlled CDC/DGA investigation](../measurements/raster-environment/record.md)
reproduces this with the same retained binaries. An OS string or a caller-supplied context label
alone does not establish comparable capabilities.

For strict drift comparisons, compile one capability probe and reuse that exact executable for
both evaluations. Run the probe through the evaluator so it executes immediately before each
conversion, against physical page 1 of the same verified PDF, in the same launch environment:

```sh
mkdir -p .build/raster-environment
xcrun swiftc -parse-as-library -O \
  -module-cache-path .build/raster-environment/module-cache \
  Sources/PDFReflowLib/PageRasterizer.swift Sources/PDFReflowLib/ConversionTypes.swift \
  Sources/PDFReflowLib/DocumentModel.swift Sources/PDFReflowLib/ReflowDocument.swift \
  tools/probe-raster-environment.swift -o .build/raster-environment/probe
python3 tools/evaluate-real-document.py --case dga-2025-2030 \
  --pdf corpus/cache/DGA.pdf --converter .build/release/pdf-reflow \
  --output /tmp/dga-candidate --epubcheck /opt/homebrew/bin/epubcheck \
  --environment-probe .build/raster-environment/probe --execution-context host-terminal
python3 tools/compare_conversion_runs.py --baseline /tmp/dga-baseline \
  --candidate /tmp/dga-candidate --output /tmp/dga-drift.json --allow-different-converters
```

Capture `/tmp/dga-baseline` with the baseline converter and the same probe before comparing.
`run_corpus_regressions.py` accepts both new flags and forwards them to every selected case.
Keep resource measurements sequential. The probe requires the same macOS/Vision SDK as the
library. Compiling it again changes its identity; recapture both runs if that identity changes.

The evaluator records a fresh run ID, converter and probe executable SHA-256, source identity,
system/build/architecture, probe result SHA-256, and EPUB SHA-256. The probe reports its own
executable/source/run identities, packed raster pixels without alignment padding, dimensions,
color-space metadata, available Metal device, and Vision success or failure plus recognized
lines. A probe timeout, launch failure, malformed output, stale identity, or OCR failure fails
the requested capability gate while retaining conversion diagnostics and a failed receipt.
The declared `--execution-context` is supplemental and may be absent or differ between two
otherwise compatible captures.

The comparator refuses missing, failed, stale, or incompatible capability receipts before
reporting output drift. It also refuses two evaluations whose `converterSHA256` differs unless
`--allow-different-converters` is passed: a before/after comparison of two builds must say so,
so a shared `.build/release/pdf-reflow` rebuilt between runs cannot pass as run-to-run drift
(the likely cause of #68's unreproduced report). The evaluator hashes the converter again after
conversion and fails the run if it changed; the corpus runner stops if the binary changes
between cases.

The binary is not the whole OCR identity (#94). Vision compiles its document models into a
cache keyed by the converter's *file name*, separate compiles can transcribe the same page
differently, and every later process of that name reuses the cached programs (Vision recompiles
them when, for example, a different binary of that name runs). So `.build/release/pdf-reflow`
in every worktree, and a same-name copy anywhere, share one cache, while a renamed copy
(`pdf-reflow-394147f`) draws its own compile. No Vision option removes this.

Every evaluation receipt records `visionModelCache`: the mode, and before and after conversion
the executable name and a fingerprint of the compiled programs (per-compile `model.anehash`
files excluded). `--fresh-vision-cache` (evaluator and corpus runner) launches a run-unique copy
(`<name>-<run id>`) that compiles into an empty cache, removed after the run, so the run is
isolated from other processes and builds of the same name; it costs model compilation on every
recognized book (Census: about 60 s instead of 5 s with a cached compile, at load 13–19) and is
still one draw, not a reproducible transcription. The comparator
lists changed pages that are OCR pages in both runs as `changedOCRPages` and adds an `ocrCaveat`
unless both receipts record identical programs: such changes do not show a converter change by
themselves. Identical programs make them genuine; differing fingerprints do not prove a
different transcription, since output-equivalent compiles also differ in bytes. For a
before/after decision on an OCR book, review the text of `changedOCRPages` or repeat each side.

Which pages the #116 band retry recovers is part of that draw, not run-to-run noise: over
eleven fresh compiles of one binary, Blue Book page 6 was read five ways and retried under four
of the compiles, while compiles sharing a fingerprint always agreed (#140). So `--ocr always` output is
reproducible within a compile and not across compiles, and a retry-set difference between two
runs is evidence about the cache, not about the converter.

To test whether one binary repeats itself, use
[repeat-run identity](regression-testing.md#repeat-run-identity), not this comparator.

The comparator verifies the retained EPUB, probe JSON, and conversion report against their
evaluation receipt. Under compatible measured conditions it compares, page by page, the parsed
page record (text, headings, paragraphs, list items, notes, tables, sub/superscripts, note
links), the page's body markup (element types, heading levels, classes, inline styling, order),
the bytes of each image in order, and the report warnings for that page; plus source-page
markers, image assets, navigation entries, and conversion report fields. Generated output paths
and ZIP timestamps/identifiers are not drift; clients needing identical bytes can pin both
([reproducible packages](conversion-options.md#reproducible-packages)). A changed EPUB hash is
permitted between runs, but each EPUB must match its own receipt. Exit status is 0 only for
compatible runs with no differences in this scope. Historical receipts without this evidence
must be recaptured; manually adding context labels cannot qualify them.

Identifiers the writer or inspector generates are not content, because one earlier change
shifts all of them (#92). Before pages are compared:

- book-wide paragraph and `pre` ordinals become, per block, whether it continues from the
  previous page and onto the next, so splitting or joining a block across a marker still counts;
- element ids lose their numbers (`heading-8-2`, `note-c3-4`, `noteref-c3-4` become
  `heading-#-#`, `note-c#-#`, `noteref-c#-#`);
- note links, backlinks and in-book markup/navigation links name their target by page, masked
  id and (for note links) target text, not by `chapter-N.xhtml` file name, so a moved spine
  boundary is not a change but a link retargeted to another note is;
- `images/image-N` sources become the asset's SHA-256, so an added image does not change the
  pages of every later image, while a moved, swapped or re-encoded image still changes its pages.

The result lists `changedPages` with the differing normalized fields per page
(`changedPageFields`), `changedImages` (assets whose bytes have no counterpart in the other run),
`navigationChanged`/`changedNavigationPages`, `pageMarkersEqual` and `changedReportFields`.
Informational, not drift: `idOnlyShifts` counts pages whose raw records differ only in generated
identifiers (by raw field, plus navigation entries whose target id changed) and `imageRenames`
counts assets with identical bytes under another name; `--detail` lists both. A warning with a
`page` also appears in `changedReportFields` when it changes. Fed Explained and FAA evaluations
from `090cc70` and `394147f` report exactly Fed pages 8, 14, 66, 88 and 116 (14–116 lost a
`furnitureRemoved` warning) and FAA page 159, with 118 and 354 id-only pages; the same-binary
Fed repeat and the unchanged 9/11 pair (1,587 cross-file note links) pass with no shifts.

These local receipts provide consistency checks, not signed attestation. A page-1 probe samples
capability at one instant and cannot prove all pages or later service states equivalent. The
comparison does not cover every EPUB semantic detail (for example CSS, package metadata, and
navigation list nesting), decoded image equivalence, or visual fidelity. Keep the existing content, resource,
EPUB, and human-review gates. Evaluations without `--environment-probe` retain their existing
gate behavior but are ineligible for strict comparison.

## Wallace algebra

*Beginning and Intermediate Algebra*, Tyler Wallace, copyright 2010. The supplied PDF is
2,183,036 bytes; its SHA-256 is
`856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678`.
Page 2 identifies [CC BY 3.0 Unported](https://creativecommons.org/licenses/by/3.0/) and the
[author's website](http://wallace.ccfaculty.org/book/book.html). The owner-supplied original is pinned alongside an owner-provided MyOpenMath download URL.
That download is checked against the same identity.
The local PDF is unmodified and is not covered by the library's MIT license. Retain the author,
title, license and source attribution in shared derivatives and identify modifications.

Fetch the source as above, or pass another local path containing the same bytes. From the
repository root, with full Xcode selected and Python 3.11+ available:

```sh
swift build -c release
python3 tools/evaluate-real-document.py --case wallace-algebra-2010 \
  --pdf corpus/cache/Beginning_and_Intermediate_Algebra.pdf --converter .build/release/pdf-reflow \
  --output /tmp/wallace-baseline --epubcheck /opt/homebrew/bin/epubcheck
scripts/compare-pdf-reflow.sh --pdf corpus/cache/Beginning_and_Intermediate_Algebra.pdf \
  --pages 2,12,16,119,266,293,343,347,438,479,483 --output /tmp/wallace-review --serve
```

Output directories must be new. `--epubcheck` is optional. The memory runner enforces the
case's ceiling automatically. `scripts/check-all.sh --corpus` includes algebra in the corpus gate.

[Review points](../corpus/wallace-algebra-2010-review.json) list physical PDF pages and
acceptance questions. Page 343's inline squared exponent has superscript semantics, while
displayed mathematics remains in images; see [current regressions](../measurements/three-fidelity-fixes/record.md).
Each exercise or answer whose value is a fraction is one preserved region carrying its own number,
and a displayed row is never split between a crop and flattened text
([evidence](../measurements/split-display-rows/record.md)); semantic exercise lists and
column-major answer-key order remain unqualified.
[Baseline and visual evidence](../measurements/wallace-algebra-2010/record.md) separate valid
EPUB packaging from accurate mathematical content.


## Warren Commission report

The owner-supplied 1964 report contains 920 scanned pages with a separate text layer and no
structure tags. Its identity is pinned at 81,216,909 bytes, SHA-256
`341cc3471750c9c3be68b95a34b52f6cbdc86c4392427a8483ee1c6bc53cfc19`.
[GovInfo's publisher page](https://www.govinfo.gov/features/warren-commission-report-and-hearings)
identifies the report and links its official PDF. The pinned identity comes from the
owner-supplied original. The PDF is external development material, not bundled or relicensed
under MIT; the owner confirms commercial use and redistribution.

```sh
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate-real-document.py --case gpo-warren-1964 \
  --pdf corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/warren-baseline --epubcheck /opt/homebrew/bin/epubcheck
```

The default-budget baseline exits unsuccessfully after reconstruction page 436 of 920 when
page-image output exceeds 512 MiB (page 390 before written rasters
[stopped carrying a constant alpha plane](../measurements/opaque-page-rasters/record.md)). The
whole book needs 1,114,310,156 entry bytes as PNG, 2.08× the default, and 537,220,320 — still
349,408 bytes over — when each image takes the smaller of PNG and JPEG 0.90, which is the best any
per-image encoding choice can do at that quality. Its 910 full-page references are colour scans,
and 512 MiB over 920 pages is 583 KiB a page. What is left is a policy decision about default
encoding, raster DPI, or references on books where nearly every page is unverified, not a
measurement. The measurement runner retains the failure and memory/progress evidence. A
[full-book encoding experiment](../measurements/warren-image-encoding/record.md)
completes with an explicit 2 GiB experimental override; the default-budget gate remains unresolved.
The [production client-policy runs](../measurements/client-options/record.md) also complete all
920 pages, with JPEG references or with supplementary references omitted, under explicit final
EPUB caps. Both validate; source-layer fidelity and physical-device memory remain unqualified. There is no case memory ceiling yet;
do not treat a failed run as successful resource qualification or raise limits just to pass.

A bounded nine-page excerpt permits visual diagnosis while full conversion is blocked:

```sh
python3 measurements/gpo-warren-1964/prepare-excerpt.py \
  --pdf corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf --output /tmp/warren-excerpt.pdf
scripts/compare-pdf-reflow.sh --pdf /tmp/warren-excerpt.pdf \
  --pages all --output /tmp/warren-review --serve
```

Excerpt preparation requires the development-only `pypdf` package (measured with 6.10.0).
All output paths must be new. The excerpt's page numbers 1-9 map to original physical pages
1, 7, 21, 30, 50, 100, 890, 910 and 920. It loses whole-book context, so its results cannot
qualify the full document. Both Poppler previews use relative image URLs with
[real-tool regression coverage](../measurements/poppler-relative-images/record.md).
The original-page pane remains the visual reference.

[Review points](../corpus/gpo-warren-1964-review.json) and
[measurement evidence](../measurements/gpo-warren-1964/record.md) record OCR and column-order defects. Synthetic OCR font classification is addressed by the
[fraction and invisible-text checks](../measurements/fractions-and-invisible-text/record.md):
ordinary invisible Courier prose no longer becomes code, and OCR font geometry does not create
headings. True heading recovery and index grouping remain unqualified. The [excerpt check](../measurements/quality-and-raster-fixes/record.md)
excludes placeholders and counts seven reflowed pages, preserving the two textless pages as
images. The excerpt passes EPUBCheck but is not fidelity-qualified. This case exercises trust in an existing OCR layer as well as
new recognition: the default full run attempts fresh OCR on only one page.

Tracked defects: [full-book resource limit](https://github.com/vocaro/PDFReflowLib/issues/5),
[OCR font/layout inference](https://github.com/vocaro/PDFReflowLib/issues/6),
[text-layer quality](https://github.com/vocaro/PDFReflowLib/issues/7),
[placeholder text/counts](https://github.com/vocaro/PDFReflowLib/issues/8), and
[Poppler image URLs](https://github.com/vocaro/PDFReflowLib/issues/9). Additional source-derived
examples are linked from the existing reading-order and memory investigations.


## 9/11 Commission report

The owner-supplied 2004 full report is a 585-page digital original with no structure tags.
[GovInfo](https://www.govinfo.gov/features/911-commission-report) identifies the official
edition and links the PDF. Local bytes are pinned at 2,475,163 bytes, SHA-256
`657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b`.
This is external development material, with owner-confirmed commercial use and redistribution;
the library MIT license does not relicense the document.

```sh
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate-real-document.py --case gpo-911-2004 \
  --pdf corpus/cache/GPO-911REPORT.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/911-baseline --epubcheck /opt/homebrew/bin/epubcheck
scripts/compare-pdf-reflow.sh --pdf corpus/cache/GPO-911REPORT.pdf \
  --pages 15,19,20,21,22,65,66,471,472,584 --output /tmp/911-review --serve
```

Output directories must be new. The full run passes the 256 MiB Mac RSS ceiling and EPUBCheck,
but header and note fidelity remain unqualified. The PDF permits copying/printing despite
permissions encryption and opens without a password prompt; the source is not rewritten.
Its metadata title is a print-job filename; set `ConversionOptions.title` for a reader-facing
title. [Review points](../corpus/gpo-911-2004-review.json) and
[baseline evidence](../measurements/gpo-911-2004/record.md) distinguish successful word-spacing
examples from retained headers, false notes headings and flattened note markers.

[Issue #10](https://github.com/vocaro/PDFReflowLib/issues/10) parks the heading investigation.
The owner's 46/54 figure comes from a separate Claude ALL-CAPS prototype, not PDFReflowLib:
46 candidates were headers, 50 were non-headings overall, and four were genuine. Its sample
uses a Chapter 1 granule with a different identity. Those reported counts are preserved with
provenance, not promoted to independently reproduced library measurements.

[Issue #11](https://github.com/vocaro/PDFReflowLib/issues/11) tracks note-marker semantics,
number/text associations and future endnote linking; full note coverage remains unqualified.


## The Fed Explained

The 135-page eleventh edition (August 2021) is a tagged Federal Reserve Board publication.
Its structure tree contains table, figure and heading roles, including figure alternate text.
Current reconstruction uses spatial extraction rather than those semantic tags. Difficult
regions remain raster images with warnings; diagrams are not rebuilt as editable vector graphs.

```sh
python3 tools/fetch_corpus.py --case fed-explained-2021
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate-real-document.py --case fed-explained-2021 \
  --pdf corpus/cache/the-fed-explained.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/fed-baseline --epubcheck /opt/homebrew/bin/epubcheck
scripts/compare-pdf-reflow.sh --pdf corpus/cache/the-fed-explained.pdf \
  --pages 9,17,20,45,46,51,82,83,120,121 --output /tmp/fed-review --serve
```

[Review points](../corpus/fed-explained-2021-review.json) cover tables, organization charts,
flow arrows and adjacent prose. The [baseline](../measurements/fed-explained-2021/record.md)
passes EPUB validation and the Mac memory gate. Spot checks expose undersized whole-page
fallback and ordinary prose rendered as headings. Full-book fidelity remains unqualified.


## Dietary Guidelines for Americans, 2025–2030

The 10-page InDesign booklet combines food illustrations, gradient section headings, bullet
columns and full-width callouts. The supplied source is pinned separately from any publisher
accessibility revision. Its direct CDN download matches the original bytes.

```sh
python3 tools/fetch_corpus.py --case dga-2025-2030
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate-real-document.py --case dga-2025-2030 \
  --pdf corpus/cache/DGA.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/dga-baseline --epubcheck /opt/homebrew/bin/epubcheck
scripts/compare-pdf-reflow.sh --pdf corpus/cache/DGA.pdf \
  --pages all --output /tmp/dga-review --serve
```

All ten pages are small enough to prepare together. [Review points](../corpus/dga-2025-2030-review.json)
and the [baseline](../measurements/dga-2025-2030/record.md) distinguish valid EPUB packaging from
usable reflow. The [shading-support measurement](../measurements/shading-support/record.md)
records nine pages with reflowed text before placeholder filtering; column-order defects remain
open. The source has tags, but custom heading and bullet roles map to paragraphs, so tag names alone are not a reliable semantic reference.
[Graphics fallback #13](https://github.com/vocaro/PDFReflowLib/issues/13) and
[native text/label defects #14](https://github.com/vocaro/PDFReflowLib/issues/14) track the gaps.


## Fifth National Climate Assessment

The NOAA-hosted full report is 219,876,258 bytes and 1,834 pages, close to the converter's
256 MiB / 2,000-page input limits. Its [chapter reference](../corpus/noaa-nca5-2023-chapters.json)
records 32 numbered chapters from PDF bookmarks. [Review points](../corpus/noaa-nca5-2023-review.json)
span chapter boundaries, charts, the landscape/portrait transition and late-book pages.

```sh
python3 tools/fetch_corpus.py --case noaa-nca5-2023
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate-real-document.py --case noaa-nca5-2023 \
  --pdf corpus/cache/noaa_61592_DS1.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/noaa-baseline --timeout 900 --epubcheck /opt/homebrew/bin/epubcheck
```

The publisher endpoint currently returns HTTP 403 to automated downloads. Place the exact
supplied/downloaded original in the indicated cache; the same fetch command verifies it offline.
A failed fresh fetch returns nonzero and does not create a substitute. The original matches
NOAA's published SHA-512 as well as the manifest's SHA-256. NOAA declares CC0/Public Domain.

The full report now converts under library defaults and is gated in the corpus lane. Two earlier
changes and one made for it moved the book across the 512 MiB entry budget: #151 stopped its
15,098 links forcing a page image, which removed 803 references and carried the default run from
reconstruction page 599 to 1,727 of 1,834; then written page rasters
[stopped carrying their constant alpha plane](../measurements/opaque-page-rasters/record.md),
taking the book to 510,379,982 entry bytes, 25.26 MiB under the budget. The published EPUB is
502,665,496 bytes with 1,548 images, of which 62 are source-page references for the chapter
covers, whose full-bleed artwork exists nowhere else in the output. Conversion takes about 121
seconds and peaks at 920–978 MiB resident against the 1,280 MiB case ceiling, so NOAA costs a full
corpus run about two minutes and half a gigabyte of transient output. The contract covers review
pages 1, 33, 48, 80, 139, 900, 1700 and 1834, read against source renders: chapter covers keep
their page image, ordinary illustrated pages must not fall back to one, and page 1834's agency
seals stay an image under `pageImageFallback`. Headroom is 4.9%, so a change that adds image bytes
to this book will fail this gate.

The [earlier full-run baseline](../measurements/noaa-nca5-2023/record.md) and the
[explicit-policy comparison](../measurements/noaa-output-policies/record.md), which completed all
1,834 pages under 4 GiB experimental caps with PNG or JPEG 0.90 full pages, remain the record of
how the book behaved before those changes. Broad fidelity is still unqualified:
[issue #181](https://github.com/vocaro/PDFReflowLib/issues/181) records the text trapped inside
page 48's figure crop and the contributor lines fused into one paragraph, both visible in the
reviewed pages and neither approved by the contract. No physical-device storage or memory budget is established.
[Chapter-aware splitting issue #15](https://github.com/vocaro/PDFReflowLib/issues/15) remains open;
the current writer's approximate 60,000-byte file splitting does not follow PDF chapters or bound
the memory of whole-document reconstruction.


## Our Flag

The 56-page House Document 108-97 is a quick illustrated baseline. Its populated structure tree
coexists with MarkInfo.Marked=false; it has heading and figure roles but no table roles or
figure alternate text. The converter does not currently consume the tree. Correct visual output
alone cannot prove tag use, and this source is not a fully validated semantic reference.

```sh
python3 tools/fetch_corpus.py --case gpo-our-flag-2003
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate-real-document.py --case gpo-our-flag-2003 \
  --pdf corpus/cache/CDOC-108hdoc97.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/our-flag-baseline --epubcheck /opt/homebrew/bin/epubcheck
scripts/compare-pdf-reflow.sh --pdf corpus/cache/CDOC-108hdoc97.pdf \
  --pages 7,15,22,27,32,33,41,48 --output /tmp/our-flag-review --serve
```

The [baseline](../measurements/gpo-our-flag-2003/record.md) passes full conversion, EPUBCheck,
progress and the 192 MiB Mac RSS gate. [Review references](../corpus/gpo-our-flag-2003-review.json)
include all ten table rows and meaning-bearing flag groups. The page-27 table retains both
headers and all rows in a warned region image; see [current evidence](../measurements/three-fidelity-fixes/record.md).
Drop-cap ordering and general figure/name/description association remain unqualified under
[heading classification #12](https://github.com/vocaro/PDFReflowLib/issues/12) and
[validated structure #17](https://github.com/vocaro/PDFReflowLib/issues/17).


## Preparedness 101: Zombie Pandemic

The CDC graphic novel tests dialogue embedded in artwork, damaged existing extraction and
panel reading order. The publisher declares Public Domain and supplies a SHA-512 matching the
owner's PDF. The automated endpoint returns HTTP 403; manually place the original in
`corpus/cache/cdc_6023_DS1.pdf`. The fetch command verifies that cached identity offline.

```sh
python3 tools/fetch_corpus.py --case cdc-zombie-pandemic-2011
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate-real-document.py --case cdc-zombie-pandemic-2011 \
  --pdf corpus/cache/cdc_6023_DS1.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/cdc-comic-baseline --epubcheck /opt/homebrew/bin/epubcheck
scripts/compare-pdf-reflow.sh --pdf corpus/cache/cdc_6023_DS1.pdf \
  --pages 3,5,13,16,21,37,39 --output /tmp/cdc-comic-review --serve
```

The [baseline](../measurements/cdc-zombie-pandemic-2011/record.md) passes EPUB validity,
progress and the 512 MiB Mac RSS gate, retaining 42 page images. The
[review targets](../corpus/cdc-zombie-pandemic-2011-review.json) expose damaged existing dialogue
on page 5 and fresh-OCR panel-order failure on page 13. [Suspect text #7](https://github.com/vocaro/PDFReflowLib/issues/7)
and [comic grouping #18](https://github.com/vocaro/PDFReflowLib/issues/18) track those gaps. Since
[#93](../measurements/text-layer-plausibility/record.md) the damaged layer on 27 pages fails the
plausibility test and is replaced by OCR under the default policy, each page reporting
`implausibleTextLayer`: dialogue units with reflowed text rise from about 124 to 222 of 231.
The measured 3,341 extracted whitespace tokens include OCR noise; they are not dialogue coverage.


## Project Blue Book Special Report No. 14

This 312-page typewritten/handwritten scan is a negative quality-signaling case. Its inherited
OCR and figure-only structure tree do not establish usable table semantics. The supplied release
copy remains in the ignored cache; automatic publisher download returns HTTP 403. The fetcher
verifies the exact supplied identity when the cache is manually seeded.

```sh
python3 tools/fetch_corpus.py --case cia-blue-book-14-1955
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate-real-document.py --case cia-blue-book-14-1955 \
  --pdf corpus/cache/CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf \
  --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/blue-book-baseline --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/check_corpus_quality.py --case cia-blue-book-14-1955 \
  --evaluation /tmp/blue-book-baseline
```

The converter now emits `unverifiedTextLayer` on pages with existing text over a page-sized
image, `damagedTextEncoding` on born-digital pages whose fonts lack a usable Unicode mapping
and whose words fail the embedded English statistics (Census pages 2, 4–16 and 18–20;
pages 3 and 17 decode natively since #143), and `implausibleTextLayer` on image-backed pages whose
inherited text fails the #93 plausibility test (none of the Blue Book's pages: its tables are
exempt through their digits).
The [current measurement](../measurements/quality-and-raster-fixes/record.md) checks pages
74 and 150 separately from the [historical failing baseline](../measurements/cia-blue-book-14-1955/record.md).
Crashes, timeouts, resource failures and generic image-preservation warnings do not satisfy it. No production quality-refusal
error exists yet; the manifest's approved diagnostic list is empty. Future dedicated quality
warnings/refusals need explicit semantics and matching contract entries. The present warning
asks the client to review transcription, tables, numbers and order against the preserved source;
it does not assert that an individual cell is wrong.

[Review references](../corpus/cia-blue-book-14-1955-review.json) include the typewritten table's
printed rows and handwritten-sheet review targets. [Issue #19](https://github.com/vocaro/PDFReflowLib/issues/19)
tracks the warning/refusal behavior; passing the signal contract will not establish correct cells.


## Issue #30 coverage expansion

Seven small public-domain or CC BY sources add layouts the earlier corpus lacked. All fetch
directly and verify by byte count and SHA-256. Each has a baseline record, review targets and a
reviewed content contract that checks only source-verified output; every one also exposes
defects tracked as separate issues rather than blessed as golden output.

```sh
python3 tools/fetch_corpus.py --case usgs-mcs2025-copper   # or any case below
swift build -c release --scratch-path .build/corpus-cli
python3 tools/run_corpus_regressions.py --converter .build/corpus-cli/out/Products/Release/pdf-reflow \
  --epubcheck /opt/homebrew/bin/epubcheck --output /tmp/corpus-30 \
  --case usgs-mcs2025-copper --case scotus-loper-bright-2024 --case census-rrs2002-01 \
  --case uscis-m618-arabic-2015 --case irs-p596-zhs-2025 --case nbs-jres-geltman-1977 \
  --case arxiv-replay-clocks-2023
```

| Case | Gap | Baseline finding | Tracking |
| --- | --- | --- | --- |
| [`usgs-mcs2025-copper`](../measurements/usgs-mcs2025-copper/record.md) | Borderless tables | Tables preserved as readable crops, but adjacent prose is absorbed into them | [#36](https://github.com/vocaro/PDFReflowLib/issues/36) |
| [`scotus-loper-bright-2024`](../measurements/scotus-loper-bright-2024/record.md) | Page-bottom footnotes | Text complete; footnotes merge into body paragraphs; 75 citation-leading lines become preformatted | [#40](https://github.com/vocaro/PDFReflowLib/issues/40), [#39](https://github.com/vocaro/PDFReflowLib/issues/39) |
| [`census-rrs2002-01`](../measurements/census-rrs2002-01/record.md) | Damaged encoding | Resolved: shifted-letter pages report `damagedTextEncoding`, keep a source image and are recognized by default ([evidence](../measurements/damaged-text-encoding/record.md)); pages set only in the EC text fonts decode natively ([evidence](../measurements/glyph-index-decoding/record.md)) | [#38](https://github.com/vocaro/PDFReflowLib/issues/38), [#143](https://github.com/vocaro/PDFReflowLib/issues/143) |
| [`uscis-m618-arabic-2015`](../measurements/uscis-m618-arabic-2015/record.md) | Right-to-left script | Arabic words correct; mixed-direction runs fragment and reverse | [#41](https://github.com/vocaro/PDFReflowLib/issues/41) |
| [`irs-p596-zhs-2025`](../measurements/irs-p596-zhs-2025/record.md) | CJK script | Order and amounts correct; spaces inserted inside CJK; some columns rasterized | [#42](https://github.com/vocaro/PDFReflowLib/issues/42), [#36](https://github.com/vocaro/PDFReflowLib/issues/36) |
| [`nbs-jres-geltman-1977`](../measurements/nbs-jres-geltman-1977/record.md) | Scanned two-column paper | Inline images force page fallback on pages 1–6 | [#37](https://github.com/vocaro/PDFReflowLib/issues/37) |
| [`arxiv-replay-clocks-2023`](../measurements/arxiv-replay-clocks-2023/record.md) | Born-digital ACM paper | Prose order correct; front-matter headings, section labels and math spacing wrong | [#43](https://github.com/vocaro/PDFReflowLib/issues/43) |

The NBS paper stands in for an owner-supplied, ACM-copyrighted Lamport CACM article in the same
two-column scanned format. Replay Clocks is CC BY 4.0: retain the attribution recorded in the
manifest. USCIS states some guide images are licensed, so that case commits no page rasters.
Vertical CJK, Hebrew and Devanagari layouts remain uncovered for lack of clearly licensed sources
([#44](https://github.com/vocaro/PDFReflowLib/issues/44)).


## Complaint for a Civil Case (Pro Se 1)

The US Courts form Pro Se 1 (Rev. 12/16), effective December 1, 2016, is a five-page fillable
AcroForm: 77 fields (68 text, 1 choice, 8 buttons including Print, Save As..., Add Attachment and
Reset), no XFA, untagged, distilled from WordPerfect with mostly unembedded Times fonts. It mixes
numbered instruction prose with stacked field labels, fill-in sentences broken by blank rules,
checkboxes and a two-block court caption. The download URL is not versioned; bytes are pinned at
1,054,771, SHA-256 `9fe218570d311b0deab9413e39efda41210e60f2a5221eb360d43912ce05a118`.

The form was prepared by the Administrative Office of the U.S. Courts and is a work of the United
States Government (17 U.S.C. 105). Neither the PDF nor its
[uscourts.gov page](https://www.uscourts.gov/forms-rules/forms/complaint-a-civil-case) carries a
copyright notice or a third-party credit, and it contains no raster images. The owner approved it
on 2026-09-17. It is not relicensed under MIT; retain the attribution recorded in the manifest.

```sh
python3 tools/fetch_corpus.py --case uscourts-pro-se-1-2016
swift build -c release
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck /opt/homebrew/bin/epubcheck --output /tmp/pro-se-1 --case uscourts-pro-se-1-2016
```

The run passes EPUBCheck, progress and the 128 MiB Mac RSS gate (64 MiB peak). The
[review points](../corpus/uscourts-pro-se-1-2016-review.json) cover all five pages. The
contract holds 162 checks: headings, caption and field-label order, whole instruction
paragraphs, the running header's removal, the page-5 push buttons kept out of the text, and no
page recognized, called damaged or implausible, or dropped to a whole-page image.
The empty widgets, unchecked boxes and push buttons show nothing beyond the printed page, so no page
gets a source-page image; each page warns that its form fields are not interactive, and the box
glyphs under the checkbox widgets read `☐` ([#151](https://github.com/vocaro/PDFReflowLib/issues/151)).
Other defects: stacked labels run together into one paragraph, fill-in sentences break apart at
each blank, section labels are split or set as `<pre>`, one paragraph splits mid-line, and the
`Page N of 5` folio stays in the text ([#152](https://github.com/vocaro/PDFReflowLib/issues/152)).
A period after a blank becomes a subscript ([#144](https://github.com/vocaro/PDFReflowLib/issues/144)).
No region references are committed: the form has no images, only rules and boxes.


## Ground wind loads paper (Word 2013)

Ivanco, Keller and Pinkerton, "Investigation of Atmospheric Boundary-Layer Effects on
Launch-Vehicle Ground Wind Loads" (2020 IEEE Aerospace Conference), is a 20-page Microsoft Word
2013 export from [NTRS 20200002975](https://ntrs.nasa.gov/citations/20200002975). It is tagged
with Word's structure tree, set in the IEEE two-column template with a table of contents, and has
27 figure rasters, an OMML equation, Symbol-font Greek letters and bullets, references and author
portraits. Five of its twelve fonts are not embedded. Bytes are pinned at 3,268,329, SHA-256
`a98e4fcdea40b8ea7023880dd88966f04198b4ec311fced0bb9ebb2dec45fe6d`. NTRS returned HTTP 503 for
a few minutes during capture. The fetcher fails in that case and never substitutes a file.

Page 1 states "U.S. Government work not protected by U.S. copyright", and the byline and the NTRS
record place all three authors at NASA Langley Research Center. The NTRS API copyright record
gives `GOV_PUBLIC_USE_PERMITTED` with `containsThirdPartyMaterial: false`. No figure or photo
carries a third-party credit, and no NASA insignia is visible in the figures. The page-20 author
portraits carry no credit at all, so no crops or rasters of page 20 may be committed. The case
commits no rasters from any page. The owner approved it on 2026-09-17. It is not relicensed under
MIT; retain the attribution recorded in the manifest.

```sh
python3 tools/fetch_corpus.py --case ntrs-20200002975-gwl-2020
swift build -c release
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck /opt/homebrew/bin/epubcheck --output /tmp/ntrs-gwl --case ntrs-20200002975-gwl-2020
```

The run passes EPUBCheck, progress and the 256 MiB Mac RSS gate (127–129 MiB peak). The
[review points](../corpus/ntrs-20200002975-gwl-2020-review.json) cover all 20 pages. The
contract holds 285 checks, all on output that matches the source: headings, pages 3, 4, 6 and 12
where the columns read in order, figure presence and captions, the `V_ref` subscript and the
Reynolds-number exponents, the paragraph continuing from page 9 through the top of figure page 10,
the appendix captions, each standing directly beneath its plot, reference order and the
biographies; and, on every page, no source-page image and no recognition, damaged-encoding,
implausible-layer, unverified-layer or page-image-fallback warning. Pages 1–12 and 19 report
`structureFallback`. Where columns sit side by side, on pages 1, 2, 5 and 8–11, the prose
interleaves line by line, pages 7 and 8 read right-column blocks first, and the figures on pages
10–11 are out of order ([#153](https://github.com/vocaro/PDFReflowLib/issues/153)). Section titles
2–6 are `<pre>`, folios are kept or made headings, and references become headings
([#154](https://github.com/vocaro/PDFReflowLib/issues/154)). Symbol-font α and bullets stay as
private-use characters, and `45-degree` loses its hyphen
([#155](https://github.com/vocaro/PDFReflowLib/issues/155)). The invisible table-of-contents links on
page 1 add no source-page image, only a warning ([#151](https://github.com/vocaro/PDFReflowLib/issues/151)).


## Agricultural Research magazine (InDesign)

*Agricultural Research* Vol. 60, No. 10 (November/December 2012), from the USDA Agricultural
Research Service, is a 24-page Adobe InDesign CS5 magazine, untagged, from the
[issue's contents page](https://agresearchmag.ars.usda.gov/2012/nov/?t=tableofcontent). It has a
cover, a Forum column, a masthead with contents, an 11-page feature, four short articles and a
two-page index. The layout uses two- and three-column justified text with wrapped photos, boxed
sidebars, colored pull quotes, a full-page background image, display titles, drop caps, rotated
photo credits, "See story on page N" cross-references and a back-cover mailing panel. Twelve
standard Arial and Times fonts are not embedded, and there are 55 link annotations. The download
URL is not versioned, so bytes are pinned at 9,329,928, SHA-256
`2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761`.

The page-3 masthead says "Most information in this magazine is public property and may be
reprinted without permission (except where copyright is noted)". No copyright notice appears in
the issue. All masthead staff and article bylines are ARS employees (17 U.S.C. 105). All 24 printed
photo numbers resolve in the ARS Image Gallery to the credited photographers. The gallery's
[rights page](https://www.ars.usda.gov/oc/images/copyright/) calls its photos copyright-free and
public domain, asks for credit to the Agricultural Research Service, and forbids using them to
imply ARS endorsement; the masthead also disclaims USDA endorsement. Page 24 holds only the USDA,
ARS and 150 Years marks and the mailing panel. No raster or crop of page 24 may be committed, and
the case commits no rasters from any page. The owner approved it on 2026-09-17. It is not
relicensed under MIT; retain the attribution recorded in the manifest.

```sh
python3 tools/fetch_corpus.py --case usda-ars-agresearch-2012-11
swift build -c release
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck /opt/homebrew/bin/epubcheck --output /tmp/ag-research --case usda-ars-agresearch-2012-11
```

The run passes EPUBCheck, progress and the 512 MiB Mac RSS gate (276–314 MiB peak). The
[review points](../corpus/usda-ars-agresearch-2012-11-review.json) cover all 24 pages. The
contract holds 164 checks on all 24 pages, all on output that matches the source: the cover lines
and headings, the masthead date lines, photo presence and printed credits, whole captions on pages
6, 9 and 12, reflowed sentences in source order on pages 6, 9, 12, 13, 15, 18 and 19, the
back-cover mailing instruction, and, on every page, no recognition, damaged-encoding or
implausible-layer warning, with the whole-page fallback confined to pages 20–21 and the
source-page image to pages 1 and 13. Pages 14, 22 and 23 hold their preserved regions and that
disclosure only: #158 keeps all of their body text inside crops, so no reflowed text is pinned.

Most of the text does not reflow. The EPUB carries 29,882 of about 83,400 source characters, and
no article title reaches the contents:
- The Forum column, masthead, contents, pull quotes, sidebars, most feature pages and the index
  stay inside region crops, and pages 20–21 fall back to whole-page images
  ([#158](https://github.com/vocaro/PDFReflowLib/issues/158)).
- Side-by-side columns come out one line per paragraph and interleave, or read right-column
  blocks first ([#153](https://github.com/vocaro/PDFReflowLib/issues/153)).
- The running foot is kept with its bullet as a superscript `l`, and end-of-story marks are
  tripled. Subheads are not headings, paragraphs merge, and the mailing panel becomes
  headings ([#159](https://github.com/vocaro/PDFReflowLib/issues/159)).


## Arrival scheduling paper (pdfTeX IEEEtran)

Sadovsky and Windhorst, "A Scheduling Algorithm Compatible with a Distributed Management of
Arrivals in the National Airspace System" (2019 IEEE/AIAA Digital Avionics Systems Conference), is
a 10-page pdfTeX IEEEtran paper from [NTRS 20190030725](https://ntrs.nasa.gov/citations/20190030725).
It is untagged. Section headings are IEEE small-caps Roman numerals. The math is Computer Modern
without ToUnicode: inline symbols with stacked indices, numbered displays with cases braces, and
matrices. It also has an algorithm step list, bullets, time-window figures, rotated schedule tables
with networkx route plots, a ruled outline table, footnotes and references. Bytes are pinned at
384,479, SHA-256 `7c2137098ffb75153e0049b970272db97bc91e13168028dc7b53fbe2deb92caa`. NTRS
returned HTTP 503 for about 50 minutes during capture. The fetcher fails in that case and never
substitutes a file.

The byline and the NTRS record place both authors at NASA Ames Research Center (17 U.S.C. 105).
The NTRS API copyright record gives `GOV_PUBLIC_USE_PERMITTED` with
`containsThirdPartyMaterial: false`. The PDF itself has no copyright notice or government-work
statement. No figure or table carries a credit. The figures are the authors' own plots, and the
route networks are generated from the paper's sample problems. No insignia or photographs appear.
The case commits no rasters. The owner approved it on 2026-09-17. It is not relicensed under MIT;
retain the attribution recorded in the manifest.

```sh
python3 tools/fetch_corpus.py --case ntrs-20190030725-dasc-2019
swift build -c release
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck /opt/homebrew/bin/epubcheck --output /tmp/ntrs-dasc --case ntrs-20190030725-dasc-2019
```

The run passes EPUBCheck, progress and the 128 MiB Mac RSS gate (49–51 MiB peak). The
[review points](../corpus/ntrs-20190030725-dasc-2019-review.json) cover all 10 pages. The contract
holds 208 checks, all on output that matches the source: the title heading, author blocks,
abstract and index terms, whole prose paragraphs in column order, the page 1 to 2 continuation,
the order of section, step, bullet and requirement openings, separate dash items, figure, table and display crops,
captions (Fig. 1 beneath its figure, TABLE I and TABLE III above their tables), footnote text and
reference order; and, on every page, no source-page image and no recognition, damaged-encoding,
implausible-layer, unverified-layer, structure-fallback or page-image-fallback warning.

The paper reflows with no structure fallbacks, but these defects remain:
- The title is the only heading. Section and appendix headings are `<p>` or `<pre>`, and
  subsection titles swallow their first line. Bullets and requirements are `<pre>`, and steps and
  references split after their first line. Paragraphs split at a column break and at a footnote
  ([#162](https://github.com/vocaro/PDFReflowLib/issues/162)).
- Symbols with stacked indices shatter their sentences into one-token paragraphs. Several
  displays are partly cropped and partly loose text, with 146 private-use brace pieces. The
  separation-matrix crop swallows two prose lines
  ([#163](https://github.com/vocaro/PDFReflowLib/issues/163)).
- The Figure 2 caption, page 9's appendices and the Table III caption are out of column order
  ([#153](https://github.com/vocaro/PDFReflowLib/issues/153)).


## Earthdata Cloud Analytics slides (Google Slides)

Lynnes and Ramachandran, "Earthdata Cloud Analytics Project", is a 21-slide Google Slides export
from [NTRS 20180003024](https://ntrs.nasa.gov/citations/20180003024), presented at the CEOS WGISS
meeting in April 2018. Its only producer mark is the Creator `Google`, and there is no Producer. The
file is untagged, with 720×405 pt slides and embedded Arial and Verdana with ToUnicode. The slides
have titles, numbered lists with lettered sub-items, diagrams built from shapes and text boxes on a
full-bleed background fill, a repeated slide footnote, chart rasters and a question slide with no
text layer. There are no speaker notes. Bytes are pinned at 510,231, SHA-256
`f0a1ea3f5711228a9de2544fd1a94b05cfb8d9323fe3a4c253542f5a6ead5c94`.

Slide 1 marks both presenters "U.S. Civil Servant", and the NTRS record places them at NASA Goddard
and NASA Marshall. The NTRS API copyright record gives `GOV_PUBLIC_USE_PERMITTED` with
`containsThirdPartyMaterial: false`. Every slide was checked, and none shows an AWS, Google, partner
or vendor logo or a screenshot of a commercial product. Every slide does show the NASA insignia,
whose use 14 CFR 1221 restricts, so **no crop or raster of any slide may be committed**. Even with
the insignia masked, these slides stay excluded:

- slide 2, for its uncredited satellite renders and ground-station photo;
- slides 3–4, for their uncredited chart rasters;
- slides 12–21, for their uncredited icons.

Contract snippets quote only agency-authored slide text. The owner approved the deck on 2026-09-17.
It is not relicensed under MIT; retain the attribution recorded in the manifest.

```sh
python3 tools/fetch_corpus.py --case ntrs-20180003024-earthdata-slides-2018
swift build -c release
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck /opt/homebrew/bin/epubcheck --output /tmp/earthdata-slides \
  --case ntrs-20180003024-earthdata-slides-2018
```

The run passes EPUBCheck, progress and the 128 MiB Mac RSS gate (41 MiB peak). The
[review points](../corpus/ntrs-20180003024-earthdata-slides-2018-review.json) cover all 21 slides.
The contract holds 213 checks, all on output that matches the source:

- the title slide's heading and byline;
- the slide titles that are headings;
- each numbered item on slides 7–9 as one whole list item;
- line order on the title-less slides;
- the diagram box labels in pipeline order;
- the AODS superscript;
- image presence on slides 2–5;
- no slide recognized, called damaged or implausible, or dropped to a whole-page image.

Slide 5's question has no text layer, so only its image carries it; it is exempt from the
no-recognition assertion, because its text never reaches the EPUB at all
([#176](https://github.com/vocaro/PDFReflowLib/issues/176)). The known defects are:

- The full-bleed background counts as a page-sized graphic, so all 21 slides get
  `unverifiedTextLayer` and a source-page image
  ([#164](https://github.com/vocaro/PDFReflowLib/issues/164)).
- The titles of slides 2–4, 6 and 10 are paragraphs, two-line titles split in two, and the other
  titles mix h2, h3 and h4.
- The repeated slide footnote is removed as furniture on five slides.
- "Cumulus" is doubled, and on slides 19–20 the diagram boxes become h5/h6 with duplicated labels
  ([#165](https://github.com/vocaro/PDFReflowLib/issues/165)).


## Tank Health Monitoring (TechPort web print)

"Tank Health Monitoring" is a five-page print of a NASA TechPort project page, from
[NTRS 20210020887](https://ntrs.nasa.gov/citations/20210020887). Server-side Chromium printed it
through Skia/PDF m92 on 08/24/2021, and iText 5.5.13.2 then post-processed it. The file is untagged,
with embedded Open Sans and Verdana with ToUnicode. The web layout survives into the PDF:

- a dark header band with the NASA insignia;
- a main column with bullet lists;
- a shaded right sidebar with the photo, a dot-leader table of contents, organization, management
  and a TRL chart;
- HTML tables;
- an image gallery;
- Chromium's footer with "Printed on", the page URL and `Page N`.

It also has 27 borderless link annotations. The download filename contains spaces, so the cache
uses `THM-Close-Out-Report-and-Exec-Summ-for-STI-Review.pdf`. Bytes are pinned at 1,660,263,
SHA-256 `0fce4b68983ad8a216c8228ec44697c61ab41977ad41733c465ebebec3976ff0`.

The NTRS record lists the author, project manager Rudy Werlink of Kennedy Space Center, as a civil
servant. The NTRS API copyright record gives `GOV_PUBLIC_USE_PERMITTED` with
`containsThirdPartyMaterial: false`. Every page shows the NASA insignia (14 CFR 1221), so **no crop
or raster of any page may be committed**. With the header masked, pages 1 and 5 would still be
excluded:

- their uncredited lander and Gateway renders (the lander appears to be a commercial CLPS concept);
- on page 5, a slide screenshot that carries a second insignia.

The owner approved the document on 2026-09-17. It is not relicensed under MIT; retain the
attribution recorded in the manifest.

```sh
python3 tools/fetch_corpus.py --case ntrs-20210020887-techport-thm-2021
swift build -c release
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck /opt/homebrew/bin/epubcheck --output /tmp/techport-thm \
  --case ntrs-20210020887-techport-thm-2021
```

The run passes EPUBCheck, progress and the 128 MiB Mac RSS gate (61 MiB peak). The
[review points](../corpus/ntrs-20210020887-techport-thm-2021-review.json) cover all five pages. The
contract holds 64 checks, all on output that matches the source:

- the main-column headings;
- the Project Introduction paragraphs, whole and separate;
- every bullet item's text in order, including the nested items;
- the page-4 closeout and Figure 1 text, the caption standing directly beneath its diagram;
- image presence, including all three page-5 gallery pictures;
- every page warning that its links are not interactive, with no source-page image and no
  recognition, damaged-encoding, implausible-layer, unverified-layer or fallback warning.

The known defects are:

- The header band's title lines stay inside a crop with the insignia on every page. The sidebar
  panels, the page-4 tables and the page-5 gallery captions exist only as crops
  ([#166](https://github.com/vocaro/PDFReflowLib/issues/166)).
- The print footer stays in the reading flow on every page.
- Bullet markers become tiny image crops before paragraph items, and nesting is lost.
- "Closeout Documentation" and "Images" are not headings
  ([#167](https://github.com/vocaro/PDFReflowLib/issues/167)).
The 27 borderless links draw nothing beyond the printed page, so no page takes a source-page image
and each warns `annotationsNotConverted` ([#151](https://github.com/vocaro/PDFReflowLib/issues/151)).
