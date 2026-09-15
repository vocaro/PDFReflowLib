# Real-document development corpus

`Corpus/manifest.json` pins every external PDF by byte count and SHA-256. PDFs and generated
EPUBs remain local; routine tests download nothing. The original six synthetic fixtures remain
in `Tests/PDFReflowLibTests/Fixtures` and run without any external documents.

| Case | Pages | Coverage | Initial Mac peak-RSS ceiling |
| --- | ---: | --- | ---: |
| `faa-phak-8083-25c` | 522 | Columns, illustrations, diagrams, tables, glossary | 1,280 MiB |
| `wallace-algebra-2010` | 489 | Fractions, radicals, powers, examples, exercises, answer keys | 256 MiB |
| `gpo-warren-1964` | 920 | Scans, noisy existing OCR, notes, index, large image output | Unset: default conversion fails |
| `gpo-911-2004` | 585 | Untagged digital text, alternating headers, tracked lettering, endnotes | 256 MiB |

These are regression limits for release CLI processes on macOS arm64, not physical-device
budgets or guarantees about Apple service memory. Each evaluation verifies exact input identity
before conversion and records progress, timing, memory, output structure and optional EPUBCheck.

## Wallace algebra

*Beginning and Intermediate Algebra*, Tyler Wallace, copyright 2010. The supplied PDF is
2,183,036 bytes; its SHA-256 is
`856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678`.
Page 2 identifies [CC BY 3.0 Unported](https://creativecommons.org/licenses/by/3.0/) and the
[author's website](http://wallace.ccfaculty.org/book/book.html). The source is owner-supplied;
no successful current download from the author website or byte-equivalence claim is implied.
The local PDF is unmodified and is not covered by the library's MIT license. Retain the author,
title, license and source attribution in shared derivatives and identify modifications.

Place the supplied file at `Corpus/Beginning_and_Intermediate_Algebra.pdf`, or pass another
local path containing the same bytes. From the repository root, with full Xcode selected and
Python 3.11+ available:

```sh
swift build -c release
python3 Tools/evaluate-real-document.py --case wallace-algebra-2010 \
  --pdf Corpus/Beginning_and_Intermediate_Algebra.pdf --converter .build/release/pdf-reflow \
  --output /tmp/wallace-baseline --epubcheck /opt/homebrew/bin/epubcheck
scripts/compare-pdf-reflow.sh --pdf Corpus/Beginning_and_Intermediate_Algebra.pdf \
  --pages 2,12,16,119,266,293,343,347,438,479,483 --output /tmp/wallace-review --serve
```

Output directories must be new. `--epubcheck` is optional. The memory runner enforces the
case's ceiling automatically. The root `check-all.sh` currently selects the FAA workload for
its optional real-document gate; run the command above explicitly for algebra.

[Review points](../Corpus/wallace-algebra-2010-review.json) list physical PDF pages and
acceptance questions. Four spot checks show displayed mathematics retained in images, but page
343's inline squared exponent loses superscript semantics. The book is not fidelity-qualified.
[Baseline and visual evidence](../measurements/wallace-algebra-2010/record.md) separate valid
EPUB packaging from accurate mathematical content.


## Warren Commission report

The owner-supplied 1964 report contains 920 scanned pages with a separate text layer and no
structure tags. Its identity is pinned at 81,216,909 bytes, SHA-256
`341cc3471750c9c3be68b95a34b52f6cbdc86c4392427a8483ee1c6bc53cfc19`.
[GovInfo's publisher page](https://www.govinfo.gov/features/warren-commission-report-and-hearings)
identifies the report and links its official PDF. The local bytes are owner-supplied, without
an independent publisher re-fetch claim. The PDF is external development material, not bundled
or relicensed under MIT; no blanket rights determination covers every third-party exhibit.

```sh
swift build -c release --scratch-path .build/corpus-cli
python3 Tools/evaluate-real-document.py --case gpo-warren-1964 \
  --pdf Corpus/GPO-WARRENCOMMISSIONREPORT.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/warren-baseline --epubcheck /opt/homebrew/bin/epubcheck
```

This default run currently exits unsuccessfully: page-image output exceeds 512 MiB after the
last completed reconstruction page 390. No full EPUB is available to validate. The measurement
runner retains the failure and memory/progress evidence. There is no case memory ceiling yet;
do not treat a failed run as successful resource qualification or raise limits just to pass.

A bounded nine-page excerpt permits visual diagnosis while full conversion is blocked:

```sh
python3 measurements/gpo-warren-1964/prepare-excerpt.py \
  --pdf Corpus/GPO-WARRENCOMMISSIONREPORT.pdf --output /tmp/warren-excerpt.pdf
scripts/compare-pdf-reflow.sh --pdf /tmp/warren-excerpt.pdf \
  --pages all --output /tmp/warren-review --serve
```

Excerpt preparation requires the development-only `pypdf` package (measured with 6.10.0).
All output paths must be new. The excerpt's page numbers 1-9 map to original physical pages
1, 7, 21, 30, 50, 100, 890, 910 and 920. It loses whole-book context, so its results cannot
qualify the full document. Select **Positioned HTML** for Poppler: simple image URLs currently
break in the local comparison server. The original-page pane remains the visual reference.

[Review points](../Corpus/gpo-warren-1964-review.json) and
[measurement evidence](../measurements/gpo-warren-1964/record.md) record confirmed OCR,
preformatted-text, column-order and placeholder-count defects. The excerpt passes EPUBCheck
but is not fidelity-qualified. This case exercises trust in an existing OCR layer as well as
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
`657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b`;
no independent publisher re-fetch is claimed. This is external development material, not a
catalog admission, bundled PDF or MIT relicensing of third-party illustrations.

```sh
swift build -c release --scratch-path .build/corpus-cli
python3 Tools/evaluate-real-document.py --case gpo-911-2004 \
  --pdf Corpus/GPO-911REPORT.pdf --converter .build/corpus-cli/release/pdf-reflow \
  --output /tmp/911-baseline --epubcheck /opt/homebrew/bin/epubcheck
scripts/compare-pdf-reflow.sh --pdf Corpus/GPO-911REPORT.pdf \
  --pages 15,19,20,21,22,65,66,471,472,584 --output /tmp/911-review --serve
```

Output directories must be new. The full run passes the 256 MiB Mac RSS ceiling and EPUBCheck,
but header and note fidelity remain unqualified. The PDF permits copying/printing despite
permissions encryption and opens without a password prompt; the source is not rewritten.
Its metadata title is a print-job filename; set `ConversionOptions.title` for a reader-facing
title. [Review points](../Corpus/gpo-911-2004-review.json) and
[baseline evidence](../measurements/gpo-911-2004/record.md) distinguish successful word-spacing
examples from retained headers, false notes headings and flattened note markers.

[Issue #10](https://github.com/vocaro/PDFReflowLib/issues/10) parks the heading investigation.
The owner's 46/54 figure comes from a separate Claude ALL-CAPS prototype, not PDFReflowLib:
46 candidates were headers, 50 were non-headings overall, and four were genuine. Its sample
uses a Chapter 1 granule with a different identity. Those reported counts are preserved with
provenance, not promoted to independently reproduced library measurements.

[Issue #11](https://github.com/vocaro/PDFReflowLib/issues/11) tracks note-marker semantics,
number/text associations and future endnote linking; full note coverage remains unqualified.
