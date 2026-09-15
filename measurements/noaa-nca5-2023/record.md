# Fifth National Climate Assessment scale baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated release CLI on macOS 27.0
(26A428) arm64, Xcode 27. Build: `2a63b92`, executable SHA-256
`9fed7af9cb6872ef13a596f1df9512fb9236e66a67e43db96e3637a9eeb4a0e8`.
Source: 1,834 pages, 219,876,258 bytes (209.69 MiB), SHA-256
`1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf`.
The owner-supplied bytes also match the SHA-512 published by NOAA.

## Full-run failure

The source fits the default 256 MiB input and 2,000-page limits. Extraction completes all
1,834 pages, but reconstruction exits after the last completed page 598 with
`Conversion resource limit: image output bytes`. Generated images exceed the 512 MiB output
ceiling. No EPUB is published, and the partial workspace is cleaned. EPUBCheck cannot run.

The failed process takes 64.78 seconds, with 918,814,720 bytes peak RSS (876.25 MiB) and
359,450,040 bytes sampled peak physical footprint. Those are different metrics, excluding
separate Apple services. This is a single failed Mac run, not full-book memory qualification,
physical-device performance, or a latency distribution. No case memory ceiling is established
until successful full conversion provides a meaningful baseline. The run is bounded by a
900-second timeout, which is not reached. Limits are not raised to mask the failure.

The 2,433 progress events are monotonic and stop at 65%, reconstruction page 598/1834. There
is no false completion event. The existing successful-progress gate correctly fails because
conversion never completes; `failure-checks.json` separately records the failure-path behavior.
Percentages represent work units, not predicted elapsed time.

Generated result and memory samples remain unchanged. The complete log, including framework
messages, is losslessly compressed with its original identity. [Issue #5](https://github.com/vocaro/PDFReflowLib/issues/5)
contains this additional output-budget reproduction alongside the scanned Warren case.

## Structure and review targets

pypdf 6.10.0 finds 303 bookmark entries and 32 numbered chapter starts. The report has 79
landscape pages (792 × 612 points) and 1,755 portrait pages (612 × 792 points). The transition
at physical pages 79/80 also separates Chapters 1 and 2. Source metadata identifies Adobe
InDesign 19.4 and a structure tree. Poppler pdfinfo 26.04.0 reports AES-256 permissions
encryption with printing allowed and copying disabled; the source opens without a password,
is consumed unchanged by the converter, and is not rewritten.

`source-inspection.json` retains bookmark hierarchy, metadata, geometry counts and selected
extraction samples. `Corpus/noaa-nca5-2023-chapters.json` records numbered chapter boundaries;
end pages are inferred from the next top-level bookmark. Chapter 1 starts on 33, Chapter 2 on
80, Chapter 3 on 139 and Chapter 32 on 1619. Unnumbered focus sections and appendices follow.
These are source-derived references, not a full visual validation of every chapter boundary.

The source visual spot check on page 48 covers Figure 1.5, its axes/legend/caption, adjacent
prose, and the spanning key-message box. The committed source raster is reference material,
not evidence of successful EPUB conversion. Later-page targets remain unqualified. No full
comparison or embedded-reader output exists because conversion fails before publication.

## Chapter splitting

EPUBWriter currently splits after accumulated serialized block payload exceeds 60,000 bytes,
between blocks; these file boundaries do not follow PDF bookmarks, and an individual large
block can exceed the threshold. Extraction/reconstruction retain whole-document value models,
so splitting output files does not provide chapter-bounded processing memory. [Issue #15](https://github.com/vocaro/PDFReflowLib/issues/15)
tracks validated chapter boundaries, bounded subdivision, cross-chapter anchors and progress.
This is a code-level gap, not an output chunking measurement from this failed run.

## Download and rights provenance

[NOAA's repository record](https://repository.library.noaa.gov/view/noaa/61592) identifies the
2023 report, its direct download, CC0/Public Domain declaration and SHA-512 checksum. The
fetcher receives HTTP 403 from that endpoint; no independent refetch is claimed. The supplied
original is present in ignored `Corpus/cache/` and verified against pinned SHA-256/byte count
and the publisher SHA-512. A fresh checkout may need a manually downloaded copy in that cache.
The publisher's CC0 declaration is recorded as such, separately from owner-confirmed entries
and from the library MIT license. This corpus addition is not a shipped-catalog admission.
