# Loper Bright footnote baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated macOS arm64 release CLI.
Corpus: Loper Bright Enterprises v. Raimondo, No. 22-451 (slip opinion); 114 pages, 637,387 bytes,
SHA-256 `12f5ea075004886774c25e7831ea1608fd0f831f0113e83bb0e85811c0a4bb6e`.
Build: repository `c7db471`, Xcode 27.0 (27A266a), macOS 27.0 (26A428),
`swift build -c release --scratch-path .build/corpus-cli`; executable SHA-256
`2b2bd4ffb98192b64f47b34cd6524e13877d8625f4b37924e167597566a5bb3f`.

## Source and scope

Issue [#30](https://github.com/vocaro/PDFReflowLib/issues/30) candidate. Rights and provenance are recorded in `corpus/manifest.json`; the fresh-download identity check is in `../corpus-candidates-30/verification.json`. No source PDF or full EPUB is committed.

Born-digital, tagged Distiller output; 23 fonts, all with ToUnicode. Single-column slip opinion with majority, concurring and dissenting opinions whose printed folios restart. Footnotes sit under a separator drawn with em-dash characters; footnote 2 of the Kagan dissent continues from page 97 onto page 98.

`source-inspection.json` records Poppler 26.04.0 metadata, per-review-page fonts and `pdftotext -layout` text. That extraction is evidence of the source text layer, not a reference transcription.

## Conversion and resource gate

The gated conversion through `tools/run_corpus_regressions.py` completes in 1.15 seconds. Kernel peak RSS is 38,354,944 bytes (36.6 MiB),
below the 128 MiB regression ceiling. Sampled physical footprint is 20.2 MiB.
Only converter RSS is gated; Apple services and physical iOS devices are not measured.

The EPUB is 97,208 bytes and passes EPUBCheck 5.3.0 with no errors or warnings. All 254 progress
events pass monotonicity, bounds and completion checks. The report counts 114 reflowed pages, 0 OCR pages and 0 images.
Warnings: 115 structureFallback, 66 uncertainHyphen.
The reviewed contract passes 15 checks on pages 60, 97, 98.

Of 39,202 Poppler-extracted source words, 151 (0.4%) are absent from EPUB text. Words kept only inside preserved images count as absent, and script-specific tokenization differences inflate the figure; it locates problems, it does not score fidelity.

## Visual and textual evidence

Review pages were compared against rendered source pages; `selected-page-xhtml.json` retains the exact XHTML. `source-page-98.png` is the 100 DPI source raster for the key finding.

- Nearly all source words reflow (0.4% absent). Footnote markers are superscripts and footnote text is present in source order, including the page 97-98 continuation.
- Footnotes are appended to the last body paragraph with the dash separator, and the page-98 continuation of footnote 2 is merged into that page's body paragraph ([#40](https://github.com/vocaro/PDFReflowLib/issues/40)). Running headers and folios remain as paragraphs.
- 75 wrapped lines that begin with U. S., v., F. or a year followed by a period become separate preformatted blocks, splitting paragraphs; LayoutReconstructor.isList treats them as list items ([#39](https://github.com/vocaro/PDFReflowLib/issues/39)).
- Every page reports structureFallback; the Distiller tags do not match native lines.

The corpus review JSON holds manual acceptance targets for the known failures. The regression contract checks only source-verified output and does not bless the defects above.
