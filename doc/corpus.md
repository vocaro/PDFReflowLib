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

## Index

Every registered case, what it exercises, where its review points live and its initial Mac
peak-RSS ceiling (a regression limit for release CLI processes on macOS arm64, not a device
budget). The case column links to the narrative section below; the seven #30 cases share one.

| Case | Document | Pages | Exercises | Review points | Mac ceiling |
| --- | --- | ---: | --- | --- | ---: |
| `faa-phak-8083-25c` | Pilot's Handbook of Aeronautical Knowledge, FAA-H-8083-25C | 522 | Columns, illustrations, diagrams, tables, glossary, tagged PDF | manifest `reviewPages` | 1,280 MiB |
| [`wallace-algebra-2010`](#wallace-algebra) | Beginning and Intermediate Algebra | 489 | Fractions, radicals, powers, examples, exercises, answer keys | [review](../corpus/wallace-algebra-2010-review.json) | 256 MiB |
| [`gpo-warren-1964`](#warren-commission-report) | Warren Commission report | 920 | Scans, noisy existing OCR, notes, index, large image output | [review](../corpus/gpo-warren-1964-review.json) | 1,536 MiB |
| [`gpo-warren-1964-suspect-text-excerpt`](#suspect-text-layer-excerpt) | Warren pages 549, 553, 556, 636, 664 (derived) | 5 | Handwritten notes whose inherited layer is noise; typewritten pages misread in place | manifest `reviewPages` | 1,024 MiB |
| [`gpo-911-2004`](#911-commission-report) | The 9/11 Commission Report | 585 | Untagged digital text, alternating headers, tracked lettering, endnotes | [review](../corpus/gpo-911-2004-review.json) | 256 MiB |
| [`fed-explained-2021`](#the-fed-explained) | The Fed Explained | 135 | Tagged text, recurring tables, organization charts and flow diagrams | [review](../corpus/fed-explained-2021-review.json) | 768 MiB |
| [`dga-2025-2030`](#dietary-guidelines-for-americans-20252030) | Dietary Guidelines for Americans, 2025–2030 | 10 | Illustrated section bands, gradients, bullet columns and callouts | [review](../corpus/dga-2025-2030-review.json) | 192 MiB |
| [`noaa-nca5-2023`](#fifth-national-climate-assessment) | Fifth National Climate Assessment | 1,834 | Large tagged report, mixed orientations, 32 chapter starts, uneven graphics | [review](../corpus/noaa-nca5-2023-review.json), [chapters](../corpus/noaa-nca5-2023-chapters.json) | 1,280 MiB |
| [`gpo-our-flag-2003`](#our-flag) | Our Flag | 56 | Structure-tree inconsistencies, flag illustrations, drop capitals, one visible table | [review](../corpus/gpo-our-flag-2003-review.json) | 192 MiB |
| [`cdc-zombie-pandemic-2011`](#preparedness-101-zombie-pandemic) | Preparedness 101: Zombie Pandemic | 42 | Comic artwork, noisy inherited text, image-only dialogue, panel order | [review](../corpus/cdc-zombie-pandemic-2011-review.json) | 512 MiB |
| [`cia-blue-book-14-1955`](#project-blue-book-special-report-no-14) | Project Blue Book Special Report No. 14 | 312 | Scanned statistical tables, inherited OCR, negative warning/refusal contract | [review](../corpus/cia-blue-book-14-1955-review.json) | 768 MiB |
| [`nbs-jres-geltman-1977`](#issue-30-coverage-expansion) | Stimulated Multiphoton Bremsstrahlung in Electron-Ion Collisions | 7 | Scanned two-column academic paper, footnotes, OCR-damaged equations | [review](../corpus/nbs-jres-geltman-1977-review.json) | 512 MiB |
| [`arxiv-replay-clocks-2023`](#issue-30-coverage-expansion) | Replay Clocks | 12 | Born-digital ACM two-column paper, pseudocode, figures, math | [review](../corpus/arxiv-replay-clocks-2023-review.json) | 256 MiB |
| [`usgs-mcs2025-copper`](#issue-30-coverage-expansion) | Mineral Commodity Summaries 2025: Copper | 2 | Borderless tables, indentation-only row groups, spanning headers | [review](../corpus/usgs-mcs2025-copper-review.json) | 128 MiB |
| [`scotus-loper-bright-2024`](#issue-30-coverage-expansion) | Loper Bright Enterprises v. Raimondo (slip opinion) | 114 | Page-bottom footnotes continuing across pages, dash separators | [review](../corpus/scotus-loper-bright-2024-review.json) | 128 MiB |
| [`census-rrs2002-01`](#issue-30-coverage-expansion) | Disclosure Risk Assessment in Perturbative Microdata Protection | 20 | Born-digital text layer with no Unicode mapping (shifted letters) | [review](../corpus/census-rrs2002-01-review.json) | 512 MiB |
| [`uscis-m618-arabic-2015`](#issue-30-coverage-expansion) | Welcome to the United States (M-618-A, Arabic) | 116 | Right-to-left Arabic with embedded Latin and numbers | [review](../corpus/uscis-m618-arabic-2015-review.json) | 256 MiB |
| [`irs-p596-zhs-2025`](#issue-30-coverage-expansion) | Publication 596 (ZH-S), Earned Income Credit | 36 | Simplified Chinese mixed with Latin identifiers and amounts | [review](../corpus/irs-p596-zhs-2025-review.json) | 256 MiB |
| [`ntrs-20180003024-earthdata-slides-2018`](#earthdata-cloud-analytics-project) | Earthdata Cloud Analytics Project | 21 | Google Slides export with a full-bleed fill under real text; one slide whose only writing is drawn | manifest `reviewPages` | 128 MiB |
| [`usda-ars-agresearch-2012-11`](#agricultural-research-magazine) | Agricultural Research, Vol. 60 No. 10 | 24 | Magazine layout, dingbat/case glyph misreads, thin-page headings, lexicon-decided hyphens | manifest `reviewPages` | 512 MiB |
| [`ntrs-20210020887-techport-thm-2021`](#nasa-techport-tank-health-monitoring) | Tank Health Monitoring, NASA TechPort project 97058 | 5 | Repeated header bands, sidebar fields, ruled tables and gallery captions | manifest `reviewPages` | 128 MiB |

These are regression limits for release CLI processes on macOS arm64, not physical-device
budgets or guarantees about Apple service memory. Each evaluation verifies exact input identity
before conversion and records progress, timing, memory, output structure and optional EPUBCheck.

A manifest entry may carry `language`, the BCP 47 tag the document is written in. The lane
converts such a case with `--language TAG` — every conversion of it, including a memory attempt
spent after host pressure spoiled the first — and the evaluation receipt's `options` says so
(`library defaults with --language ar`). Two entries carry it: `ar` for
`uscis-m618-arabic-2015` and `zh-Hans` for `irs-p596-zhs-2025`, so each declares its own
`dc:language` and stands down the rules that hold only for a declared English
([#293](https://github.com/vocaro/PDFReflowLib/issues/293)). Only `zh-Hans` also reaches
Vision's recognizer: the library sets the recognition language only where Vision lists the tag
as given, and this host lists `zh-Hans` but `ar-SA`, not `ar`, so the Arabic guide's tag stops
short of recognition. An entry without the field converts at library defaults, which declare
`en`, exactly as the rest of the lane does. What the tag changes in each book, measured with and
without it on one binary, is in the two books' baseline records
([Arabic](../measurements/uscis-m618-arabic-2015-language-tag/record.md),
[Chinese](../measurements/irs-p596-zhs-2025-language-tag/record.md)).
The seven [#30 cases](#issue-30-coverage-expansion) are gated with reviewed contracts; their
selection and download identities are in [their record](../measurements/corpus-candidates-30/record.md).

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
  $(python3 tools/pdfreflow_tools/swift_sources.py probe-raster-environment.swift) \
  -o .build/raster-environment/probe
python3 tools/evaluate_real_document.py --case dga-2025-2030 \
  --pdf corpus/cache/DGA.pdf --converter .build/release/pdf-reflow \
  --output /tmp/dga-candidate --epubcheck /opt/homebrew/bin/epubcheck \
  --environment-probe .build/raster-environment/probe --execution-context host-terminal
python3 tools/compare_conversion_runs.py --baseline /tmp/dga-baseline \
  --candidate /tmp/dga-candidate --output /tmp/dga-drift.json
```

Capture `/tmp/dga-baseline` with the baseline converter and the same probe before comparing.
`run_corpus_regressions.py` accepts both new flags and forwards them to every selected case.
Resource measurements may run concurrently (`--jobs`); see
[parallel gates](regression-testing.md#parallel-gates) for the parity evidence and the host
memory-pressure guard. The probe requires the same macOS/Vision SDK as the
library. `tools/check_documented_builds.py` compiles this command as written, so a library source
the rasterizer comes to need cannot go missing from it unnoticed (#204).
Compiling it again changes its identity; recapture both runs if that identity changes.

A page is compared by its content, not by the identifiers the converter generates for it (#92).
Two of those identifiers renumber book-wide — the parser's paragraph ordinals and the writer's
`images/image-N` asset names — so comparing them verbatim reported every page after an edit as
changed: removing one paragraph from page 8 of the Fed report reported 117 changed pages, and
dropping one image asset reported 132 changed pages and 311 changed images, out of 315. Each page
now records, per paragraph, only whether it continues onto the previous or next page, so a
paragraph split or joined at a page break is still a difference; and it holds its images by their
SHA-256, so a moved, swapped or re-encoded image still changes the page it sits on. Assets are
matched book-wide by bytes: bytes with no match are `changedImages`, and an asset whose bytes are
unchanged and whose name moved is counted in `imageRenames`. Pages that agree once normalized but
differ in raw identifiers are summarized in `idOnlyShifts`. Neither summary fails a run, and
`--detail` lists them. Both edits above now report exactly the one page they changed; the
before-and-after numbers are in
[measurements/comparison-generated-ids](../measurements/comparison-generated-ids/record.md).

A difference between two binaries is the change's doing only where one binary does not produce
it on its own, and converting twice with one binary is not a no-op. Vision's reading of a page
differs between two runs on one host, from one unchanged binary: `census-rrs2002-01` reads page 4
as joined prose in one run and as the recognition's own line fragments in the next, and
`cdc-zombie-pandemic-2011` loses page 7's recognition entirely to the page image, taking the
nineteen navigation entries built from its headings with it (#284). This is not #173's variance
across binaries — the binary, its path, the source and the options are identical between these two
runs — and #269 and #281 record what it does to one gated case. So `--control` takes a third
evaluation —
a second run of the **baseline's own** converter, captured the same way — and every page, image
and report field that run also moves is reported as `unstablePages`, `unstableImages` and
`unstableReportFields` instead of as the candidate's. What is left is `attributedPages`,
`attributedImages` and `attributedReportFields`, and those alone decide the run:

```sh
python3 tools/compare_conversion_runs.py --baseline /tmp/dga-baseline \
  --candidate /tmp/dga-candidate --control /tmp/dga-baseline-again --output /tmp/dga-drift.json
```

A control whose `converterSHA256` is not the baseline's is refused, because a control built from
another tree measures that tree's difference and would charge it to the host. An unstable page may
still hold a real change; the comparison says it cannot tell rather than guessing, and a book whose
pages are unstable needs the reading pinned another way. Without `--control` nothing is attributed
and the verdict is what it always was.

The evaluator records a fresh run ID, converter and probe executable SHA-256, source identity,
system/build/architecture, probe result SHA-256, and EPUB SHA-256. The probe reports its own
executable/source/run identities, packed raster pixels without alignment padding, dimensions,
color-space metadata, available Metal device, and Vision success or failure plus recognized
lines. A probe timeout, launch failure, malformed output, stale identity, or OCR failure fails
the requested capability gate while retaining conversion diagnostics and a failed receipt.
The declared `--execution-context` is supplemental and may be absent or differ between two
otherwise compatible captures.

The comparator refuses missing, failed, stale, or incompatible capability receipts before
reporting output drift. It verifies the retained EPUB, probe JSON, and conversion report against
their evaluation receipt. Under compatible measured conditions it compares normalized page
records, source-page markers, encoded image assets, and conversion report fields; generated
output paths and ZIP timestamps/identifiers are not drift; clients needing identical bytes can
pin both ([reproducible packages](conversion-options.md#reproducible-packages)). A changed EPUB
hash is permitted between runs, but each EPUB must match its own receipt. Exit status is 0 only
for compatible runs with no differences in this scope. Historical receipts without this evidence
must be recaptured; manually adding context labels cannot qualify them.

These local receipts provide consistency checks, not signed attestation. A page-1 probe samples
capability at one instant and cannot prove all pages or later service states equivalent. The
comparison does not cover every EPUB semantic detail (for example CSS, navigation, and inline
styling), decoded image equivalence, or visual fidelity. Keep the existing content, resource,
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
python3 tools/evaluate_real_document.py --case wallace-algebra-2010 \
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
Detached fractions and broader exercise/answer-key fidelity remain unqualified.
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
python3 tools/evaluate_real_document.py --case gpo-warren-1964 \
  --pdf corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/warren-baseline --epubcheck /opt/homebrew/bin/epubcheck
```

The recorded default-budget baseline exited unsuccessfully after reconstruction page 390 when
page-image output exceeded 512 MiB. **Since the automatic encoding default the whole book
converts at library defaults, and since 2026-09-23 it is gated in the corpus lane**: on `8faeaab`,
920 pages, 934 images, every one written as JPEG because its scans are tonal and its line art is
neutral, 536,305,614 entry bytes — 565,298 bytes, 0.105%, inside the 512 MiB budget — in 523
seconds at a peak RSS of 1,174.5 MiB against a 1,536 MiB ceiling, with 14 pages recognized. That
margin is worth about 0.002 of JPEG quality and comes from ImageIO on this OS build, which is why
the case was held out of the lane while the encoding default was being measured
([record](../measurements/image-encoding-default/record.md)); the owner ruled on
[#242](https://github.com/vocaro/PDFReflowLib/issues/242) that the margin is a pass, and that an
OS revision pushing the book over it is a lane failure to look at then, not a reason to keep the
book out. The admission, both books' numbers and the basis of every pinned check are in
[corpus-lane-admissions](../measurements/corpus-lane-admissions/record.md). The measurement
runner retains the older failure and memory/progress evidence. A
[full-book encoding experiment](../measurements/warren-image-encoding/record.md) completes with an
explicit 2 GiB experimental override. The
[production client-policy runs](../measurements/client-options/record.md) also complete all
920 pages, with JPEG references or with supplementary references omitted, under explicit final
EPUB caps. Both validate; source-layer fidelity and physical-device memory remain unqualified.

A bounded nine-page excerpt permits visual diagnosis without converting the whole book:

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
new recognition: the default full run recognizes 14 of its 920 pages, and the lane's contract pins
nothing that reading decides — every pinned line is one the inherited layer holds on a page whose
layer is kept, and the two textless cloth covers pin only their page images.

### Suspect-text-layer excerpt

`gpo-warren-1964-suspect-text-excerpt` gates physical pages 549, 553, 556, 636 and 664 of the
pinned source against the inherited-layer plausibility rules (#93, #7): issue #7's own
reproduction path, which sidesteps the full book's image-output ceiling failure (#5) rather than
resolving it. `measurements/gpo-warren-1964-suspect-text-excerpt/prepare-excerpt.py` (pypdf)
verifies the pinned source identity before extracting; the excerpt is registered in
`corpus/manifest.json` as its own document (`identity.suppliedBy: "derived"`, no `downloadURL`),
so `tools/fetch_corpus.py --case gpo-warren-1964-suspect-text-excerpt` only ever reports a cache
hit against a locally regenerated file, never a download. Each page was converted and its source
raster read directly (`tools/compare_pdf.py --serve`). Pages 1–3 (549, 553, 556) are cursive
Parkland Memorial Hospital admission notes and a death-declaration statement, confirmed illegible
from the rasters: both the inherited layer and fresh recognition fail the English test and the
pages fall back to page images, which is the correct outcome, not a defect. Page 4 (636) is a
faint carbon typescript whose misread layer (`tcld`/`ftboot`-style damage) is compared against a
fresh reading and replaced where that reading misreads less of its own words. The case pins the
finding and the page image — what every run agrees on — and not which side of that comparison won.
It pinned the verdict until #269 and #281: two phrases read off the raster, "and he told me about
the things at" and "At 6:00 PM I instructed the officers to bring", and the absence of the
discarded layer's `ftboot`. The comparison turns on about five points between the reading's misread
share and the layer's 23.8%, and the reading is Vision's, which differs between two runs of one
binary on one host (#173, #284), so the lane reported FAIL for a condition of the host on a tree
that had not changed. The evidence moved rather than went:
`aMisreadCarbonTypescriptIsReplacedByARecognitionThatReadsBetter` replays this page's captured
layer and a captured recognition of it through `RecognitionPolicy` and holds both phrases, the
absent token and the `ocrUsed` warning, the way #173's recognized tables are replayed from
captures rather than re-measured. Page 5 (664) is a clean typewritten
exhibit whose misread layer is nonetheless kept, because recognition read no better; its kept,
still garbled text was confirmed to be a corrupted rendering of the same clearly legible source
content, not something else. Peak converter RSS measured about 724 MiB against a 1,024 MiB
ceiling. The page-by-page review is recorded in the case's `basis` in
[corpus/regressions.json](../corpus/regressions.json); there is no separate measurement record.

Of the five defects this book was filed for, four are fixed on `main` and are named here for
where the behavior came from, not as work in progress: the OCR font and geometry inference
([#6](https://github.com/vocaro/PDFReflowLib/issues/6), `7fcb80f`), the placeholder text and
counts ([#8](https://github.com/vocaro/PDFReflowLib/issues/8), `305cb14`), the inherited
text-layer quality rules ([#7](https://github.com/vocaro/PDFReflowLib/issues/7), ported by
`1b0308b`) and the comparison harness's absolute Poppler image URLs
([#9](https://github.com/vocaro/PDFReflowLib/issues/9), `b5f1937`).

The full-book image-output ceiling that
[#5](https://github.com/vocaro/PDFReflowLib/issues/5) described was closed twice over. `fbe3464`
closed the issue by making the default image encoding a per-image choice on the abandoned
coordination branch, which `dd160b4` merged with the `ours` strategy, so that commit is an
ancestor of `main` and none of its content is
([decision 0005](decisions/0005-abandoned-coordination-branch.md)); `56d9ec1` then ported the
per-image classifier onto `main` itself, and that port is what brings the book inside the budget
today. Before it, a default run measured on `da544ad` still exited after reconstruction page 390
of 920, and with the budget lifted the same build wrote 1,246,503,758 entry bytes over 931 images —
1,188.76 MiB, 2.32 times the 512 MiB default. Additional source-derived examples are linked from
the existing reading-order and memory investigations.


## 9/11 Commission report

The owner-supplied 2004 full report is a 585-page digital original with no structure tags.
[GovInfo](https://www.govinfo.gov/features/911-commission-report) identifies the official
edition and links the PDF. Local bytes are pinned at 2,475,163 bytes, SHA-256
`657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b`.
This is external development material, with owner-confirmed commercial use and redistribution;
the library MIT license does not relicense the document.

```sh
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate_real_document.py --case gpo-911-2004 \
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

[Issue #10](https://github.com/vocaro/PDFReflowLib/issues/10)'s heading investigation is done: the
running heads it describes are removed on document-wide margin-slot evidence, and the report's
heading elements that are running heads went from six to none.
The owner's 46/54 figure comes from a separate Claude ALL-CAPS prototype, not PDFReflowLib:
46 candidates were headers, 50 were non-headings overall, and four were genuine. Its sample
uses a Chapter 1 granule with a different identity. Those reported counts are preserved with
provenance, not promoted to independently reproduced library measurements.

Note-marker semantics, number/text associations and endnote linking are unresolved here, and
nothing open tracks them. [#11](https://github.com/vocaro/PDFReflowLib/issues/11) was closed by
`9803329` on the abandoned coordination branch, which merged with the `ours` strategy, so none
of its content reached `main` ([decision 0005](decisions/0005-abandoned-coordination-branch.md)).
`main` reconstructs bounded numbered note paragraphs (`NumberedNoteDetector`, `49b964b`) and
carries a marker continuation across a page break (#39, ported for #238), but it has no note
linker: no `NoteKey`, no `epub:type="noteref"` and no backlinks, so a body marker never resolves
to its note. Full note coverage remains unqualified.


## The Fed Explained

The 135-page eleventh edition (August 2021) is a tagged Federal Reserve Board publication.
Its structure tree contains table, figure and heading roles, including figure alternate text.
Current reconstruction uses spatial extraction rather than those semantic tags. Difficult
regions remain raster images with warnings; diagrams are not rebuilt as editable vector graphs.

```sh
python3 tools/fetch_corpus.py --case fed-explained-2021
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate_real_document.py --case fed-explained-2021 \
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
python3 tools/evaluate_real_document.py --case dga-2025-2030 \
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

[Graphics fallback #13](https://github.com/vocaro/PDFReflowLib/issues/13)'s budget is now on
`main`, raised to 250,000 operations on its own measurement, and no DGA page falls back on it
today — every one is under 10,000 operations, so #13's own claim about this book is stale.
The native cover-label split from [#14](https://github.com/vocaro/PDFReflowLib/issues/14)
was originally only on the abandoned coordination branch (`2e18b3149`). A fresh implementation
now splits the opposite-side selections using their measured ink ownership and joins each
ampersand-led label on its own side. The source contract requires intact food-label paragraphs;
see [the cover comparison](../measurements/detached-cover-labels/record.md). The retained source
image and review warning still apply, and the page-3 protein-column defect remains separate.


## Fifth National Climate Assessment

The NOAA-hosted full report is 219,876,258 bytes and 1,834 pages, close to the converter's
256 MiB / 2,000-page input limits. Its [chapter reference](../corpus/noaa-nca5-2023-chapters.json)
records 32 numbered chapters from PDF bookmarks. [Review points](../corpus/noaa-nca5-2023-review.json)
span chapter boundaries, charts, the landscape/portrait transition and late-book pages.

```sh
python3 tools/fetch_corpus.py --case noaa-nca5-2023
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate_real_document.py --case noaa-nca5-2023 \
  --pdf corpus/cache/noaa_61592_DS1.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/noaa-baseline --timeout 900 --epubcheck /opt/homebrew/bin/epubcheck
```

The publisher endpoint currently returns HTTP 403 to automated downloads. Place the exact
supplied/downloaded original in the indicated cache; the same fetch command verifies it offline.
A failed fresh fetch returns nonzero and does not create a substitute. The original matches
NOAA's published SHA-512 as well as the manifest's SHA-256. NOAA declares CC0/Public Domain.

The [full-run baseline](../measurements/noaa-nca5-2023/record.md) failed the image-output ceiling
after reconstruction page 598, and the
[explicit-policy comparison](../measurements/noaa-output-policies/record.md) completed all
1,834 pages only under 4 GiB experimental entry/final caps, with automatic references, PNG crops
and either PNG or JPEG 0.90 full pages; both passed EPUBCheck and preserved identical chapter
text, source anchors and crop bytes, with selected source-image review and late cancellation
checks. **The book now converts at library defaults inside the default budget, and since
2026-09-23 it is gated in the corpus lane**: on `8faeaab`, 1,834 pages, 1,609 images, 286,429,009
entry bytes — 0.53 of the 512 MiB budget — in 119 seconds at a peak RSS of 886.9 MiB against a
1,280 MiB ceiling, with no page recognized. It is the slowest case in the lane, which the owner's
ruling on [#242](https://github.com/vocaro/PDFReflowLib/issues/242) accepts. The encoding default
alone had not brought it in: with the budget lifted it wrote 817,716,220 bytes (1.52×), because
only 126 of its then 2,410 images were ones the classifier permits and JPEG encodes smaller, and
forced to `smallest:0.9` everywhere it was still 1.29× over
([record](../measurements/image-encoding-default/record.md)). What moved it was the number of
images, not their encoding: a page image was mandatory for any page carrying an annotation, which
is every page holding one of the report's own cross-references, and is now required only for an
annotation that did not convert, which took 781 images out; and an embedded original is written
as itself rather than re-rendered. The admission, both books' numbers and the basis of every
pinned check are in [corpus-lane-admissions](../measurements/corpus-lane-admissions/record.md).
[#5](https://github.com/vocaro/PDFReflowLib/issues/5), the output budget, is closed and nothing
open tracks it: `fbe3464` closed it on the abandoned coordination branch and `dd160b4` merged
that branch with the `ours` strategy, so none of its content is on `main`
([decision 0005](decisions/0005-abandoned-coordination-branch.md)); `56d9ec1` ported the
encoding default onto `main` separately. A default run measured on `da544ad`, before that port,
exited after reconstruction page 784 of 1,834, and with the budget lifted wrote 1,158,808,212
entry bytes over 2,410 images — 1,105.13 MiB, 2.16 times the 512 MiB default.
[Chapter-aware splitting #15](https://github.com/vocaro/PDFReflowLib/issues/15) now validates
chapter destinations against complete native opening titles, including consecutive Arabic or
Roman sequences under explicit Part containers. All 32 NOAA chapter starts begin spine
documents. The 60,000-byte body target subdivides large chapters and isolates oversized atomic
blocks without splitting their content; it remains a soft packing target. Page spilling and
streamed logical blocks separately bound retained reconstruction data. The
[full-report qualification](../measurements/chapter-outline-qualification/record.md) records
default-budget completion, source-page/navigation/link preservation, memory, progress and
cancellation. It does not claim arbitrary within-block subdivision, inferred footnote links or
a new physical-device budget.


## Our Flag

The 56-page House Document 108-97 is a quick illustrated baseline. Its populated structure tree
coexists with MarkInfo.Marked=false; it has heading and figure roles but no table roles or
figure alternate text. The converter does not currently consume the tree. Correct visual output
alone cannot prove tag use, and this source is not a fully validated semantic reference.

```sh
python3 tools/fetch_corpus.py --case gpo-our-flag-2003
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate_real_document.py --case gpo-our-flag-2003 \
  --pdf corpus/cache/CDOC-108hdoc97.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/our-flag-baseline --epubcheck /opt/homebrew/bin/epubcheck
scripts/compare-pdf-reflow.sh --pdf corpus/cache/CDOC-108hdoc97.pdf \
  --pages 7,15,22,27,32,33,41,48 --output /tmp/our-flag-review --serve
```

The [baseline](../measurements/gpo-our-flag-2003/record.md) passes full conversion, EPUBCheck,
progress and the 192 MiB Mac RSS gate. [Review references](../corpus/gpo-our-flag-2003-review.json)
include all ten table rows and meaning-bearing flag groups. The page-27 table retains both
headers and all rows in a warned region image; see [current evidence](../measurements/three-fidelity-fixes/record.md).
Drop-cap ordering is fixed: `a9d8fd5` attaches a native decorative initial to its own body line,
so pages 7, 9, 27 and 31 emit the opening before its continuation and neither initial becomes a
heading ([record](../measurements/drop-cap-order/record.md)). General figure/name/description
association remains unqualified under
[validated structure #17](https://github.com/vocaro/PDFReflowLib/issues/17).


## Preparedness 101: Zombie Pandemic

The CDC graphic novel tests dialogue embedded in artwork, damaged existing extraction and
panel reading order. The publisher declares Public Domain and supplies a SHA-512 matching the
owner's PDF. The automated endpoint returns HTTP 403; manually place the original in
`corpus/cache/cdc_6023_DS1.pdf`. The fetch command verifies that cached identity offline.

```sh
python3 tools/fetch_corpus.py --case cdc-zombie-pandemic-2011
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate_real_document.py --case cdc-zombie-pandemic-2011 \
  --pdf corpus/cache/cdc_6023_DS1.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/cdc-comic-baseline --epubcheck /opt/homebrew/bin/epubcheck
scripts/compare-pdf-reflow.sh --pdf corpus/cache/cdc_6023_DS1.pdf \
  --pages 3,5,13,16,21,37,39 --output /tmp/cdc-comic-review --serve
```

The [baseline](../measurements/cdc-zombie-pandemic-2011/record.md) passes EPUB validity,
progress and the 512 MiB Mac RSS gate, retaining 42 page images. The
[review targets](../corpus/cdc-zombie-pandemic-2011-review.json) expose damaged existing dialogue
on page 5 and fresh-OCR panel-order failure on page 13. [Suspect text #7](https://github.com/vocaro/PDFReflowLib/issues/7)
and [comic grouping #18](https://github.com/vocaro/PDFReflowLib/issues/18) track those gaps. Page
5's damaged dialogue is exactly the layer `TextLayerPlausibility` (#93, #7) now tests before any
recognition: under the default policy such a page reports `implausibleTextLayer`, and its layer is
replaced by fresh OCR when the layer fails the word or ink test, or kept and reported
`implausibleTextLayer` when fresh recognition itself fails the same English test. The gated
[regression contract](../corpus/regressions.json) for this document has not yet been re-reviewed
page by page against this behavior; that review is separate from porting the mechanism itself.
The measured 3,341 extracted whitespace tokens include OCR noise; they are not dialogue coverage.


## Project Blue Book Special Report No. 14

This 312-page typewritten/handwritten scan is a negative quality-signaling case. Its inherited
OCR and figure-only structure tree do not establish usable table semantics. The supplied release
copy remains in the ignored cache; automatic publisher download returns HTTP 403. The fetcher
verifies the exact supplied identity when the cache is manually seeded.

```sh
python3 tools/fetch_corpus.py --case cia-blue-book-14-1955
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate_real_document.py --case cia-blue-book-14-1955 \
  --pdf corpus/cache/CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf \
  --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/blue-book-baseline --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/check_corpus_quality.py --case cia-blue-book-14-1955 \
  --evaluation /tmp/blue-book-baseline
```

The converter now emits `unverifiedTextLayer` on pages with existing text over a page-sized
image. The [current measurement](../measurements/quality-and-raster-fixes/record.md) checks pages
74 and 150 separately from the [historical failing baseline](../measurements/cia-blue-book-14-1955/record.md).
Since [#275](https://github.com/vocaro/PDFReflowLib/issues/275) the book's hand-written table
pages say more than that: 57 of its 312 layers fail the word test, 56 of those pages are
recognized, and 41 of them preserve a located table as a picture under `unreadTableCells`. That
recognition is why the book's memory ceiling rose from 512 to 768 MiB
([record](../measurements/unread-table-cells-plausibility/record.md)); page 74, whose table's
values are typewritten, keeps its layer and its `unverifiedTextLayer` notice.
That is the warned per-table fallback [#31](https://github.com/vocaro/PDFReflowLib/issues/31)
asked for, demonstrated on the book itself rather than on a captured reading
([record](../measurements/scanned-table-fallback-reached/record.md)); reconstructing the cells
stays refused on the evidence in [scanned-table-cells](../measurements/scanned-table-cells/record.md).
Crashes, timeouts, resource failures and generic image-preservation warnings do not satisfy it. No production quality-refusal
error exists yet; the manifest's approved diagnostic list is empty. Future dedicated quality
warnings/refusals need explicit semantics and matching contract entries. The present warning
asks the client to review transcription, tables, numbers and order against the preserved source;
it does not assert that an individual cell is wrong.

[Review references](../corpus/cia-blue-book-14-1955-review.json) include the typewritten table's
printed rows and handwritten-sheet review targets. The warning this book asked for is on `main`:
[#19](https://github.com/vocaro/PDFReflowLib/issues/19) is named for where `unverifiedTextLayer`
came from, and `305cb14` implemented it and closed the issue. Passing the signal contract will
not establish correct cells, and no quality refusal exists.

Page 19 carries the one known false join of the marker-continuation rule
([citation-continuations](../measurements/citation-continuations/record.md)): on this inherited-OCR
page a serial-number code list fills equal-width lines, so `1132. 02 representing an additional
observer` reads as a wrapped continuation of the `1132.01` entry above it and is appended to it.
The rule consults neither `unverifiedTextLayer` nor the shape of an enumerated code list.


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
| [`usgs-mcs2025-copper`](../measurements/usgs-mcs2025-copper/record.md) | Borderless tables | Fixed (#36, ported for [#229](https://github.com/vocaro/PDFReflowLib/issues/229)): the section prose around the tables reflows (page 1, 355 words instead of 20; page 2, 578 instead of 251). Fixed again (#210): all three tables are now read as cells and the book converts with no images at all; a cell's raised note and estimate marks are characters, not `<sup>` | [#210](https://github.com/vocaro/PDFReflowLib/issues/210) |
| [`scotus-loper-bright-2024`](../measurements/scotus-loper-bright-2024/record.md) | Page-bottom footnotes | Text complete; footnotes merge into body paragraphs. The 75 citation-leading lines that became preformatted are fixed (#39): 7 remain, four after an abbreviation or a sentence end, two opening a page after a running header and one `* * *` separator | [#40](https://github.com/vocaro/PDFReflowLib/issues/40) closed, fix only in `20c78f352`; no open tracker, see [#231](https://github.com/vocaro/PDFReflowLib/issues/231) |
| [`census-rrs2002-01`](../measurements/census-rrs2002-01/record.md) | Damaged encoding | Fixed (#38): `TextEncodingCheck` flags the shifted-letter body (pages 2-20) as `damagedTextEncoding` and recognizes it by default; minor OCR misreadings remain on individual words | [#38](https://github.com/vocaro/PDFReflowLib/issues/38) |
| [`uscis-m618-arabic-2015`](../measurements/uscis-m618-arabic-2015/record.md) | Right-to-left script | Arabic words correct; mixed-direction runs fragment and reverse | [#41](https://github.com/vocaro/PDFReflowLib/issues/41) |
| [`irs-p596-zhs-2025`](../measurements/irs-p596-zhs-2025/record.md) | CJK script | Order and amounts correct; spaces inserted inside CJK; some columns rasterized | [#42](https://github.com/vocaro/PDFReflowLib/issues/42) open; [#36](https://github.com/vocaro/PDFReflowLib/issues/36) closed, fix only in `3507d7d01`, live tracker [#229](https://github.com/vocaro/PDFReflowLib/issues/229) |
| [`nbs-jres-geltman-1977`](../measurements/nbs-jres-geltman-1977/record.md) | Scanned two-column paper | Inline images force page fallback on pages 1–6 | [#37](https://github.com/vocaro/PDFReflowLib/issues/37) closed, fix only in `277cbde39`; no open tracker, see [#231](https://github.com/vocaro/PDFReflowLib/issues/231) |
| [`arxiv-replay-clocks-2023`](../measurements/arxiv-replay-clocks-2023/record.md) | Born-digital ACM paper | Prose order correct; front-matter headings, section labels and math spacing wrong | [#43](https://github.com/vocaro/PDFReflowLib/issues/43)'s missing-space half is on `main`, ported for [#225](https://github.com/vocaro/PDFReflowLib/issues/225); its front-matter heading and section-label half is not, and lives only in `417edc705` — no open tracker, see [#231](https://github.com/vocaro/PDFReflowLib/issues/231) |

Five of the issues in that last column are closed although the defect beside them is still in
`main`. Each was closed by a commit on the abandoned coordination branch, which `dd160b4` merged
with the `ours` strategy: the commit is an ancestor of `main` and its content is not
([decision 0005](decisions/0005-abandoned-coordination-branch.md)). The named commit is where the
work is — `git show 3507d7d01` and so on — and per decision 0005 it is hand-ported onto `main`'s
current pipeline with its own tests and corpus review, not cherry-picked. [#231](https://github.com/vocaro/PDFReflowLib/issues/231) reconciles
the 124 issues that branch closed against what `main` actually holds.

The NBS paper stands in for an owner-supplied, ACM-copyrighted Lamport CACM article in the same
two-column scanned format. Replay Clocks is CC BY 4.0: retain the attribution recorded in the
manifest. USCIS states some guide images are licensed, so that case commits no page rasters.
Hebrew is covered by the [UCL Shakespeare source review](../measurements/ucl-hebrew-shakespeare-2017/record.md)
and its page-specific content contract. The 553-page CC BY 4.0 book converts with
`--language he --no-ocr`; six reviewed pages protect selected text, cover art and reference
order. Parallel bilingual alignment, verse hierarchy, speaker pairing and note links remain
unqualified. Vertical Japanese and Devanagari candidates have [documented source
blockers](../measurements/japanese-tategaki-overleaf/record.md) and [Hindi source
blockers](../measurements/hindi-candidates-44/record.md), respectively, so [#44](https://github.com/vocaro/PDFReflowLib/issues/44)
remains open.

## Earthdata Cloud Analytics Project

A 21-slide Google Slides export, NASA Technical Reports Server record 20180003024 (report
GSFC-E-DAA-TN54544), presented at the CEOS WGISS meeting, April 2018. Local bytes are pinned at
510,231, SHA-256 `f0a1ea3f5711228a9de2544fd1a94b05cfb8d9323fe3a4c253542f5a6ead5c94`. Both
presenters are marked `*U.S. Civil Servant`; the NTRS copyright record gives
`determinationType GOV_PUBLIC_USE_PERMITTED`. Every slide shows the NASA insignia (use restricted
by 14 CFR 1221); no crops or rasters of any slide are committed, and the review contract has no
image references. Retain the attribution recorded in the manifest.

```sh
python3 tools/fetch_corpus.py --case ntrs-20180003024-earthdata-slides-2018
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate_real_document.py --case ntrs-20180003024-earthdata-slides-2018 \
  --pdf corpus/cache/20180003024.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/earthdata-baseline --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/compare_pdf.py --pdf corpus/cache/20180003024.pdf \
  --converter .build/corpus-cli/release/pdf-reflow --output /tmp/earthdata-review --serve
```

[#176](https://github.com/vocaro/PDFReflowLib/issues/176) recognizes a page whose text layer
holds no letter at all but whose own drawing carries writing. Slide 5's question ("How do we
support user analysis of very large data volumes?") is drawn as vector glyph outlines with no
text layer at all; it is this deck's motivating case, and it is now gated here. All 21 slides
were converted and reviewed against Poppler rasters of the source pages. Slide 5's recognized
text was checked word-for-word against its rendered slide and matches exactly; it reports
`ocrUsed`, and only it among the 21 slides is not `unverifiedTextLayer`. Slide 1's two-line title
and byline, and slide 9's title and five guiding principles, were also checked in source order.

Every other slide reports `unverifiedTextLayer`: this pipeline has no equivalent of the
abandoned integration branch's `layoutComesApart` (#117, not ported; see
[decision 0005](decisions/0005-abandoned-coordination-branch.md)), which there exempts a
born-digital page whose art is only a full-bleed background paint from counting as image-backed;
without it, an ordinary slide export already reads as image-backed here. That branch's own record
left the identical defect open for this exact deck under #164, so this is not a regression
from porting the feature — it is a pre-existing gap this port does not close either. #164 has
since been closed, by `88803aca7` on that branch, so it no longer tracks anything: the defect
stands here exactly as described. Numbered and
lettered list item grouping (slides 7 and 9) and lettered sub-item nesting (slide 7) were reviewed
and found imperfect, and diagram box order beyond what is listed above was not independently
verified; none of that is pinned. [#164](https://github.com/vocaro/PDFReflowLib/issues/164) and [#165](https://github.com/vocaro/PDFReflowLib/issues/165) described these gaps and are both
closed, by `88803aca7` and `3a65be6c1` on the abandoned coordination branch, whose content never
reached `main`; nothing open tracks either. The reconciliation is [#231](https://github.com/vocaro/PDFReflowLib/issues/231).

`TextLayerPlausibilityTests.swift` covers the #176 mechanism itself end to end with synthetic
slides; the rule is specified in [behavior](behavior.md#pages-whose-writing-is-drawn-176).

## Agricultural Research magazine

*Agricultural Research*, Vol. 60 No. 10, November/December 2012, USDA Agricultural Research
Service. Local bytes are pinned at 9,329,928, SHA-256
`2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761`. As a work of the U.S.
government it is public domain (17 U.S.C. 105); rights are cleared for the full 24-page issue,
with one standing exception: page 24 carries agency logos and a mailing panel, and no crop or
raster of that page is ever committed. This corpus case, and the review contract below, add no
`imageRegions` or `minimumImages` check anywhere, matching that constraint, not only on page 24.

```sh
python3 tools/fetch_corpus.py --case usda-ars-agresearch-2012-11
swift build -c release --scratch-path .build/corpus-cli
python3 tools/evaluate_real_document.py --case usda-ars-agresearch-2012-11 \
  --pdf corpus/cache/November-December2012.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/agresearch-baseline --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/compare_pdf.py --pdf corpus/cache/November-December2012.pdf \
  --converter .build/corpus-cli/release/pdf-reflow --output /tmp/agresearch-review --serve
```

[#186](https://github.com/vocaro/PDFReflowLib/issues/186) bundles five magazine-layout fixes;
this document is the motivating case. All five are now ported to main: a heading-size threshold
on thin-text pages (a document-wide body floor, plus excluding an isolated lowercase-opening
heading-size line), system-lexicon-decided line-end hyphens, (#218) a bold sub-heading whose
paragraph opens past an intervening picture and its caption, and (#217) dingbat fonts read
through their own encoding and a font's drawn letter case trusted over its `ToUnicode` map. The
rules are specified in [behavior](behavior.md); the adaptations each port required are in
[decision 0005](decisions/0005-abandoned-coordination-branch.md).

Pages 1, 6, 9, 19 and 24 were converted and read against the actual output — pages 1 and 24
against source rasters (`tools/compare_pdf.py`), pages 6, 9 and 19 by reading the converted text
itself, which is unambiguous. Page 1's cover title ("Keeping Our" / "Troops Safe" / "From Insects")
is confirmed unaffected by the new document-body floor, and its lowercase cross-reference line
"pages 2, 4-14" is confirmed now a paragraph instead of a fourth heading. Page 9's "Fighting Filth
Flies" sidebar title (nine-point Helvetica-Bold over a ten-and-a-half-point body) is confirmed now
a heading, and its own paragraph ("Nonbiting flies that shuttle between filth...", opening past an
intervening photograph and caption) is confirmed still present in the output; pre-existing column
interleaving on this three-column page (#153, closed by `58a2ddda6` on the abandoned branch and
unfixed here — see below) means the two are not adjacent in reading order, so
this is checked as heading-presence and paragraph-presence separately, with the direct adjacency
covered by Swift fixture tests against this same real page in isolation. Page 24's mailing panel
(return address, "Official Business", the web line) is confirmed now paragraphs. Pages 6 and 19
each confirm an ordinary English compound the magazine never prints whole (`com-panies`,
`infec-tions`) joined without its hyphen; a third instance on page 15 (`compli-ance`) is not fixed
and not pinned, because its two halves land in separate paragraph blocks from unrelated
column-interleaving behavior (#153) before the hyphen logic ever sees them as adjacent lines.

The #217 pair were at first confirmed still present on this document and recorded as known
fidelity issues: the back cover's dingbat bullet between the two web addresses misread as a
superscript lowercase `l`, and page 15's photo credit "BRAD FRITz" misread its final letter's
case, both needing content-stream font reading main did not have. `GlyphIdentityReader` now
fixes both, and the contract pins them: the bullet (a Monotype Sorts glyph at code 79, embedded
as `WVUHWN+MonotypeSorts`) reads as U+25CF, not raised and not `l`, and the credit reads
"BRAD FRITZ" (its Helvetica-Condensed glyph's `WinAnsiEncoding`, Nonsymbolic flags and CharSet,
which lists `Z` but not `z`, agree the glyph drawn is a capital). Those early ports did not
qualify the remaining crops (#158) or column interleaving (#153). Their original branch fixes,
`bff0a046c` and `58a2ddda6`, were absent after the abandoned branch's `ours` merge
([decision 0005](decisions/0005-abandoned-coordination-branch.md)); #231 records that history.

The later [native magazine qualification](../measurements/native-magazine-panels/record.md)
adds complete captions on pages 5, 8, 9 and 19, the outlined initial on 16, semantic quotations
on 11–12, native column order on 20–23, and removal of both impressions of page 23's running
foot. These source cases supersede the earlier broad statement that their text remains cropped
or interleaved. The [continuation qualification](../measurements/magazine-continuations/record.md)
keeps the page-12 paragraph together around its quotation and the page-17 paragraph together
around its picture and credit; the displays retain their own blocks. Stacked subheadings on
6, 7 and 17 become complete headings. Other unreviewed layout cases are not covered by those
claims. The Mac RSS ceiling remains 512 MiB.

## NASA TechPort Tank Health Monitoring

The five-page NASA TechPort project 97058 data sheet is pinned as
`ntrs-20210020887-techport-thm-2021`, SHA-256
`0fce4b68983ad8a216c8228ec44697c61ab41977ad41733c465ebebec3976ff0`.
Its source identity and owner-approved text-derivative scope are in the manifest. No page
raster or crop is committed. The source is attributed to Rudy Werlink, NASA Kennedy Space
Center; the document was printed on 2021-08-24.

The [source record](../measurements/native-magazine-panels/record.md) qualifies the repeated
header band, native sidebar fields, three ruled tables on page 4, and three picture/caption
cards on page 5. The three TRL values remain native text while the chart retains its source
appearance. Tables preserve merged cells and original inline styles; gallery captions follow
their own pictures from left to right. All five pages have source contracts. The registered
Mac RSS ceiling is 128 MiB; it is not a physical-device budget.
