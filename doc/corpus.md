# Real-document development corpus

`Corpus/manifest.json` pins every external PDF by byte count and SHA-256. PDFs and generated
EPUBs remain local; routine tests download nothing. The original six synthetic fixtures remain
in `Tests/PDFReflowLibTests/Fixtures` and run without any external documents.

| Case | Pages | Coverage | Initial Mac peak-RSS ceiling |
| --- | ---: | --- | ---: |
| `faa-phak-8083-25c` | 522 | Columns, illustrations, diagrams, tables, glossary | 1,280 MiB |
| `wallace-algebra-2010` | 489 | Fractions, radicals, powers, examples, exercises, answer keys | 256 MiB |

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
