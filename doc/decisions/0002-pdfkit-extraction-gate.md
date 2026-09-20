# 0002 One process-wide gate for PDFKit extraction, drained before it unlocks

## Context

PDFKit's attributed-text extraction can abort the process with an `NSInvalidArgumentException`
(a nil `NSFont`) when separate documents are read concurrently. The failure is reproducible with
public Apple APIs on the development Mac and through the unmodified `NativeTextReader`
([#21](https://github.com/vocaro/PDFReflowLib/issues/21); Apple FB24796210). Independent
converter instances in one process, which an app converting several PDFs at once creates, hit
it.

Serializing the synchronous page-extraction step behind a library-local `NSLock` removed most
aborts, but an eight-worker stress campaign still aborted occasionally. The cause was not
overlapping extraction: `PDFSelection.attributedString` and the fonts its runs carry are
autoreleased, and one thread freeing a just-finished extraction's objects raced another thread's
PDFKit call already inside the gate. A queued conversion also could not be canceled while
`NSLock.lock()` waited indefinitely for the active extraction.

## Decision

`NativeTextReader.withExtractionLock` serializes synchronous native extraction across every
converter instance in the process. Acquisition tries the lock at once and, when contended,
checks task cancellation between 50 ms timed waits (`lock(before:)`), then checks again after
acquiring. The protected operation runs inside its own `autoreleasepool`, drained before
`unlock()`, so autoreleased fonts and attributed strings are freed before the next waiter enters
PDFKit. The lock is never held across progress callbacks, OCR, graphics work or writing.

The same rule applies to test code: fonts, CoreText drawings and PDFKit reads are made through
`pdfKitGated` (`Tests/PDFReflowLibTests/PDFKitGate.swift`), and `tools/check_pdfkit_gate.py`
fails the build on any such call in `Sources/` or `Tests/` outside `withExtractionLock` or
`pdfKitGated`. About forty test call sites were gated when the drain landed.

## Consequences

- Eight-worker native campaigns pass: 2 of 80 processes aborted with the drain removed, 0 of 70
  with it present. Every `check-all.sh` lane runs a fresh-process smoke gate (two trials, one and
  eight workers, 50 document opens per worker); longer campaigns and the unmitigated SDK control
  are explicit diagnostic runs (see [regression testing](../regression-testing.md#concurrency-campaigns)).
- Concurrent imports trade extraction throughput for serialization. A canceled waiter can
  return while another extraction still holds the lock; a PDFKit call already executing cannot be
  interrupted; each timed wait blocks its worker thread. The interval is a cancellation-check
  policy, not a latency guarantee.
- The mitigation is bounded to this library's own calls. A host application making a font,
  laying out text with CoreText, or reading PDFKit text on its own thread during a conversion can
  still abort a gated extraction. #21 stays open for that and for the Apple bug; the gate does not
  address PDFKit's attributed-text memory leak (#4, FB24783799).
- A finite passing campaign is bounded evidence, not proof that all concurrent PDFKit use is
  safe.

## Evidence

[pdfkit-concurrency](../../measurements/pdfkit-concurrency/record.md) (reproduction and the
lock), [extraction-cancellation](../../measurements/extraction-cancellation/record.md) (timed
waits; baseline `58da4de`), [pdfkit-gate-drain](../../measurements/pdfkit-gate-drain/record.md)
(the drain and the test gate), [apple-feedback-pdfkit](../../measurements/apple-feedback-pdfkit/record.md).
