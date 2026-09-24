# Footprint under host pressure (#244): quiet baseline complete, pressure pair unavailable

The owner requested a serial quiet corpus lane and the same conversions under induced host
pressure before deciding whether the memory gate should use the kernel's lifetime maximum
physical footprint. The reviewed corpus now has 22 cases. No metric or budget was changed.

On 2026-09-23 the quiet lane used the existing release converter with
`tools/run_corpus_regressions.py --jobs 1 --memory-attempts 1 --settle-seconds 0`. It reached
seven completed cases before disk space fell to 1.6 GiB and the run was stopped. Six cases
recorded normal pressure throughout; the Fed case had 123 warning samples among 641, so it
cannot serve as a quiet baseline. The incomplete receipts and memory traces are retained at
`/private/tmp/pdfreflow-footprint-244-quiet-20260923`. Generated EPUBs from this run were
removed, reducing its disk use from 241 MiB to 7.7 MiB. No induced lane was started. This
evidence cannot decide whether the footprint is stable under pressure, and #244 remains open.

`pressure.py` is a bounded helper for a later induced lane. It starts only from normal host
pressure, touches memory in increments, stops on critical pressure, and caps allocation at the
smaller of 12 GiB or one third of physical RAM by default. `compare.py` pairs two complete
corpus lane outputs by case and flags a quiet run with warning samples or an induced run that
never reached warning pressure. A warning must actually be observed during each pressured
conversion before its pair can support an inference about pressure resistance.

## 2026-09-24 serial quiet lane

The host had 36 GiB of physical RAM. After removing 124 stale generated evaluator directories,
disk free space rose from roughly 9 GiB to 118 GiB. The frozen release converter SHA-256 was
`23dcc3afc4274af476f1a156967f2d11e449778f16ef6408777339239c09a1c3`. With
`--jobs 1 --memory-attempts 1 --settle-seconds 0`, all 22 cases completed at
`/private/tmp/pdfreflow-footprint-244-quiet-20260924`. EPUBCheck and structural checks passed
for every conversion. Twenty-one receipts recorded only normal host pressure and a passed RSS
memory gate. The Wallace receipt recorded warning pressure while Calibre was being used; its
memory gate was therefore not measured. A separate quiet Wallace retry at
`/private/tmp/pdfreflow-footprint-244-wallace-quiet-retry-20260924` recorded normal pressure,
89,817,088 B peak RSS, 61,653,856 B lifetime maximum physical footprint, and a passed gate.

The content-contract failures in the frozen lane were stale visible-image expectations, separate
from memory measurement. The GPO p581–583 expectations were removed after source review;
`gpo-911-2004` then passed 101 content checks. Wallace p12/p347 expectations are under
source-backed revision because their equations are now MathML with fallback images.

## Pressure induction attempt

The helper's default cap, 12 GiB, and a 4 GiB trial did not raise host pressure from normal.
The bounded maximum was then raised to 14.25 GiB (under 40% of physical RAM). With 512 MiB
steps, it held 14.0 GiB at the cap and still observed normal pressure. The optional
`--hold-at-cap` mode retained that allocation during a single FAA conversion at
`/private/tmp/pdfreflow-footprint-244-faa-held-20260924`. That conversion and EPUBCheck passed,
but its recorded peak host pressure remained level 1 (normal), so it is **not** an induced-pressure
pair. Its peak RSS was 833,912,832 B and lifetime footprint 552,174,912 B; the corresponding
quiet FAA values were 834,748,416 B and 691,275,240 B. The difference cannot be attributed to
warning pressure because no warning occurred. The helper was stopped and memory released.

This host did not reach sustained warning pressure within the safe bounded allocation. The
required 22-case pressured lane was not run, `compare.py` has no valid pressure pairs to compare,
and the issue remains open. Keep the current RSS metric and budgets until a host that can produce
warning pressure supplies paired receipts.
