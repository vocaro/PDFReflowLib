# Footprint under host pressure (#244): measurement incomplete

The owner requested a serial quiet corpus lane and the same conversions under induced host
pressure before deciding whether the memory gate should use the kernel's lifetime maximum
physical footprint. The current reviewed corpus has 21 cases, rather than the 18 named when
the issue was opened. No metric or budget was changed.

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
