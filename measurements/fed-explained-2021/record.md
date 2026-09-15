# The Fed Explained baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated macOS arm64 release CLI.
Corpus: owner-supplied eleventh edition, August 2021, 135 pages, 4,032,813 bytes; SHA-256
`8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60`.
Build: repository `f701da8`, Xcode 27, macOS 27.0 (26A428),
`swift build -c release --scratch-path .build/corpus-cli`. Executable SHA-256:
`6ae1a17ef314531255ad1e768c4c75c6739483fe793de6627d8f9b5b2021602f`.

## Conversion and validation

The final fresh-process run takes 13.58 seconds with 464,437,248 bytes peak RSS (442.9 MiB),
below the initial 768 MiB ceiling. Sampled physical footprint peaks at 393,512,160 bytes.
Output is 72,194,450 bytes, with 127 pages counted as reflowed, 27 recognized pages and 281
images. All 595 progress events pass monotonicity, bounds and completion checks. EPUBCheck
5.3.0 reports zero errors/warnings. These are one-run process measurements, excluding separate
Apple services, not mobile-device budgets, latency distributions or fidelity scores.

Generated result, memory samples and EPUBCheck log are retained unchanged. The complete
progress log is losslessly compressed and its original identity is recorded. Comparison
metadata identifies a separate full conversion with ten prepared review pages. Original PDFs
and complete EPUBs are not committed.

## Source structure and fidelity

`source-inspection.json` records pypdf 6.10.0 inspection of the pinned source. Raw structure
roles include 11 tables, 94 rows and 41 figures; these counts are not an audit of tag accuracy.
Some figures carry detailed alternate text. The converter does not consume the structure tree
or propagate source figure descriptions; fallback images use generic descriptions.

Browser/source spot checks cover physical pages 45 and 46. Screenshots retain the comparison;
selected XHTML fragments provide exact baseline output for additional review targets.

- Page 45 preserves the policy diagram and adjacent prose as a whole-page raster following an
  unsupported-graphics warning. It is displayed far too small in the review pane, reproducing
  the existing fallback-scaling defect (issue #3). Presence of the image does not establish
  readable diagrams at ordinary reader widths.
- Page 46 promotes ordinary body lines, including “funds rate and other short-term interest
  rates”, to separate heading elements. The source shows paragraph text beside a sidebar and
  above Table 3.1. This is a [heading-classification defect](https://github.com/vocaro/PDFReflowLib/issues/12) even though the PDF has structure tags.
- Recurring table pages and figure arrows remain review targets. Raster preservation does not
  provide semantic table cells, editable vector diagrams, or source alternate text. The full
  book is not fidelity-qualified.

Screenshots and extracts retain the source publication's attribution and rights, separate from
the library MIT license. The owner confirms commercial use and redistribution of this corpus.
