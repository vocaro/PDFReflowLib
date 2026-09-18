# Serialized extraction still aborting with the NSFont exception (#21)

macOS 27.0 (26A428), Xcode 27.0 (27A266a), arm64, 18 cores, 2026-09-18. Other agents were running
corpus lanes on the machine throughout; the load average of each campaign is in the logs (roughly
30 to 120).

## What the recurrences show

The last comment on #21 reports the abort after 58da4de serialized extraction: 1 of 8 processes of
the `check-all.sh` smoke gate, and a `swift test` run. Their crash reports were still in
`~/Library/Logs/DiagnosticReports`:

- `probe-2026-09-16-220332.ips` (the smoke gate, `untagged-native-w8`): the aborting thread is
  inside `NativeTextReader.lines`, in `withExtractionLock`, in
  `-[PDFSelection attributedString]`. The other seven workers all wait in `-[NSLock lockBeforeDate:]`.
  Nothing else in the process was in PDFKit when it aborted, and it is one process: separate
  processes play no part.
- `swiftpm-testing-helper` on 09-16 11:50, 09-17 12:59 and 09-17 16:09: each aborts inside
  `withExtractionLock` too. The other threads run unrelated tests (layout, OCR raster analysis,
  PNG encoding, a test calling `NativeSpacingReader.read` directly).

The exception comes from one PDFKit block. Disassembled (`dyld_info -disassemble` on PDFKit, stub
selectors read in lldb), `__60-[PDFSelection createAttributedStringForCGSelection:scaled:]_block_invoke`
takes each run's CoreText font, calls `-[NSFont fontWithSize:]` with its size times the scale, and
stores the result under `NSFont` with `setObject:forKey:`. The abort is that call returning nil.

## Where the gate leaked

`scope-probe.swift` (Apple SDKs only) extracts attributed text under a lock and varies what else
the process does. Each process runs 8 threads; the extracting thread opens its own document every
iteration. Counts are processes that aborted with the NSFont exception
(`scope-probe-campaigns.jsonl`):

| Other threads, meanwhile | Lock covers | Aborted |
|---|---|---|
| none (one thread) | extraction | 0 / 146 |
| 7 more locked extractors | extraction only; pool drained after unlock | **19 / 310** |
| 7 more locked extractors | extraction and its autorelease drain | 0 / 170 |
| 7 more locked extractors | extraction, drain, page and document release | 0 / 163 |
| 7 more locked extractors | the whole iteration (open to release) | 0 / 169 |
| opening and releasing documents | extraction | 0 / 139 |
| drawing the page (`drawPDFPage`) | extraction | 0 / 110 |
| plain `PDFPage.string`, selection strings | extraction | 0 / 95 |
| drawing free-text and widget annotations | extraction | 0 / 129 |
| `NSFont(name:size:)`, `withSize` | extraction | **75 / 182** |
| `CTFontCreateWithName`, `CTLineDraw` | extraction | **3 / 59** |
| `NSFont(name:size:)` under the lock, released after | extraction and drain | 0 / 90 |
| `CTFontCreateWithName`, `CTLineDraw` under the lock | extraction and drain | 0 / 82 |

So the lock was never bypassed; its scope was short. PDFKit returns the selections and attributed
strings autoreleased, and the fonts they carry go with them. `withExtractionLock` released the lock
before the caller's pool drained them (the pipeline's per-page `autoreleasepool`, the probe's
per-iteration one), so one thread released those fonts while the next held the gate and called
`fontWithSize:`. Making a font or laying out a CoreText line on another thread does the same; opening
and releasing documents, drawing pages or annotations, and plain-text reads did not.

## Fix

- `NativeTextReader.withExtractionLock` runs its operation in an `autoreleasepool` inside the lock,
  so everything the extraction autoreleased is released before another thread can extract. All
  library PDFKit text reads already ran inside that gate (`NativeTextReader.lines`,
  `AnnotationEvidence`'s field text, `MathRecognizer.glyphs` from the pipeline), and the library
  makes no font of its own.
- Tests make fonts, lay out and draw CoreText lines, and read PDFKit text through `pdfKitGated`
  (`Tests/PDFReflowLibTests/PDFKitGate.swift`), which holds the same lock. Parallel tests share
  their process with the library's gated extraction; 40 gated sites in 20 test files now cover
  calls that were outside it.
- `tools/check_pdfkit_gate.py`, run by `tools/test_pdfkit_gate.py`, fails on any PDFKit text read
  (`attributedString`, `selectionsByLine`, `selection(for:/from:)`, character geometry, page
  `string`, …), font construction or CoreText line call in `Sources/` or `Tests/` outside those
  closures. A `private` or nested function passes its call to its callers in the same file.

## Before and after, with the real extraction

The repository's probe (`tools/probe-pdfkit-concurrency.swift` compiled with the library's
extraction sources, exactly as `check_pdfkit_concurrency.py` builds it), from the tip's sources
(`base`) and from this change (`fix`), 8 workers × 1,000 extractions per process, both builds
running side by side under the same load, alternating the RoleMap and untagged fixtures
(`drive-native-probe.py`, `native-probe-campaigns.jsonl`):

| Round | base aborted | fix aborted |
|---|---|---|
| r1 | 7 / 107 | 0 / 105 |
| r2 | 4 / 74 | 0 / 73 |
| r3 | 2 / 78 | 0 / 77 |
| r4 (two lanes each) | 5 / 233 | 0 / 230 |
| **total** | **18 / 492 (3.7%)** | **0 / 485** (3.88 million extractions) |

Every base abort is `setObject:forKey: object cannot be nil (key: NSFont)`. At base's rate, 485
clean processes by chance is about 1 in 70 million. The unchanged smoke tool then passed 200 of 200
fresh processes on the fix (`--modes native --workers 1 8 --trials 50 --iterations 1000`, 900,000
extractions; the gate runs 8 processes of 50). `swift test` passed 10 consecutive runs of 1,025
tests under the same machine load.

Output is unchanged: FAA, Fed, Wallace and TechPort converted by the tip and by this change give
byte-identical EPUB entries (XHTML, navigation, CSS and 3,563 images), except for the OPF's
modification time and generated identifier.

## Limits

The lock is process-local and cooperative. A host application that makes fonts, draws text or
reads PDFKit text on another thread while a conversion extracts can still hit the Apple exception
(FB24796210); so can a test that bypasses `pdfKitGated` in a way the lexical check cannot see.
Test font objects are released outside the lock; the campaigns found that harmless for fonts made
under it.
