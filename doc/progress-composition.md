# Native progress composition evaluation

The evaluation of OS 27's `ProgressManager`/`ProgressReporter` composition, its executable
findings and the decision to retain `PDFConverter.convert`'s ordered, awaited
`ConversionProgress` callback are recorded as
[decision 0003](decisions/0003-awaited-progress-callbacks.md). The probes are
[NativeProgressEvaluationTests.swift](../Tests/PDFReflowLibTests/NativeProgressEvaluationTests.swift);
the commands, platform results, rejected lifetime hypothesis and retained logs are in
[the validation record](../measurements/progress-composition/record.md). The stage shares the
converter reports are specified in [behaviour](behaviour.md#pdfconverter-entry-limits-progress-cancellation).
