# Wallace algebra baseline

Tier: deterministic on-device Apple PDF/OCR stack, release CLI, library defaults. Corpus:
owner-supplied 489-page *Beginning and Intermediate Algebra*, Tyler Wallace (2010), identified
in `result.json`. Implementation: PDFReflowLib `5c38c48aa107c789d2e2f6d80c0869dca53159eb`,
macOS 27 arm64, Xcode 27. Executable identity is retained in the result. No LLM/PCC is used.

The final fresh-process baseline converts in 8.37 seconds with 85,458,944 bytes peak RSS
(81.5 MiB), below the initial 256 MiB case ceiling. It emits 45,747,613 bytes of EPUB content,
with 481 pages containing reflowed text, no OCR pages and 2,077 images. These counters do not
establish reading order, math fidelity, accessibility or text coverage. EPUBCheck 5.3.0 reports
zero errors/warnings, and 3,086 CLI progress events pass the monotonic/bounds/completion checks.
This is one Mac observation, excluding separate Apple services; physical mobile memory and
repeated in-app conversion remain unqualified.

`result.json`, `progress.log`, `memory-samples.json` and `epubcheck.log` are the final baseline's
unmodified generated receipts. An earlier exploratory run establishes the initial budget;
this final run independently verifies it after review metadata is recorded.

## Visual spot checks

A separate conversion feeds the Poppler comparison harness. `comparison-identity.json` retains
its input, executable, EPUB, harness and tool identities; its complete local bundle remains at
`.build/wallace-comparison`. Eleven physical pages are prepared, but only pages 16, 343, 347 and
479 have visual spot checks. The remaining review points are candidates, not passed tests.

- Page 16: visible fraction exercises remain image crops with their numbers attached.
- Page 343: the displayed derivation is an image, while the introductory squared exponent is
  incorrectly flattened. XHTML literally contains `The general from of a quadratic is ax2 + bx
  + c = 0.` with no superscript element. The source's exponent is raised. This changes math
  semantics and needs a source-derived regression when fixed.
- Page 347: visible left-column quadratic exercises retain powers within the raster region.
- Page 479: visible answers 33-38 retain their number/expression associations and complex roots
  through mixed images/text. The remainder of the answer key is not adjudicated.

`page-16.png`, `page-343.png`, `page-347.png` and `page-479.png` show the corresponding browser
comparisons. Poppler simple HTML is a comparator, not a reference oracle: it also flattens
mathematical notation. Original source rasters are the visual reference. Image preservation
can protect display while losing selectable mathematical structure.

Screenshots contain excerpts from *Beginning and Intermediate Algebra* by Tyler Wallace,
copyright 2010, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/), source identified by
the PDF as <http://wallace.ccfaculty.org/book/book.html>. These are rendered/conversion comparison
excerpts, not original unmodified page files; they retain the book's license and are not MIT.
The source PDF and complete derived EPUB are not committed.
