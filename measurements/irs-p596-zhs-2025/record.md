# IRS Publication 596 (Simplified Chinese) baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated macOS arm64 release CLI.
Corpus: Publication 596 (ZH-S), Earned Income Credit (EIC), 2025 (Simplified Chinese); 36 pages, 2,674,617 bytes,
SHA-256 `7d1cff45bc567f1257ea1aa1e2ce67945aafb12708b2e22901ce6392436590c2`.
Build: repository `c7db471`, Xcode 27.0 (27A266a), macOS 27.0 (26A428),
`swift build -c release --scratch-path .build/corpus-cli`; executable SHA-256
`2b2bd4ffb98192b64f47b34cd6524e13877d8625f4b37924e167597566a5bb3f`.

## Source and scope

Issue [#30](https://github.com/vocaro/PDFReflowLib/issues/30) candidate. Rights and provenance are recorded in `corpus/manifest.json`; the fresh-download identity check is in `../corpus-candidates-30/verification.json`. No source PDF or full EPUB is committed.

Tagged Antenna House output modified by iText; Noto Sans CJK Identity-H fonts. Two-column Simplified Chinese with embedded Latin identifiers and amounts, column rules, tip boxes, and EIC lookup tables on pages 24-34.

`source-inspection.json` records Poppler 26.04.0 metadata, per-review-page fonts and `pdftotext -layout` text. That extraction is evidence of the source text layer, not a reference transcription.

## Conversion and resource gate

The gated conversion through `tools/run_corpus_regressions.py` completes in 4.39 seconds. Kernel peak RSS is 179,879,936 bytes (171.5 MiB),
below the 256 MiB regression ceiling. Sampled physical footprint is 90.9 MiB.
Only converter RSS is gated; Apple services and physical iOS devices are not measured.

The EPUB is 39,199,102 bytes and passes EPUBCheck 5.3.0 with no errors or warnings. All 230 progress
events pass monotonicity, bounds and completion checks. The report counts 34 reflowed pages, 0 OCR pages and 139 images.
Warnings: 57 imageRegion, 26 structureFallback, 21 annotationsNotConverted, 3 furnitureRemoved.
The reviewed contract passes 12 checks on pages 1, 16.

Of 32,019 Poppler-extracted source words, 27,241 (85.1%) are absent from EPUB text. Words kept only inside preserved images count as absent, and script-specific tokenization differences inflate the figure; it locates problems, it does not score fidelity.

## Visual and textual evidence

Review pages were compared against rendered source pages; `selected-page-xhtml.json` retains the exact XHTML. `source-page-3.png` is the 100 DPI source raster for the key finding.

- Page 16 prose reflows in two-column order with correct amounts and embedded Latin, but spaces are inserted between CJK characters at justified-line joins and the two-line rule-14 heading becomes two headings ([#42](https://github.com/vocaro/PDFReflowLib/issues/42)).
- Page 3 emits both text columns as tall preserved-region crops, and page 1 loses its contents and 未来进展 paragraph the same way ([#36](https://github.com/vocaro/PDFReflowLib/issues/36)). The cover title splits into two headings.
- Most absent words are the EIC lookup tables on pages 24-34, which are preserved as images; that representation is expected for dense tables.

The corpus review JSON holds manual acceptance targets for the known failures. The regression contract checks only source-verified output and does not bless the defects above.
