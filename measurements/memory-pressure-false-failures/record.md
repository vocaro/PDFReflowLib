# Memory-pressure false failures

The corpus memory gate failed a case whenever host memory pressure rose above normal while the
converter ran, on the reasoning that macOS compresses and pages out resident memory under
pressure, so a peak RSS taken then can slip under a ceiling the same conversion would exceed on
a quiet host. The guard's reasoning holds. Its verdict did not: it reported "FAIL" for a
condition of the machine, indistinguishable in the summary from the library allocating too much.

This record measures how often that happened here and what it cost, and backs
[decision 0009](../../doc/decisions/0009-an-unmeasured-ceiling-is-not-a-failure.md).

Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max (6 performance and 12 efficiency
cores), 36 GB. Library source at `9975bbc`. Measured 2026-09-20 over every corpus evaluation
still retained under `$TMPDIR/pdfreflow-checks.*` from 2026-09-19 and 2026-09-20; the numbers
are in [spoiled-measurements.json](spoiled-measurements.json).

## Every failure this gate has produced here was about the host

| | Evaluations |
| --- | ---: |
| Corpus evaluations across 23 runs | 414 |
| Ceilings actually exceeded | 0 |
| Measurements spoiled by host memory pressure | 25 |

Six percent of evaluations failed, and every one of them failed for the machine rather than for
the library: conversion exit 0, structural check passed, EPUBCheck 0, content contract passed,
peak RSS inside the ceiling. The gate's false-discovery rate on this host is 100%.

The spoiled peaks were not close calls. They ran at 26–81% of their ceilings, a median of 43%;
the FAA handbook's three spoiled runs reached 634–762 MiB of its 1,280 MiB. Nothing this host's
pressure could plausibly have hidden was close to a ceiling.

## The spike does not have to last

`peakMemoryPressureLevel` is the maximum over 100 ms samples spanning the whole conversion, so
any excursion at all condemns the run. In the mildest spoiled measurement, pressure was above
normal for 28 of 814 samples — 2.8 seconds of an 85-second conversion — and threw away a peak
518 MiB under its ceiling. Eight of the 25 were excursions shorter than a quarter of the run.
Twelve were above normal in every sample: the host was loaded for the whole conversion.

## The load was a neighbor, and it left

The worst run, 2026-09-20 12:11, failed 13 of 18 cases. The corpus lane was serial, so its own
concurrency was not the source. Ordering the cases by start time places every failure in one
contiguous 365-second window opening with the run, and every case that started after it passed:

| Case | Start | End | Peak pressure |
| --- | ---: | ---: | ---: |
| faa-phak-8083-25c | 0 s | 103 s | 2 |
| … eleven more … | | | 2 |
| irs-p596-zhs-2025 | 353 s | 365 s | 2 |
| nbs-jres-geltman-1977 | 368 s | 370 s | 1 |
| arxiv-replay-clocks-2023 | 373 s | 376 s | 1 |
| ntrs-20180003024-earthdata-slides-2018 | 379 s | 382 s | 1 |
| gpo-warren-1964-suspect-text-excerpt | 384 s | 393 s | 1 |
| usda-ars-agresearch-2012-11 | 396 s | 407 s | 1 |

The window is an unrelated `studywright` build on the same Mac, at load average 43 with 9 GB of
the 10 GB swap file in use. It ended, and the host went quiet for the rest of the run without
anything in this repository changing. Waiting for that and measuring again is what the 13 cases
needed; failing them is not.

## What a repeat costs

The five cases that ran after the window took 2–11 seconds each. A second attempt is cheap for
most of the corpus and expensive only for the FAA handbook (103 s) and CIA Blue Book (75 s),
and it is only worth spending once the host is quiet, which is why the evaluator waits for
normal pressure before it spends one and reports the ceiling unmeasured when the host never
settles.

## What was not measured

Whether `ri_lifetime_max_phys_footprint` — now recorded per evaluation as
`converterLifetimeMaxPhysicalFootprintBytes` — is a sound ceiling metric. It is the kernel's own
high-water mark, so unlike the sampled footprint it cannot miss a spike between two samples, and
the footprint ledger counts compressed pages that resident size does not. A probe here confirmed
the high-water behavior: a child that touched 400 MiB and released it read 15 MiB resident and
7 MiB footprint at exit, with a lifetime maximum of 407 MiB. It counts compressed pages at their
compressed size, not their original size, so it is not an upper bound on an unpressured peak, and
every checked-in ceiling was established against peak RSS. It is recorded as corroborating
evidence and gated on nothing until a re-baselining measures it.
