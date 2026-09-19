# 0003 Ordered, awaited progress callbacks rather than native progress trees

## Context

OS 27 added native progress composition to Foundation. The Xcode 27.0 (27A266a) interface
declares `ProgressManager`, `ProgressReporter` and the noncopyable `Subprogress` at
macOS/iOS 27: a manager updates counts and allocates weighted child work, its read-only reporter
exposes observable state and can be assigned to another manager, and there is interoperability
with Foundation `Progress` (Apple's [ProgressManager](https://developer.apple.com/documentation/foundation/progressmanager)
and [ProgressReporter](https://developer.apple.com/documentation/foundation/progressreporter)
references). The roadmap asked whether `PDFConverter.convert`'s awaited `ConversionProgress`
callback should be replaced by, or supplemented with, such a tree.

The local SDK declarations and executable probes were the evidence for availability and
behaviour on the installed build; earlier proposal spellings were not what was evaluated. The
public count-mutation methods are synchronous and provide no awaited client-callback parameter,
and conforming to `Observable` does not itself implement the library's event-delivery contract.

`NativeProgressEvaluationTests.swift` exercises actual Foundation objects:

| Probe | Observed result | Consequence for this converter |
| --- | --- | --- |
| Weighted stage children | 2 opening units, 55 extraction, 25 reconstruction, 17 writing and 1 publication reproduce the existing fractions | Composition is feasible with fixed weights |
| Release an unfinished child | A child at 2/10 of a 100-unit allocation disappears; its parent advances from 0.2 to 1 | Scope exit is not evidence that an EPUB was published |
| Retain the child's reporter | The child remains at 0.2 after the manager variable is cleared; releasing the reporter then advances the parent to 1 | Reporter ownership affects completion; account for it explicitly |
| Increase the total | Changing 5/10 to 5/20 lowers the fraction from 0.5 to 0.25 | Monotonic estimates still require a policy |

The opening allocation is implicit in the existing mapping: the opening event is zero and later
pipeline events include the 0.02 offset; OCR shares extraction's allocation rather than adding a
second block of work. The probes retain successful children until their fractions are checked,
so deinitialization cannot disguise incomplete work. The Swift Foundation project's
[manager implementation](https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/ProgressManager/ProgressManager.swift)
also describes parent completion on child deinitialization; that moving source is explanatory,
and the retained tests establish the installed SDK's behaviour. The first exploratory run
incorrectly expected retaining a reporter to let its manager deinitialize; the final probe checks
that retention explicitly. No claim is made about future Foundation releases, observation
scheduling, physical-device latency or relative performance.

## Decision

Retain `PDFConverter.convert`'s awaited `ConversionProgress` callback. Do not replace it with a
native progress tree or add a new public progress parameter. The evaluation is complete; the
minimum deployment version remains iOS/macOS 27.

Native composition can express the current estimates, but it does not remove the converter's
need to deliver ordered stage/page snapshots, await client work, and distinguish successful
publication from cancellation or failure. For the sequential pipeline, adoption would add
lifetime management and a second progress representation without replacing those
responsibilities. This is a design choice, not a finding that native composition is broken.

## Consequences

- Each conversion delivers immutable stage, fraction, source-page and total-page values through
  one awaited callback. The caller may suspend, including a hop to `MainActor`; the conversion
  awaits the callback before continuing. Other conversions progress independently. A callback is
  an event; an observed reporter would be current state.
- The public-API regressions deliberately suspend each callback and require every callback to
  return before the conversion returns, no overlapping callbacks for one conversion, ordered
  extraction/reconstruction page numbers, monotonic fractions, and exactly one completion event
  after the destination exists. Cancellation during writing and a final-file budget failure must
  remove staging without completion. A mutation that detached the completion callback
  (`Task { await progress(...) }`) fails the regression; the production code is restored.
- A client needing a composed UI estimate updates its own manager from the callback and exposes
  its reporter. Such an adapter needs explicit ownership and terminal-result handling, and must
  use the returned report or thrown error to determine success. Task cancellation remains the
  cancellation mechanism. A future requirement for public composition can justify a separate API
  design.
- The stage shares now live in `ProgressBudget` (see [behaviour](../behaviour.md#pdfconverter-entry-limits-progress-cancellation)).
  No runtime code, output format, conversion option, deployment target, resource budget or
  corpus expectation changed with this evaluation.

## Evidence

[measurements/progress-composition/record.md](../../measurements/progress-composition/record.md):
commands, platform results, the rejected lifetime hypothesis and the retained logs. Evaluated
2026-09-15 at runtime baseline `ea7ddfd` on macOS 27.0 (26A428), Xcode 27.0, arm64.
