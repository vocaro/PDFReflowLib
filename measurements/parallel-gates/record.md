# Parallel gates

`scripts/check-all.sh --corpus` ran every gate one after another, and the corpus lane converted
its cases one at a time. This record measures the parallel restructuring described in
[regression testing](../../doc/regression-testing.md#parallel-gates), and checks its corpus output
against a serial run. It follows the approach studywright took for its pytest lane
(vocaro/studywright#26, vocaro/studywright#187): parallelize by default, keep a serial escape hatch, and establish
parity with the serial run before relying on the parallel one.

Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max (6 performance and 12 efficiency
cores), 36 GB, other agent sessions sharing it (load average 5.5–7.9 at the start of each run).
Library source at `52becb7`, with a warm `.build`. Measured 2026-09-19.

## Where the serial time went

The serial run's per-gate seconds, as the new script reports them with `PDFREFLOW_CHECKS_SERIAL=1`.
A run of the unmodified script at `52becb7`, timed from shell trace timestamps, took 274 s with
the same distribution.

| Gate | Serial | Parallel |
| --- | ---: | ---: |
| python-tool-tests | 11 s | 11 s |
| swift-tests | 5 s | 5 s |
| release-build | 12 s | 12 s |
| pdfkit-concurrency | 6 s | 6 s |
| fixture-epubs | 9 s | 14 s |
| conversion-policies | 21 s | 32 s |
| structure-memory | 3 s | 4 s |
| repeated-conversions | 28 s | 38 s |
| corpus | 180 s | 53 s |
| **Wall-clock** | **276 s** | **76 s** |

The corpus lane was two thirds of the serial time. Its converter is single-threaded: across
all 18 cases, converter CPU seconds were 0.6–1.1 times wall seconds. Separate processes
therefore scale with cores. In the parallel run the Python tool tests overlap the Swift suite and
build (about 17 s for the first step), the concurrency stress runs alone, and the five remaining
gates run at once; the corpus lane, at six jobs, sets the floor. Its longest case, FAA at about
44 s under contention, is the lower bound for further scaling at this layer.

## Corpus parity

Two corpus runs on the same converter (`c5c35c9b…`), both with the environment probe
(`tools/run_corpus_regressions.py --environment-probe .build/raster-environment/probe`):
`--jobs 1` took 244 s and `--jobs 6` took 48 s (the probe adds time to each case).
`tools/compare_conversion_runs.py` passed for all 18 cases: no changed pages, images, page
markers or conversion report fields. Every content assessment was identical and passing. Host
memory pressure stayed at level 1 (normal) in every sample of both runs.
[parity.json](parity.json) has the per-case figures.

| Case | Serial s | Parallel s | Serial RSS MiB | Parallel RSS MiB | Ceiling MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| faa-phak-8083-25c | 39.2 | 44.2 | 850 | 935 | 1,280 |
| cia-blue-book-14-1955 | 32.7 | 37.3 | 252 | 285 | 512 |
| cdc-zombie-pandemic-2011 | 12.2 | 13.2 | 426 | 435 | 512 |
| gpo-911-2004 | 12.4 | 12.6 | 106 | 109 | 256 |
| wallace-algebra-2010 | 10.7 | 12.3 | 80 | 83 | 256 |
| uscis-m618-arabic-2015 | 8.3 | 9.5 | 166 | 172 | 256 |
| fed-explained-2021 | 7.2 | 8.1 | 300 | 305 | 768 |
| census-rrs2002-01 | 6.5 | 6.1 | 250 | 262 | 512 |
| usda-ars-agresearch-2012-11 | 5.6 | 6.2 | 280 | 289 | 512 |
| gpo-warren-1964-suspect-text-excerpt | 4.8 | 5.6 | 724 | 742 | 1,024 |
| irs-p596-zhs-2025 | 4.1 | 5.0 | 169 | 174 | 256 |
| gpo-our-flag-2003 | 1.4 | 1.5 | 99 | 102 | 192 |
| arxiv-replay-clocks-2023 | 1.0 | 1.2 | 166 | 170 | 256 |
| scotus-loper-bright-2024 | 1.0 | 1.3 | 40 | 41 | 128 |
| dga-2025-2030 | 0.8 | 0.9 | 107 | 108 | 192 |
| ntrs-20180003024-earthdata-slides-2018 | 0.8 | 0.9 | 91 | 92 | 128 |
| nbs-jres-geltman-1977 | 0.7 | 0.7 | 258 | 261 | 512 |
| usgs-mcs2025-copper | 0.2 | 0.2 | 31 | 32 | 128 |

Peak RSS read 1–13% higher in parallel for every case, never lower, so the memory gate is
conservative under concurrency: a case close to its ceiling can fail in parallel and pass
serially, but not the reverse. The closest here is the CDC comic at 85% of its ceiling in
parallel. The pressure guard covers the other direction: memory compression under host-wide
pressure would lower RSS, and the evaluator fails the memory gate when pressure rises above
normal.

## Scope

One parallel and one serial complete gate run, and one pair of probed corpus runs, on one
loaded host. Conversion seconds in parallel receipts include contention
(`concurrentEvaluations`) and are not comparable to serial ones. The PDFKit concurrency stress
still runs alone, so its evidence is unchanged. Parity covers what
`tools/compare_conversion_runs.py` compares, plus the content contracts; it is not a fidelity
qualification.
