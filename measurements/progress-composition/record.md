# OS 27 progress composition evaluation

Evaluation date: 2026-09-15. Runtime baseline: `ea7ddfd`. Environment: macOS 27.0
(26A428), Xcode 27.0 (27A266a), arm64. The [decision and API findings](../../doc/progress-composition.md)
complete the roadmap evaluation task while retaining ordered client reporting.

## Scope

This is an SDK/design evaluation with regression coverage, not a runtime migration or a
performance optimization. Four Foundation probes test weighted children, child release,
reporter retention and changing totals. Two public conversion tests (three cases) exercise
awaited callbacks, publication, cancellation and final-file budget failure on the bundled
three-page prose fixture. They require no external PDF or new dependency.

The first exploratory run incorrectly expected retaining a reporter to allow its manager
to deinitialize. It failed: the fraction stayed 0.2 and the manager remained alive. The final
probe explicitly checks that retention, then checks that releasing the reporter advances the
parent to 1. This corrects an evaluation hypothesis, not a library defect. The independent
unretained-child probe passed from the first run.

## Negative control

Temporarily replacing the converter's final `await progress(...)` with
`Task { await progress(...) }` makes `slowCallbacksAreAwaitedThroughPublicationAndReturn`
fail because its entered and returned callback sequences differ at conversion return.
`detached-callback.log.gz` retains that expected failure. The mutation was reverted before
the final checks, and `git diff --exit-code -- Sources` confirms no production-code changes.

## Reproduce

```sh
swift test --filter 'NativeProgressEvaluationTests|OrderedProgressContractTests'
swift test -c release --filter 'NativeProgressEvaluationTests|OrderedProgressContractTests'
scripts/check-all.sh --fast
xcodebuild test -scheme PDFReflowLib-Package \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:PDFReflowLibTests/NativeProgressEvaluationTests \
  -only-testing:PDFReflowLibTests/OrderedProgressContractTests CODE_SIGNING_ALLOWED=NO
```

The focused macOS debug/release runs and iOS 27 Simulator run (iPhone 18 Pro) each pass
six tests with seven cases. `scripts/check-all.sh --fast` exits successfully: all 148 Swift tests,
69 Python tests, eight fresh native-extraction processes, six fixture conversions, four
policy conversions and ten rejection/cleanup cases pass. Logs are compressed without
removing diagnostic output. Existing fixture identities and resource ceilings remain
unchanged. Corpus conversion is not needed for an evaluation that changes no extraction,
layout, rendering or shipping code; this run makes no new corpus-fidelity claim.

Retained logs: `focused-macos.log.gz`, `focused-release.log.gz`, `ios.log.gz`, `fast.log.gz`
and the expected-failure `detached-callback.log.gz`. The evaluated test file's SHA-256 is
`1fb71e4d4a169439747eee60f6a8c5f6b6304251003b0b33948f5f78c1512e8e`.
