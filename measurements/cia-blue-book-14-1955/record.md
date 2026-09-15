# Blue Book negative quality baseline

Tier: deterministic Apple PDF stack, defaults, isolated macOS arm64 release CLI.
Corpus: Project Blue Book Special Report No. 14 (1955), CIA-UAP-015 release copy;
312 pages, 24,433,155 bytes, SHA-256
`90e05e77fc088c29758c2ddda514c0c12f317e5686ee213d348db2f9da152ee3`.
Runtime build: repository `156c7ac`, Xcode 27, macOS 27.0 (26A428), release executable SHA-256
`9fed7af9cb6872ef13a596f1df9512fb9236e66a67e43db96e3637a9eeb4a0e8`.
The separate quality-assessment tool is introduced with this record; it evaluates the unchanged
baseline artifacts and does not modify the converter or its warnings.

## Source

The owner supplies this exact release copy. The official PURSUE publisher page identifies the
June 12, 2026 release and the indexed official PDF location matches its filename. Fresh automatic
fetch returns HTTP 403, so independent download identity is not established. The repository
fetcher verifies the manually seeded ignored cache against the supplied bytes and SHA-256.
The PDF and full EPUB are not committed. Physical page 4 states that no copyright material is
contained in the publication; source attribution and the tentative rights record remain separate
from the library license.

Poppler 26.04.0 reports AES-256 encryption with copying disabled and printing enabled. The
file opens without an opening password; PDFReflowLib processes it without changing its bytes
or permissions. The current page source checks PDFKit isLocked, not copying permissions.
Neither this property nor the archival text is treated as a quality decision.

pypdf 6.10.0 finds inherited text on all 312 pages, totaling 832,006 extracted characters.
The structure tree contains 312 Figure entries and no alternate text, heading or table roles.
On checked pages 74 and 150 the text-rendering mode is 3 (invisible), alongside page images.
The mere presence of tags or extracted text does not establish usable table semantics.

## Resource, package and progress result

The configured full run completes in 37.38 seconds, with 307,970,048 bytes peak RSS (293.7 MiB)
under the 512 MiB limit. Sampled physical footprint peaks at 291,177,360 bytes (277.7 MiB).
The 266,665,782-byte EPUB passes EPUBCheck 5.3.0 with no errors or warnings. All 1,066 progress
events pass monotonicity, bounds and completion checks. The report counts 227 pages with
reflowed text, zero fresh OCR pages and 397 images. Warnings are exclusively 397 imageRegion
and 278 furnitureRemoved events. These are one-run Mac process results, excluding separate Apple
services; no physical-device or transcription qualification is claimed.

The first ungated run measures 37.21 seconds and 369,410,048 bytes RSS (352.3 MiB); the retained
result is the later configured-gate run. Generated receipts remain unchanged, including their
historical directory names. The progress log is losslessly compressed with its original identity.
Selected XHTML is extracted from the configured run's EPUB, not the preliminary run.

## Negative quality contract

`tools/check_corpus_quality.py` evaluates the baseline against the manifest's qualityExpectation.
It exits 1: pages 74 and 150 have neither complexLayout nor pageImageFallback warnings, and the
converter has not explicitly refused conversion for quality reasons. `quality-assessment.json`
records this failure. A generic imageRegion notice does not identify unreliable extracted text.

Successful explicit quality refusal requires an approved exact terminal diagnostic, normal CLI
error exit 1, no published EPUB, no staging leftovers, no completion event, no timeout and no
failed configured memory gate. The current API has no quality-refusal error; the approved list
is empty. Crashes, permissions failures and output-budget failures do not qualify. Successful
conversion instead requires the normal evaluation to pass and accepted warnings on both target
pages. The contract tests cover both positive signaling controls and misleading failure modes.

This opt-in quality gate remains red until [issue #19](https://github.com/vocaro/PDFReflowLib/issues/19)
is addressed. Its ordinary instrumentation tests pass; the real-document failure is not silently
reported as a passing quality test. A future passing signal would still not prove table fidelity.

## Visual/textual review

Source pages 74 and 150 are visually inspected and compared with exact emitted XHTML; no
rendered whole-book EPUB review is claimed. Four further pages have retained XHTML and manual
review targets. Page 74's printed numeric rows are transcribed into the review JSON as future
cell-association references, not passing automated fidelity assertions.

- Page 74 (printed 64) is a typewritten chi-square table. Scan-edge marks become repeated I
  headings, an object placeholder becomes a heading, and several table rows collapse into prose.
  Its only warnings concern removed furniture and preservation of the original page image.
- Page 150 (printed 141) is a dense handwritten statistical sheet. Garbled labels, headings and
  numeric strings become formatted prose/headings without an explicit text-quality warning.
  The original page image survives, so this is not complete loss of the source visual content.

Both expose the existing suspect-OCR, scan-font semantics and placeholder problems (#7, #6,
#8), plus the need to signal unreliable reconstruction before clients present it as usable reflow.
