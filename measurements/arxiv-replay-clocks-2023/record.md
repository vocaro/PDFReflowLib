# Replay Clocks ACM-format paper baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated macOS arm64 release CLI.
Corpus: Replay Clocks; 12 pages, 2,617,877 bytes,
SHA-256 `1e8172e4a347bdf6722dacc38755f6fb3299866336b8153f51b2c13f3ac6109a`.
Build: repository `c7db471`, Xcode 27.0 (27A266a), macOS 27.0 (26A428),
`swift build -c release --scratch-path .build/corpus-cli`; executable SHA-256
`2b2bd4ffb98192b64f47b34cd6524e13877d8625f4b37924e167597566a5bb3f`.

## Source and scope

Issue [#30](https://github.com/vocaro/PDFReflowLib/issues/30) candidate. Rights and provenance are recorded in `corpus/manifest.json`; the fresh-download identity check is in `../corpus-candidates-30/verification.json`. No source PDF or full EPUB is committed.

Born-digital pdfTeX with acmart; Linux Libertine and newtx math Type 1 fonts with ToUnicode (math variables map to Unicode mathematical italic). Two columns, rotated arXiv margin stamp, pseudocode floats, vector figures and link annotations.

`source-inspection.json` records Poppler 26.04.0 metadata, per-review-page fonts and `pdftotext -layout` text. That extraction is evidence of the source text layer, not a reference transcription.

## Conversion and resource gate

The gated conversion through `tools/run_corpus_regressions.py` completes in 1.15 seconds. Kernel peak RSS is 169,246,720 bytes (161.4 MiB),
below the 256 MiB regression ceiling. Sampled physical footprint is 46.7 MiB.
Only converter RSS is gated; Apple services and physical iOS devices are not measured.

The EPUB is 8,165,353 bytes and passes EPUBCheck 5.3.0 with no errors or warnings. All 111 progress
events pass monotonicity, bounds and completion checks. The report counts 12 reflowed pages, 0 OCR pages and 72 images.
Warnings: 21 imageRegion, 11 annotationsNotConverted, 11 furnitureRemoved, 4 uncertainHyphen.
The reviewed contract passes 19 checks on pages 1, 3, 4.

Of 10,020 Poppler-extracted source words, 1,734 (17.3%) are absent from EPUB text. Words kept only inside preserved images count as absent, and script-specific tokenization differences inflate the figure; it locates problems, it does not score fidelity.

## Visual and textual evidence

Review pages were compared against rendered source pages; `selected-page-xhtml.json` retains the exact XHTML. `source-page-1.png` is the 100 DPI source raster for the key finding.

- Most prose reflows in correct two-column order; figures and some pseudocode are preserved as crops.
- Page 1 promotes the rotated arXiv stamp and both author names to headings, emits the second affiliation after the first column, and merges ABSTRACT and 1 INTRODUCTION into their paragraphs. Spaces after math variables are dropped (event 𝑒 must becomes 𝑒must) ([#43](https://github.com/vocaro/PDFReflowLib/issues/43)).
- Algorithm listings on pages 3-5 mix reflowed numbered lines, flattened paragraphs and crops; parts of the section 3.2 requirements appear only in crops ([#36](https://github.com/vocaro/PDFReflowLib/issues/36)).

The corpus review JSON holds manual acceptance targets for the known failures. The regression contract checks only source-verified output and does not bless the defects above.
