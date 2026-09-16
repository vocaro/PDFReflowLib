# USGS copper summary baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated macOS arm64 release CLI.
Corpus: Mineral Commodity Summaries 2025: Copper; 2 pages, 746,302 bytes,
SHA-256 `348b1e224d830a51e6d35cf81343eead26a0cb2a4e74c474d699b7faed1b10e6`.
Build: repository `c7db471`, Xcode 27.0 (27A266a), macOS 27.0 (26A428),
`swift build -c release --scratch-path .build/corpus-cli`; executable SHA-256
`2b2bd4ffb98192b64f47b34cd6524e13877d8625f4b37924e167597566a5bb3f`.

## Source and scope

Issue [#30](https://github.com/vocaro/PDFReflowLib/issues/30) candidate. Rights and provenance are recorded in `corpus/manifest.json`; the fresh-download identity check is in `../corpus-candidates-30/verification.json`. No source PDF or full EPUB is committed.

Born-digital, tagged Acrobat Pro extract (printed pages 64-65 of Mineral Commodity Summaries 2025). Four fonts. Both pages combine prose sections with underlined labels and borderless tables whose rows are grouped only by indentation; page 2 adds spanning Mine/Refinery production headers and eight table notes.

`source-inspection.json` records Poppler 26.04.0 metadata, per-review-page fonts and `pdftotext -layout` text. That extraction is evidence of the source text layer, not a reference transcription.

## Conversion and resource gate

The gated conversion through `tools/run_corpus_regressions.py` completes in 0.21 seconds. Kernel peak RSS is 32,440,320 bytes (30.9 MiB),
below the 128 MiB regression ceiling. Sampled physical footprint is 11.9 MiB.
Only converter RSS is gated; Apple services and physical iOS devices are not measured.

The EPUB is 896,074 bytes and passes EPUBCheck 5.3.0 with no errors or warnings. All 27 progress
events pass monotonicity, bounds and completion checks. The report counts 2 reflowed pages, 0 OCR pages and 12 images.
Warnings: 2 imageRegion.
The reviewed contract passes 11 checks on pages 1, 2.

Of 1,399 Poppler-extracted source words, 1,137 (81.3%) are absent from EPUB text. Words kept only inside preserved images count as absent, and script-specific tokenization differences inflate the figure; it locates problems, it does not score fidelity.

## Visual and textual evidence

Review pages were compared against rendered source pages; `selected-page-xhtml.json` retains the exact XHTML. `source-page-1.png` is the 100 DPI source raster for the key finding.

- Page 1 reflows only the folio, title, unit note and author line. The Domestic Production and Use paragraph, the statistics table and the Recycling, Import Sources and Tariff sections become seven preserved-region crops ([#36](https://github.com/vocaro/PDFReflowLib/issues/36)). The crops are legible and complete, but prose is no longer text.
- Page 2 reflows the COMEX paragraph and all eight table notes with correct superscript markers. Events, World Resources and Substitutes prose and the world-production table become crops.
- Tables as readable images are an acceptable interim representation; the defect is surrounding prose absorbed into them.

The corpus review JSON holds manual acceptance targets for the known failures. The regression contract checks only source-verified output and does not bless the defects above.
