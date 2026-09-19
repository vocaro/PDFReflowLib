# Census unmapped-encoding baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated macOS arm64 release CLI.
Corpus: Disclosure Risk Assessment in Perturbative Microdata Protection (Research Report Series, Statistics #2002-01); 20 pages, 187,466 bytes,
SHA-256 `0f97380ae4308581bd70013b7317faafd7c217654236bd31d1448f26eae56905`.
Build: repository `c7db471`, Xcode 27.0 (27A266a), macOS 27.0 (26A428),
`swift build -c release --scratch-path .build/corpus-cli`; executable SHA-256
`2b2bd4ffb98192b64f47b34cd6524e13877d8625f4b37924e167597566a5bb3f`.

## Source and scope

Issue [#30](https://github.com/vocaro/PDFReflowLib/issues/30) candidate. Rights and provenance are recorded in `corpus/manifest.json`; the fresh-download identity check is in `../corpus-candidates-30/verification.json`. No source PDF or full EPUB is committed.

Word cover followed by LaTeX distilled with Acrobat Distiller 4.05. All 17 fonts lack ToUnicode (Poppler); body Type 1C fonts use custom encodings. Poppler and PDFKit both extract the body as letters shifted by three (page 3: Two data files were used. extracts as Wzr gdwd ohv zhuh xvhg1) while the rendered pages are correct.

`source-inspection.json` records Poppler 26.04.0 metadata, per-review-page fonts and `pdftotext -layout` text. That extraction is evidence of the source text layer, not a reference transcription.

## Conversion and resource gate

The gated conversion through `tools/run_corpus_regressions.py` completes in 0.52 seconds. Kernel peak RSS is 39,829,504 bytes (38.0 MiB),
below the 128 MiB regression ceiling. Sampled physical footprint is 21.0 MiB.
Only converter RSS is gated; Apple services and physical iOS devices are not measured.

The EPUB is 2,259,764 bytes and passes EPUBCheck 5.3.0 with no errors or warnings. All 93 progress
events pass monotonicity, bounds and completion checks. The report counts 20 reflowed pages, 0 OCR pages and 41 images.
Warnings: 18 imageRegion.
The reviewed contract passes 6 checks on pages 1.

Of 7,547 Poppler-extracted source words, 3,650 (48.4%) are absent from EPUB text. Words kept only inside preserved images count as absent, and script-specific tokenization differences inflate the figure; it locates problems, it does not score fidelity.

## Visual and textual evidence

Review pages were compared against rendered source pages; `selected-page-xhtml.json` retains the exact XHTML. `source-page-3.png` is the 100 DPI source raster for the key finding.

- Page 1 converts cleanly and is the contract's only protected page.
- Pages 2-20 ship shifted-letter text as paragraphs. The only warnings are imageRegion crops for equations and tables; nothing marks the text as unreadable and OCR is not attempted ([#38](https://github.com/vocaro/PDFReflowLib/issues/38)).
- The word-coverage figure is not meaningful for this case: both the source extraction and the EPUB carry the same wrong letters.

The corpus review JSON holds manual acceptance targets for the known failures. The regression contract checks only source-verified output and does not bless the defects above.

Update (2026-09-19): the findings above are the retained failing baseline from before `TextEncodingCheck`
was ported onto main (#38). Pages 2-20 now report `damagedTextEncoding`, keep a source-page image
and are recognized by default (`recognizedPageCount` 19); the RSS ceiling is 512 MiB (measured peak
about 270 MiB). Pages 1-3 were re-reviewed against Poppler rasters after the port; the contract now
covers those three pages, including page 3's exact sentence "Two data files were used." and its 16
numbered fields, read directly off the source raster. Pages 4-20 are not individually re-verified,
only confirmed to share the same warning/recognition pattern.
