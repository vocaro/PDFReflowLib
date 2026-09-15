# Cancellation while native extraction is contended

This addresses the queued-cancellation portion of [#21](https://github.com/vocaro/PDFReflowLib/issues/21).
The library still serializes native PDFKit extraction. A cancelled waiter can now return before
the active extraction finishes. Apple's underlying NSFont exception, independent host PDFKit
calls and physical-device concurrency remain open; this work does not close #21.

## Mechanism and regression

At baseline `58da4de7c1481dba7455cc9df88eaf813fe9ee3c`, `NSLock.lock()` waits indefinitely
before the next task-cancellation check. The regression holds the actual library extraction
gate on a dedicated thread, starts a native reader in another task, and cancels the reader.
The baseline fails its one-second cancellation observation while the holder still owns the
lock. It exits only after the test releases the holder. `before.log.gz` retains the failing
two-test run; the initial helper extraction preserves the baseline locking behavior.

Acquisition now tries the lock immediately and, if contended, checks task cancellation between
50 ms timed waits. A cancellation check after acquisition and `defer`-based release cover the
acquisition race and thrown extraction errors. Lock/unlock and all PDFKit extraction remain
synchronous on the same thread. Apple's [NSLock reference](https://developer.apple.com/documentation/foundation/nslock)
documents the timed acquisition API and same-thread ownership requirement.

This interval is a cancellation-check policy, not a hard wall-clock guarantee: OS scheduling
and a PDFKit operation already executing can still delay completion. A queued task still
blocks its worker thread during each timed wait. No PDFKit work is forcibly interrupted.

`ExtractionCancellationTests.swift` adds four tests:

- A native waiter must observe cancellation within a generous one-second test deadline while
  the gate remains held. Another waiter must remain blocked until the owner releases the gate,
  then complete. Subsequent native extraction checks source text and bold styling.
- A public conversion must throw cancellation and remove its staging directory before the
  holder releases the gate. It must not publish an EPUB or report extraction/completion.
- A throwing operation must release the gate for its next caller.
- A task already cancelled before acquisition must not execute the protected operation.

The holder has a ten-second fail-safe so the contention tests cannot leave the gate locked
indefinitely. Tests use original bundled prose/list fixtures, independent PDFDocument instances,
and a synthetic held gate; they do not depend on a slow or hung Apple call to reproduce the wait.
The native baseline regression and public cleanup test are bounded deterministic-ownership
checks with scheduler allowance, not physical-device latency measurements.

## Results

Fresh checks on 2026-09-15 use macOS 27.0 (26A428), Xcode 27.0 (27A266a), arm64:

- All 142 Swift tests pass on macOS and iOS 27 Simulator (iPhone 18 Pro).
- All 69 Python tests, six fixture conversions, four policy conversions and ten
  rejection/cleanup cases pass.
- The normal eight-process native-extraction concurrency smoke gate passes all processes,
  covering 1,800 extraction iterations across tagged and untagged fixtures.
- The structure-index peak RSS is 119,832,576 bytes, below the unchanged 192 MiB ceiling.
- All eight complete corpus conversions pass EPUBCheck, progress, resource budgets and
  221 content checks on 54 reviewed pages. All 2,151 source pages' non-OPF EPUB entries
  match the retained baseline, including XHTML, navigation, CSS and 3,922 image files.

Full Warren and NOAA conversions remain explicit exclusions for their existing output-ceiling
failures. Existing corpus correctness limitations remain; output equality protects against
regressions from this synchronization change but does not qualify every source page.

## Reproduce and retained evidence

```sh
swift test --filter ExtractionCancellationTests
scripts/check-all.sh --corpus
xcodebuild test -scheme PDFReflowLib-Package \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO
```

`results.json` pins implementation/test/collector hashes and the complete corpus assessment.
`receipts.tar.gz` retains fresh-process identities, validation, memory, progress and content
receipts. Compressed logs preserve the baseline failure, targeted pass and platform gates.
The collector compares every non-OPF EPUB entry against the hashes retained by the previous
complete corpus gate, including all XHTML and image bytes. `EPUB/package.opf` is excluded from
that byte comparison because it contains dynamic publication metadata; ordinary EPUBCheck,
navigation and metadata validation still run. No expected content contracts or resource limits
are changed for this repair.
