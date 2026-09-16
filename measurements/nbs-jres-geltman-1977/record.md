# NBS scanned journal paper baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated macOS arm64 release CLI.
Corpus: Stimulated Multiphoton Bremsstrahlung in Electron-Ion Collisions; 7 pages, 7,303,514 bytes,
SHA-256 `44653967317ce75f324b8051cdf2f123429ca1cbd199fefbffabe9acb9b0c86d`.
Build: repository `c7db471`, Xcode 27.0 (27A266a), macOS 27.0 (26A428),
`swift build -c release --scratch-path .build/corpus-cli`; executable SHA-256
`2b2bd4ffb98192b64f47b34cd6524e13877d8625f4b37924e167597566a5bb3f`.

## Source and scope

Issue [#30](https://github.com/vocaro/PDFReflowLib/issues/30) candidate. Rights and provenance are recorded in `corpus/manifest.json`; the fresh-download identity check is in `../corpus-candidates-30/verification.json`. No source PDF or full EPUB is committed.

Scanned journal paper processed by Adobe Acrobat 9 Paper Capture: page scans with a HiddenHorzOCR text layer. Two columns, footnotes under a rule, numbered display equations and a spanning figure. Pages 1-6 contain inline stencil images (BI/EI); page 7 does not.

`source-inspection.json` records Poppler 26.04.0 metadata, per-review-page fonts and `pdftotext -layout` text. That extraction is evidence of the source text layer, not a reference transcription.

## Conversion and resource gate

The gated conversion through `tools/run_corpus_regressions.py` completes in 0.73 seconds. Kernel peak RSS is 268,189,696 bytes (255.8 MiB),
below the 512 MiB regression ceiling. Sampled physical footprint is 41.1 MiB.
Only converter RSS is gated; Apple services and physical iOS devices are not measured.

The EPUB is 6,509,733 bytes and passes EPUBCheck 5.3.0 with no errors or warnings. All 33 progress
events pass monotonicity, bounds and completion checks. The report counts 1 reflowed pages, 0 OCR pages and 8 images.
Warnings: 6 unsupportedGraphics, 6 furnitureRemoved, 6 pageImageFallback, 2 imageRegion, 1 unverifiedTextLayer, 1 uncertainHyphen.
The reviewed contract passes 7 checks on pages 1, 2, 7.

Of 5,408 Poppler-extracted source words, 4,891 (90.4%) are absent from EPUB text. Words kept only inside preserved images count as absent, and script-specific tokenization differences inflate the figure; it locates problems, it does not score fidelity.

## Visual and textual evidence

Review pages were compared against rendered source pages; `selected-page-xhtml.json` retains the exact XHTML. `source-page-7.png` is the 100 DPI source raster for the key finding.

- Pages 1-6 report unsupportedGraphics and pageImageFallback: GraphicsReader marks the inline stencil images (EI) as unsupported, so these pages keep appearance but no text reflows ([#37](https://github.com/vocaro/PDFReflowLib/issues/37)).
- Page 7 reflows. Its closing left-column prose becomes a crop while the final line reflows separately ([#36](https://github.com/vocaro/PDFReflowLib/issues/36)); References is emitted as preformatted text; reference entries carry OCR noise and some entries merge. unverifiedTextLayer is reported.
- The contract protects the explicit fallback and warning signals, not reflow quality.

The corpus review JSON holds manual acceptance targets for the known failures. The regression contract checks only source-verified output and does not bless the defects above.
