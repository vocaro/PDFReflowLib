# Our Flag baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated macOS arm64 release CLI.
Corpus: Our Flag, House Document 108-97, Joint Committee on Printing / GPO, 2003;
56 physical pages, 1,103,159 bytes, SHA-256
`a47a3153b649022a52b53e7b0c40b55bfea24e7980bbe32fe6fee0cf1936bbd8`.
Build: repository `3e6e61e`, Xcode 27, macOS 27.0 (26A428),
`swift build -c release --scratch-path .build/corpus-cli`. Executable SHA-256:
`9fed7af9cb6872ef13a596f1df9512fb9236e66a67e43db96e3637a9eeb4a0e8`.

## Conversion and regression gate

The measured run completes in 1.78 seconds. Kernel peak RSS is 121,585,664 bytes
(116.0 MiB), below the configured 192 MiB regression ceiling. Sampled physical footprint is
184,206,224 bytes (175.7 MiB); footprint and RSS are different metrics, and only RSS is gated.
The 13,485,363-byte EPUB passes EPUBCheck 5.3.0 with no errors or warnings. All 256 progress
events pass bounds, monotonicity and completion checks. The report counts 55 pages with
reflowed text, five OCR pages and 128 images. These counts do not establish semantic coverage.
The initial ungated run measures 121,503,744 bytes RSS and 1.88 seconds; the retained final
receipts are the configured-gate run. No physical iOS device or separate Apple service is measured.

The fresh official GovInfo download matches the independently supplied original. Both copies
remain outside Git in ignored/local caches. Generated result, conversion, memory and validation
receipts are unchanged; the complete progress log is losslessly compressed with its original
identity. Exact XHTML is retained for eight review pages. The comparison uses another complete
conversion and Poppler 26.04.0; `comparison.json` records those commands.

## Structure inspection

`source-inspection.json` records pypdf 6.10.0 structure traversal and selected page text. The
catalog contains a populated StructTreeRoot but MarkInfo.Marked is false, explaining Poppler's
`Tagged: no` report. The tree has 361 P, 204 Span, 103 Figure, 35 Sect, 23 H2, nine H3, two H4,
one H1, one Part and 15 LI entries. Physical pages 3–54 have StructParents. RoleMap is empty.
There are no Table/TR/TH/TD roles and no Figure Alt entries. Page 27 has two H2 entries.
This is a useful mixed-quality structure reference, not a fully validated accessible PDF:
MCID coverage, association correctness and logical ordering are not exhaustively validated.
The current library uses layout heuristics and does not consume these tags.
[Issue #17](https://github.com/vocaro/PDFReflowLib/issues/17) tracks validated tag consumption
with fallback and explicit tests that distinguish semantic order from geometry.

## Fidelity evidence

Source rasters and the rendered three-pane comparison are visually checked on pages 27 and 33.
The four emitted state-flag image assets on page 33 are also visually checked. Other review
pages have exact XHTML and prepared comparison views, not complete visual adjudication.

- Page 27 (printed 21): both drop-cap paragraph openings become h2 headings and follow their
  own continuation lines. The split `fab` / `rics` is in the wrong order. The page emits four
  h2 elements against two actual section titles. Page 7's XHTML similarly places the second
  body line before the opening sentence. [Issue #12](https://github.com/vocaro/PDFReflowLib/issues/12)
  contains this additional reproduction; the extraction/layout cause remains unisolated.
- Page 27's ten-row flagpole-height / flag-size table collapses into one paragraph with dot
  leaders. There is no semantic table or table-region image. The review JSON records all ten
  checked reference pairs for future assertions. [Issue #16](https://github.com/vocaro/PDFReflowLib/issues/16)
  requires row associations or readable image preservation, independent of absent source table tags.
- Page 33: California, Colorado, Connecticut and Delaware images survive, but descriptions
  interleave between columns and separate from their images. A decorative rule receives a generic
  figure caption; the printed page number becomes h2. [Issue #2](https://github.com/vocaro/PDFReflowLib/issues/2)
  includes the smaller reproduction and complete-group ordering acceptance criteria.
- Poppler positioned HTML retains the page arrangement in the checked views. It is a geometric
  comparator, not evidence of semantic reflow; original source rasters remain the visual reference.

The baseline qualifies package validity, completion, progress and a Mac process-memory limit.
It fails the stated table and flag-group fidelity targets. The review JSON is a reference for
future fixes; these fidelity expectations are not represented as passing automated assertions.
