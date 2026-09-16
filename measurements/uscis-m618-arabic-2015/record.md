# USCIS Arabic guide baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated macOS arm64 release CLI.
Corpus: Welcome to the United States: A Guide for New Immigrants (M-618-A, Arabic, rev. 09/15); 116 pages, 4,156,497 bytes,
SHA-256 `354effbbe38450664959b8832d136cfd158d3c17d1ba777b8b1e4a5b6aa36d54`.
Build: repository `c7db471`, Xcode 27.0 (27A266a), macOS 27.0 (26A428),
`swift build -c release --scratch-path .build/corpus-cli`; executable SHA-256
`2b2bd4ffb98192b64f47b34cd6524e13877d8625f4b37924e167597566a5bb3f`.

## Source and scope

Issue [#30](https://github.com/vocaro/PDFReflowLib/issues/30) candidate. Rights and provenance are recorded in `corpus/manifest.json`; the fresh-download identity check is in `../corpus-candidates-30/verification.json`. No source PDF or full EPUB is committed.

Tagged InDesign CS6 export; 129 fonts, four without ToUnicode. Arabic body text with embedded English terms, form numbers, URLs and phone numbers; photographs, a card specimen and section-divider pages. USCIS states some images are licensed, so no page rasters are committed for this case.

`source-inspection.json` records Poppler 26.04.0 metadata, per-review-page fonts and `pdftotext -layout` text. That extraction is evidence of the source text layer, not a reference transcription.

## Conversion and resource gate

The gated conversion through `tools/run_corpus_regressions.py` completes in 8.33 seconds. Kernel peak RSS is 148,684,800 bytes (141.8 MiB),
below the 256 MiB regression ceiling. Sampled physical footprint is 180.7 MiB.
Only converter RSS is gated; Apple services and physical iOS devices are not measured.

The EPUB is 104,109,827 bytes and passes EPUBCheck 5.3.0 with no errors or warnings. All 481 progress
events pass monotonicity, bounds and completion checks. The report counts 107 reflowed pages, 3 OCR pages and 213 images.
Warnings: 162 imageRegion, 100 structureFallback, 99 furnitureRemoved, 63 annotationsNotConverted, 3 ocrUsed, 3 pageImageFallback.
The reviewed contract passes 9 checks on pages 5, 21.

Of 25,008 Poppler-extracted source words, 9,311 (37.2%) are absent from EPUB text. Words kept only inside preserved images count as absent, and script-specific tokenization differences inflate the figure; it locates problems, it does not score fidelity.

## Visual and textual evidence

Review pages were compared against rendered source pages; `selected-page-xhtml.json` retains the exact XHTML.

- Arabic words extract as correct Unicode, and the contents heading and entries on page 5 appear in source order, though entries flow together into long paragraphs.
- Page 21 fragments right-to-left sentences at visual line breaks, reverses I-551 to 551-I and the phone number to 3676-870-800-1, mirrors (USCIS) to .)USCIS(, moves sentence periods to line starts and emits two Arabic letters as superscripts ([#41](https://github.com/vocaro/PDFReflowLib/issues/41)).
- Three textless divider pages use OCR and page-image fallback.

The corpus review JSON holds manual acceptance targets for the known failures. The regression contract checks only source-verified output and does not bless the defects above.
