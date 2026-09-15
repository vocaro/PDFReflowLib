# PDFKit attributed-string extraction leaks memory after document/page release

Suggested area: macOS / PDFKit (or the PDF framework component available in Feedback Assistant).
Type: Incorrect/Unexpected Behavior; memory leak during repeated document processing.

## Summary

A standalone Swift command-line program using only Foundation, PDFKit and Darwin repeatedly
opens PDF documents inside autorelease pools, reads a page's attributedString, and releases all
PDFDocument, PDFPage and attributed-string references at the end of each page iteration.
Memory accumulates across passes. Apple's leaks tool reports 75,269 leaked allocations
(247,048,656 bytes) after a separate one-pass run. Allocation stacks include
PDFPage.attributedString, PDFSelection.attributedStringScaled:,
CGPDFSelectionCreateAttributedString and PageLayout::CreateAttributedStringForStringRanges.

No PDFReflowLib code, third-party dependencies, EPUB packaging or retained extracted-content
collections participate in this reproducer. Only character counts and scalar memory records
are retained between page iterations.

## Environment

ProductName:		macOS
ProductVersion:		27.0
BuildVersion:		26A428
arm64
Mac17,6
38654705664
Xcode 27.0
Build version 27A266a

The two hardware values following arm64 are the Mac model identifier and installed RAM bytes.
Fresh diagnostics are collected on 2026-09-14 local time. Physical iOS/iPadOS reproduction has
not been performed. This report does not assert that every converter memory allocation leaks.

## Steps to reproduce

1. Unzip the attached bundle. It contains the public U.S. Government FAA handbook (522 pages),
   the 47-line standalone probe, debug-only entitlements, commands and diagnostic output.
2. Select a full Xcode installation with xcode-select, or set DEVELOPER_DIR appropriately.
3. Run `bash reproduce.sh`. It builds the standalone probe with `swiftc -O -g`, signs only that
   temporary diagnostic executable with get-task-allow, then runs three independent processes:
   plain text (three passes), attributed text (three passes), and stack-logged attributed text
   (one pass). `leaks` may return nonzero when leaks are detected; inspect its output.
4. Compare physicalFootprintAfterPassBytes in the two JSONL files and inspect leaks-reproduced.txt.

The source PDF is also available at:
https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/faa-h-8083-25c.pdf
SHA-256: 247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7
Size: 77,598,564 bytes. Verify identity if using a download instead of the attachment.

## Expected result

After all per-page objects leave scope and the autorelease pool drains, attributed extraction
should release its owned objects. Framework caches may retain memory, but repeated passes
should not continuously accumulate unreachable attributed strings and decoded image storage.

## Actual result

After-pass physical footprint in bytes, measured with task_info(TASK_VM_INFO), using separate
processes without MallocStackLogging:

| Pass | Plain selection strings | Page attributedString |
| --- | ---: | ---: |
| 1 | 89,850,936 | 1,553,254,488 |
| 2 | 634,406,064 | 2,375,699,336 |
| 3 | 608,552,136 | 3,207,876,280 |

The separate one-pass MallocStackLogging diagnostic reports 75,269 leaked allocations totaling
247,048,656 bytes. The full stack log is attached. Leaked root attributed strings retain attribute
storage including decoded CGImage/CGDataProvider data. This supports a leak along this framework
path; Apple must determine the precise internal ownership defect.

Peak RSS is also recorded in summary.json, but it is a different metric from physical footprint.
Stack logging changes memory use and timing. Recorded control/attributed processes overlap in
wall time; the report makes no timing comparison or physical-device memory-budget claim.

## Impact and workaround

Our on-device PDF-to-EPUB library needs font attributes and baseline offsets to preserve useful
formatting and distinguish scripts. Multi-document or large-document processing can accumulate
substantial memory despite bounded per-page lifetimes. Avoiding all attributed-text extraction
loses formatting information; skipping unnecessary reads reduces exposure but is not a fix.
The library's separate image-output safety ceiling is not being reported as an Apple defect.

Related public tracking: https://github.com/vocaro/PDFReflowLib/issues/4
The attached input is a public government publication; no private user documents are included.
