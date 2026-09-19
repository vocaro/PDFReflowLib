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
| `noaa-nca5-2023` | 1,834 | Large tagged report, mixed orientations, 32 chapter starts, uneven graphics | Unset: default conversion fails |
| `gpo-our-flag-2003` | 56 | Structure-tree inconsistencies, flag illustrations, drop capitals, one visible table | 192 MiB |
| `cdc-zombie-pandemic-2011` | 42 | Comic artwork, noisy inherited text, image-only dialogue, panel order | 512 MiB |
| `cia-blue-book-14-1955` | 312 | Scanned statistical tables, inherited OCR, negative warning/refusal contract | 512 MiB |
| `nbs-jres-geltman-1977` | 7 | Scanned two-column academic paper, footnotes, OCR-damaged equations | 512 MiB |
| `arxiv-replay-clocks-2023` | 12 | Born-digital ACM two-column paper, pseudocode, figures, math | 256 MiB |
| `usgs-mcs2025-copper` | 2 | Borderless tables, indentation-only row groups, spanning headers | 128 MiB |
| `scotus-loper-bright-2024` | 114 | Page-bottom footnotes continuing across pages, dash separators | 128 MiB |
| `census-rrs2002-01` | 20 | Born-digital text layer with no Unicode mapping (shifted letters) | 512 MiB |
| `uscis-m618-arabic-2015` | 116 | Right-to-left Arabic with embedded Latin and numbers | 256 MiB |
| `irs-p596-zhs-2025` | 36 | Simplified Chinese mixed with Latin identifiers and amounts | 256 MiB |
| `usda-ars-agresearch-2012-11` | 24 | Magazine layout, dingbat/case glyph misreads, thin-page headings, lexicon-decided hyphens | 512 MiB |

These are regression limits for release CLI processes on macOS arm64, not physical-device
budgets or guarantees about Apple service memory. Each evaluation verifies exact input identity
before conversion and records progress, timing, memory, output structure and optional EPUBCheck.
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
case's ceiling automatically. `scripts/check-all.sh --corpus` includes algebra in the eight-document gate.

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

The recorded default-budget baseline exits unsuccessfully after reconstruction page 390
when page-image output exceeds 512 MiB. The measurement runner retains that failure and
memory/progress evidence. A [full-book encoding experiment](../measurements/warren-image-encoding/record.md)
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
python3 tools/evaluate_real_document.py --case noaa-nca5-2023 \
  --pdf corpus/cache/noaa_61592_DS1.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/noaa-baseline --timeout 900 --epubcheck /opt/homebrew/bin/epubcheck
```

The publisher endpoint currently returns HTTP 403 to automated downloads. Place the exact
supplied/downloaded original in the indicated cache; the same fetch command verifies it offline.
A failed fresh fetch returns nonzero and does not create a substitute. The original matches
NOAA's published SHA-512 as well as the manifest's SHA-256. NOAA declares CC0/Public Domain.

The [full-run baseline](../measurements/noaa-nca5-2023/record.md) fails the image-output ceiling
after reconstruction page 598; the latest default run fails after page 599. The
[explicit-policy comparison](../measurements/noaa-output-policies/record.md) completes all
1,834 pages with automatic references, PNG crops and either PNG or JPEG 0.90 full pages under
4 GiB experimental entry/final caps. Both pass EPUBCheck and preserve identical chapter text,
source anchors and crop bytes, with selected source-image review and late cancellation checks.
Peak converter RSS is about 1.04 billion bytes in these single Mac runs; no case RSS ceiling
or physical-device budget is established. Default-budget failure remains outside the passing
corpus lane. [Output-budget issue #5](https://github.com/vocaro/PDFReflowLib/issues/5)
and [chapter-aware splitting issue #15](https://github.com/vocaro/PDFReflowLib/issues/15) track
separate gaps. The current writer's approximate 60,000-byte file splitting does not follow PDF
chapters or bound the memory of whole-document reconstruction.


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
| [`census-rrs2002-01`](../measurements/census-rrs2002-01/record.md) | Damaged encoding | Fixed (#38): `TextEncodingCheck` flags the shifted-letter body (pages 2-20) as `damagedTextEncoding` and recognizes it by default; minor OCR misreadings remain on individual words | [#38](https://github.com/vocaro/PDFReflowLib/issues/38) |
| [`uscis-m618-arabic-2015`](../measurements/uscis-m618-arabic-2015/record.md) | Right-to-left script | Arabic words correct; mixed-direction runs fragment and reverse | [#41](https://github.com/vocaro/PDFReflowLib/issues/41) |
| [`irs-p596-zhs-2025`](../measurements/irs-p596-zhs-2025/record.md) | CJK script | Order and amounts correct; spaces inserted inside CJK; some columns rasterized | [#42](https://github.com/vocaro/PDFReflowLib/issues/42), [#36](https://github.com/vocaro/PDFReflowLib/issues/36) |
| [`nbs-jres-geltman-1977`](../measurements/nbs-jres-geltman-1977/record.md) | Scanned two-column paper | Inline images force page fallback on pages 1–6 | [#37](https://github.com/vocaro/PDFReflowLib/issues/37) |
| [`arxiv-replay-clocks-2023`](../measurements/arxiv-replay-clocks-2023/record.md) | Born-digital ACM paper | Prose order correct; front-matter headings, section labels and math spacing wrong | [#43](https://github.com/vocaro/PDFReflowLib/issues/43) |

The NBS paper stands in for an owner-supplied, ACM-copyrighted Lamport CACM article in the same
two-column scanned format. Replay Clocks is CC BY 4.0: retain the attribution recorded in the
manifest. USCIS states some guide images are licensed, so that case commits no page rasters.
Vertical CJK, Hebrew and Devanagari layouts remain uncovered for lack of clearly licensed sources
([#44](https://github.com/vocaro/PDFReflowLib/issues/44)).

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
abandoned integration branch's `layoutComesApart` (#117, not ported), which there exempts a
born-digital page whose art is only a full-bleed background paint from counting as image-backed;
without it, an ordinary slide export already reads as image-backed here. That branch's own record
left the identical defect open for this exact deck, tracked as #164, so this is not a regression
from porting the feature — it is a pre-existing gap this port does not close either. Numbered and
lettered list item grouping (slides 7 and 9) and lettered sub-item nesting (slide 7) were reviewed
and found imperfect, and diagram box order beyond what is listed above was not independently
verified; none of that is pinned. [Tracking: #164](https://github.com/vocaro/PDFReflowLib/issues/164),
[#165](https://github.com/vocaro/PDFReflowLib/issues/165).

`ImageOnlyPageTests.swift` covers the #176 mechanism itself end to end with synthetic slides; see
[regression testing](regression-testing.md#pages-whose-writing-is-drawn).

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
this document is the motivating case. Three are now ported to main: a heading-size threshold on
thin-text pages (a document-wide body floor, plus excluding an isolated lowercase-opening
heading-size line), system-lexicon-decided line-end hyphens, and (#218) a bold sub-heading whose
paragraph opens past an intervening picture and its caption. See
[regression testing](regression-testing.md#thin-page-headings-and-lexicon-decided-hyphens) and
[regression testing](regression-testing.md#a-sub-heading-past-a-photograph) for what those fixes
do and the adaptations each port required. The remaining two (dingbat font reading, and a
letter-case glyph-versus-cmap disagreement) are tracked separately as #217's scope.

Pages 1, 6, 9, 19 and 24 were converted and read against the actual output — pages 1 and 24
against source rasters (`tools/compare_pdf.py`), pages 6, 9 and 19 by reading the converted text
itself, which is unambiguous. Page 1's cover title ("Keeping Our" / "Troops Safe" / "From Insects")
is confirmed unaffected by the new document-body floor, and its lowercase cross-reference line
"pages 2, 4-14" is confirmed now a paragraph instead of a fourth heading. Page 9's "Fighting Filth
Flies" sidebar title (nine-point Helvetica-Bold over a ten-and-a-half-point body) is confirmed now
a heading, and its own paragraph ("Nonbiting flies that shuttle between filth...", opening past an
intervening photograph and caption) is confirmed still present in the output; pre-existing column
interleaving on this three-column page (#153) means the two are not adjacent in reading order, so
this is checked as heading-presence and paragraph-presence separately, with the direct adjacency
covered by Swift fixture tests against this same real page in isolation. Page 24's mailing panel
(return address, "Official Business", the web line) is confirmed now paragraphs. Pages 6 and 19
each confirm an ordinary English compound the magazine never prints whole (`com-panies`,
`infec-tions`) joined without its hyphen; a third instance on page 15 (`compli-ance`) is not fixed
and not pinned, because its two halves land in separate paragraph blocks from unrelated
column-interleaving behavior (#153) before the hyphen logic ever sees them as adjacent lines.

The other three upstream #186 fixes are confirmed still present (not fixed) on this document, and
are recorded as known fidelity issues rather than pinned: the back cover's dingbat bullet between
the two web addresses still misreads as a superscript lowercase `l` (needs `FontWeightReader`'s
content-stream font/glyph scanning, absent from main), page 15's photo credit "BRAD FRITz" still
misreads its final letter's case (same dependency), and a sidebar subhead's paragraph opening past
its photograph is not specifically handled (needs the sub-heading label system, also absent from
main). Most page text on this document sits in preserved-region crops (#158) or interleaves
across columns (#153), both pre-existing and outside this port's scope; those pages are not
reviewed here. Peak converter RSS measured about 279 MiB against a 512 MiB ceiling.
