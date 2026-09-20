# Draining autoreleased fonts before releasing the extraction gate

> The Swift probes moved to `tools/probes/`, and `tools/pdfreflow_tools/swift_sources.py` now owns the library source list each one compiles with (`6e6ba6c`); the paths and hand-copied source lists below are as measured.

This closes the residual crash reported against the serialization lock in
[#21](https://github.com/vocaro/PDFReflowLib/issues/21): even with `NativeTextReader`'s
process-wide extraction lock in place (`58da4de`), an eight-worker native stress campaign still
aborted occasionally with PDFKit's `NSFont` exception. This does not close #21 — the underlying
Apple SDK bug (FB24796210) and independent host PDFKit/font/CoreText calls made outside this
library's lock remain open regardless of this fix.

## Cause

`PDFSelection.attributedString` and the fonts its runs carry are autoreleased. `withExtractionLock`
unlocked before those objects were freed. One thread could free a font from a just-completed
extraction while another thread, already inside the gate, asked `-[NSFont fontWithSize:]` for a
new one; that call returned `nil` and PDFKit's `createAttributedStringForCGSelection:scaled:`
threw trying to store it. The two threads never executed extraction concurrently — the lock
still worked as designed — but freeing the first thread's autoreleased objects raced the second
thread's PDFKit call.

## Fix

`NativeTextReader.withExtractionLock` now wraps the protected operation in `autoreleasepool`,
draining it before `unlock()` runs (see the `defer`/pool ordering in
`Sources/PDFReflowLib/NativeTextReader.swift`). Autoreleased fonts and attributed strings are
freed before the next waiter can enter PDFKit, eliminating the race.

Forty test call sites across `Tests/PDFReflowLibTests/` construct fonts, draw CoreText lines, or
read PDFKit text outside the library — plausible sources of the same interference, since PDFKit's
attributed extraction aborts when *any* thread of the process does this work while a gated
extraction runs, not only when it's the library's own second extraction. Every such call site
found by `tools/check_pdfkit_gate.py` (26 across 8 files, several files with more than one call
inside a shared private helper it also chases through callers) now takes the library's real lock
through a new test helper, `pdfKitGated` (`Tests/PDFReflowLibTests/PDFKitGate.swift`).
`tools/check_pdfkit_gate.py` — a lexical Swift scanner, not a compiler plugin — fails the build
on any future PDFKit/font/CoreText call in `Sources/` or `Tests/` left outside
`withExtractionLock`/`pdfKitGated`; its own behavior is covered by `tools/test_pdfkit_gate.py`
(6 cases), picked up automatically by `python3 -m unittest discover -s tools -p 'test_*.py'`.

## Reproduction

`tools/check_pdfkit_concurrency.py --modes native --workers 8` compiles
`tools/probe-pdfkit-concurrency.swift` directly against `NativeTextReader.swift` and the other
library value-type sources (`-D PDFREFLOW_NATIVE`), so it exercises the real fix, not a
reimplementation. To confirm the drain is what closes the gap (not just that the suite still
passes), the fix was temporarily removed from `withExtractionLock` (reverting to
`return try operation()`, no `autoreleasepool`) and the same campaign re-run before restoring it.

Host and inputs: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple Swift 6.4, arm64, release
optimization, 1,000 opens/worker per process, both the RoleMap/MCR and untagged fixtures from
`check_pdfkit_concurrency.py`, `git` HEAD `3c7d08e` (working tree, drain hunk toggled by hand
between runs; `before-identity.json`/`after-identity.json` record the two distinct
`NativeTextReader.swift` source hashes actually compiled for each campaign).

| Campaign | Work | Outcome |
| --- | --- | --- |
| Drain removed (`before-results.json`) | 8 workers, 1,000 opens/worker, 40 trials x 2 fixtures = 80 processes | 78/80 pass; 2 processes abort with the `NSFont` exception |
| Fix present (`after-results.json`) | 8 workers, 1,000 opens/worker, 35 trials x 2 fixtures = 70 processes | 70/70 pass; 560,000 completed extraction iterations |

The failing-run stack trace (`drain-removed-crash-2026-09-19.stderr.log.gz`) matches the issue's
reported trace exactly: `NSInvalidArgumentException`, `setObject:forKey: object cannot be nil
(key: NSFont)`, inside `-[PDFSelection createAttributedStringForCGSelection:scaled:]` reached
through `-[PDFSelection attributedString]` from `NativeTextReader.extractLines`.

This is a smaller campaign than the coordination branch's own validation of the same fix
(492/485 eight-worker processes, 3.88M extractions) — bounded by the time available for this
port, not by lower confidence in the mechanism. A 2/80 (2.5%) crash rate without the drain and
0/70 with it, on top of the exact stack-trace match, is consistent with the branch's own
finding and with the mechanism described above, but it remains a finite passing campaign, not
proof that all concurrent PDFKit use is now safe. It does not qualify physical iPhone/iPad
concurrency, a host application's independent PDFKit/font/CoreText calls, or Apple's own
diagnosis of FB24796210, all of which stay open per the issue.

## Full suite

All Swift tests (`swift test`) and the full `check_pdfkit_gate.py` scan pass with the fix and the
new test-site gating in place; see the commit message for exact counts.
