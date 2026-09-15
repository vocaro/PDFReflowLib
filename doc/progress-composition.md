# Native progress composition evaluation

## Decision

Retain `PDFConverter.convert`'s awaited `ConversionProgress` callback. Do not replace it
with a native progress tree or add a new public progress parameter at this time. The
evaluation is complete; the minimum deployment version remains iOS/macOS 27.

OS 27's native composition can express the current estimates, but it does not remove the
converter's need to deliver ordered stage/page snapshots, await client work, and distinguish
successful publication from cancellation or failure. For the current sequential pipeline,
adoption would add lifetime management and a second progress representation without replacing
those responsibilities. This is a design choice, not a finding that native composition is broken.

## Available APIs

The Xcode 27.0 (27A266a) Foundation interface declares `ProgressManager`, `ProgressReporter`
and the noncopyable `Subprogress` at macOS/iOS 27. `ProgressManager` updates counts and
allocates weighted child work; its read-only `ProgressReporter` exposes observable state
and can be assigned to another manager. There is also interoperability with Foundation
`Progress`. See Apple's [ProgressManager reference](https://developer.apple.com/documentation/foundation/progressmanager)
and [ProgressReporter reference](https://developer.apple.com/documentation/foundation/progressreporter).

The local SDK declarations and executable probes are the evidence for availability and
behavior on the installed build. Earlier proposal spellings are not the API being evaluated.
The public count mutation methods are synchronous; they provide no awaited client-callback
parameter. Conforming to `Observable` does not itself implement the library's event-delivery
contract.

## Executable findings

The tests in [NativeProgressEvaluationTests.swift](../Tests/PDFReflowLibTests/NativeProgressEvaluationTests.swift)
exercise actual Foundation objects:

| Probe | Observed result | Consequence for this converter |
| --- | --- | --- |
| Weighted stage children | 2 opening units, 55 extraction, 25 reconstruction, 17 writing and 1 publication reproduce the existing fractions | Composition is feasible with fixed weights |
| Release an unfinished child | A child at 2/10 of a 100-unit allocation disappears; its parent advances from 0.2 to 1 | Scope exit is not evidence that an EPUB was published |
| Retain the child's reporter | The child remains at 0.2 after the manager variable is cleared; releasing the reporter then advances the parent to 1 | Reporter ownership affects completion; account for it explicitly |
| Increase the total | Changing 5/10 to 5/20 lowers the fraction from 0.5 to 0.25 | Monotonic estimates still require a policy |

The opening allocation is implicit in the existing mapping: the opening event is zero,
and subsequent pipeline events include the 0.02 offset. OCR shares extraction's allocation;
it does not add a second block of work. The probes retain successful children until their
fractions have been checked, so deinitialization cannot disguise incomplete work.

The Swift Foundation project's [manager implementation](https://github.com/swiftlang/swift-foundation/blob/main/Sources/FoundationEssentials/ProgressManager/ProgressManager.swift)
also describes parent completion on child deinitialization. That moving source is explanatory;
the retained tests establish the installed SDK behavior. No claim is made about every future
Foundation release, observation scheduling, physical-device latency, or relative performance.

## Preserved client contract

Each conversion continues to deliver immutable stage, fraction, source-page and total-page
values through one awaited callback. The caller can suspend, including a hop to `MainActor`;
the conversion awaits that callback before continuing its own work. Other conversions can
make independent progress. A callback is an event, while an observed reporter is current state.

The new public-API regressions deliberately suspend each callback. They require every callback
to return before conversion returns, no overlapping callbacks for that conversion, ordered
extraction/reconstruction page numbers, monotonic fractions, and exactly one completion event
after the destination exists. Cancellation during writing and a final-file budget failure
must remove staging without completion. An intentional mutation that detached the completion
callback fails the new regression; the production code is restored.

Clients needing a composed UI estimate can update their own manager from the existing callback
and expose its reporter. Such an adapter would need explicit ownership and terminal-result
handling, and must use the conversion's returned report or thrown error to determine success.
Task cancellation remains the cancellation mechanism. A future requirement for public
composition can justify a separate API design; it is not required to complete this evaluation.

See [the validation record](../measurements/progress-composition/record.md) for commands,
platform results, the rejected lifetime hypothesis and retained logs. No runtime code, output
format, conversion option, deployment target, resource budget or corpus expectation changes.
