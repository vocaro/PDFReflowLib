# 9/11 Commission report baseline

Tier: deterministic on-device Apple PDF/OCR stack, library defaults, isolated release CLI.
Source: owner-supplied 585-page full GPO report, SHA-256 `657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b`,
2,475,163 bytes. Build: repository `27d827b`, Xcode 27, macOS 27.0 (26A428) arm64,
`swift build -c release --scratch-path .build/corpus-cli`. Executable SHA-256:
`6ae1a17ef314531255ad1e768c4c75c6739483fe793de6627d8f9b5b2021602f`. No LLM/PCC is used.

## Conversion and validation

The final fresh-process run completes in 9.43 seconds with
120,012,800 bytes peak RSS (114.5 MiB), below
the configured 256 MiB case ceiling. Sampled peak physical footprint is
164,512,584 bytes, a different metric. EPUB size is
67,662,420 bytes. The report counts 577 pages with reflowed text, eight recognized
pages and 331 images. EPUBCheck 5.3.0 reports zero errors/warnings; 1,568 CLI progress events
pass monotonicity, bounds and completion checks. The counters are not text-coverage or fidelity
scores. This is one Mac process run, excluding separate Apple services, not an iOS budget or
repeated in-app conversion measurement.

The baseline follows an exploratory run used to choose the ceiling. `result.json`,
`memory-samples.json` and `epubcheck.log` retain the final generated receipts unchanged;
`progress.log.gz` losslessly compresses the complete log and `progress-identity.json` pins its
uncompressed bytes. No source PDF or complete EPUB is committed.

## Source and spot checks

`source-inspection.json` records the absent structure tree, permissions and extraction samples.
The file uses RC4 permissions encryption, permits copying/printing, and opens for conversion
without a password prompt; its encryption is not removed or rewritten. The metadata title is
`201-635.job`; clients can override the book title through conversion options. Poppler finds
nonempty text on 577 pages. This is a digital original, not the scanned Warren corpus.

`comparison-identity.json` identifies a separate complete-book conversion with the same source
and executable. Ten physical pages are prepared in `.build/911-comparison`; whole-book context
is preserved. Browser/source spot checks cover 19, 20 and 472. `selected-page-xhtml.json` retains
exact baseline fragments for eight inspected pages; other review points remain unqualified.

- Pages 15/19: PDFReflowLib correctly emits “We present” and “Tuesday, September 11, 2001”.
  Poppler layout extraction produces the reported split-word forms. These are useful positive
  regression targets, not failures reproduced in PDFReflowLib. No general spacing accuracy
  claim follows from these two phrases.
- Pages 20/21 and 66: alternating report/chapter headers survive as body paragraphs.
- Pages 471/472: chapter-specific endnote headers become `<h2>` navigation headings.
  These are concrete false-heading examples, not a heading-precision score.
- Pages 19/65: multiline chapter titles become several headings, while section headings
  1.1/2.1 remain body text. Genuine structure needs review alongside header suppression.
- Page 20: the superscript endnote marker after 7:45 becomes ordinary baseline text (`7:45.4`).
  Page 472's notes 38/39 use preformatted blocks and note 40 splits mid-sentence. Endnote links
  are not reconstructed by the current writer. Note text and its associations are not fully
  qualified by EPUBCheck.

Screenshots retain the browser comparisons. They are government-report excerpts, not library
code relicensed under MIT. No blanket rights claim is made for third-party report illustrations.
The timeline page 50 is a review candidate, not visually adjudicated in this addition; keep its
labels associated with preserved graphics rather than deleting them to improve heading counts.

## External prototype finding: deferred issue #10

The owner supplied details from a separate Claude session's throwaway Chapter 1 conversion:
508 text blocks, 54 ALL-CAPS heading candidates, four genuine headings (chapter title and
sections 1.1, 1.2, 1.3). Reported classifications are 46 page headers and 50 non-headings overall,
including map fragments. Those categories account for the two quoted counts; they must not be
presented as two PDFReflowLib measurements. The external research note identifies pdfminer.six
sample extraction and a distinct 850,415-byte Chapter 1 granule with SHA-256
`b2edd40aadec313985abe2c770c4fa692eb8b20fc3403cc43b8460a74c006247`.
The discarded prototype outputs and exact tool versions are not available here. The external
estimate of about 1,700 endnotes is likewise not an inventory measured by this addition.

[Issue #10](https://github.com/vocaro/PDFReflowLib/issues/10) retains the methodology, definitions
and future investigation: stable-position recurrence, alternating/chapter-local headers,
true heading preservation and graphic-label ownership. No fix or full precision audit is part
of this corpus addition. The original document's corpus role does not propose it for a catalog.
