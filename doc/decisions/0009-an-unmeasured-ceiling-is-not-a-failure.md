# 0009 An unmeasured memory ceiling is reported as unmeasured, not as a failure

## Context

`tools/evaluate_real_document.py` gates each corpus case's converter process against the peak RSS
ceiling in `corpus/manifest.json`. Under host memory pressure macOS compresses and pages out
resident memory, so a peak taken on a loaded machine can slip under a ceiling the same conversion
would exceed on a quiet one. The evaluator therefore sampled
`kern.memorystatus_vm_pressure_level` throughout each conversion and failed the gate whenever the
peak sample rose above normal.

That reasoning is sound and the verdict was not. Across 414 retained corpus evaluations on the
development Mac, 25 failed and all 25 failed this way: conversion exit 0, structure passed,
EPUBCheck 0, content contract passed, peak RSS between 26% and 81% of its ceiling. No ceiling was
ever actually exceeded. The failures arrived as "FAIL <case>" in the summary, identical in shape
to the library allocating too much, and the load was an unrelated `studywright` build on the same
machine.

A measurement the host spoiled is not evidence that the library regressed, and it is not evidence
that it did not. Reporting it as either one is wrong.

## Decision

The memory gate has three outcomes, not two, and `result.json` names which:

- `exceeded` — the peak RSS is above the ceiling. Pressure only ever lowers a resident size, so
  an exceedance measured under pressure is an exceedance. The run fails, exit 1.
- `passed` — the peak is within the ceiling and host pressure stayed normal for every sample
  taken while the converter ran. Readings from before the process started are recorded but do not
  count: they cannot have compressed pages it had not yet allocated.
- `notMeasured` — the peak is within the ceiling and pressure rose above normal. The run does not
  pass, and exits 3 rather than 1 when every other gate passed.

Before giving up on a measurement, the evaluator tries to obtain one. It waits up to
`--settle-seconds` (default 60) for host pressure to return to normal before each conversion, and
after a spoiled one it spends another of the `--memory-attempts` (default 2) conversions — but
only if the host settles first, so a machine that stays loaded costs one conversion rather than
several. Every attempt's measurements and samples are retained.

`tools/run_corpus_regressions.py` prints `UNMEASURED <case>`, records `memoryUnmeasured` in the
summary, and exits 3 when unmeasured ceilings are the only thing between it and a pass.
`scripts/check-all.sh` labels such a gate `UNMEASURED` and exits 3 if nothing else failed.

## Consequences

- An unmeasured ceiling is still not a pass, and no lane goes green because a machine was busy.
  What changes is that the operator is told the host was loaded instead of being pointed at the
  library. The exit status distinguishes the two for anything reading it.
- A spoiled corpus case that the host recovers from now costs a second conversion — 2 seconds for
  most of the corpus, 103 seconds for the FAA handbook — and returns a real measurement instead of
  a false alarm.
- The ceilings and their metric are unchanged: peak RSS of the converter process from
  `wait4`/`rusage`, against the per-case budgets in `corpus/manifest.json`.
- `ri_lifetime_max_phys_footprint` is now recorded per evaluation as
  `converterLifetimeMaxPhysicalFootprintBytes`. It is the kernel's high-water mark of the
  footprint ledger, so it cannot miss a spike between samples and it counts compressed pages that
  a resident size does not. It counts them at their compressed size, so it is not an upper bound
  on an unpressured peak; it is recorded as corroborating evidence and gated on nothing. Adopting
  it as the ceiling metric would mean re-baselining all 18 budgets, which this decision does not.
- Measuring memory on a machine that is building something else still produces worse data than
  not measuring at all. The runbook says so; the gate now says so too, instead of blaming the
  library.

## Evidence

[memory-pressure-false-failures](../../measurements/memory-pressure-false-failures/record.md):
414 evaluations, 25 spoiled measurements, 0 ceilings exceeded, and the 365-second neighbor-build
window that took 13 of 18 cases down in one run. The instrumentation controls in
`tools/test_memory_gate.py` cover each outcome, the settle-and-retry, and the host that never
settles.
