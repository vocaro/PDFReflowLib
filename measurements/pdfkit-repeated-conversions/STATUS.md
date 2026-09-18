# Status (work in progress, unmerged)

Stopped early at the owner's request on 2026-09-18. See `record.md` for the measurements.

Done: the per-page union request in `NativeTextReader` (tested by
`AttributedExtractionTests.swift`), the repeated-conversion harness (`harness.swift`,
`measure.sh`), the leak gate `tools/check_repeated_conversions.py` (unit tests in
`tools/test_repeated_conversions.py`; wired into `scripts/check-all.sh --corpus`), `text-line` and
`union` modes in `tools/probe-pdfkit-memory.swift`, and docs. Verified: `swift test`, Python tests,
doc counts, all 21 corpus lanes PASS, byte identity on 21 cached sources (all but NOAA and Warren).

Remaining:
- Byte identity on NOAA and Warren (lanes already pass).
- Peak RSS: the harness saw FAA peaks of 0.8–1.06 GB for the candidate against 0.68–0.95 GB for
  the baseline, but under load average 25. Compare fresh-process peaks on a quiet machine, e.g.
  `tools/evaluate-real-document.py` for FAA with both binaries, before merging.
- The `probe-pdfkit-memory.swift` `text-line`/`union` comparison was interrupted after FAA
  `text-line` (162,418 leaks, 11.2 MB); rerun for `union` and the Fed, the magazine and Our Flag.
- Physical iPhone repeated conversions (the host app in `measurements/page-retention/device/host`)
  were not run; they need the owner's permission to deploy.
- The baseline's one differing FAA round in one process (record.md) is unexplained.

Resume: merge this branch, `swift build -c release`, then
`LEAKS=1 measurements/pdfkit-repeated-conversions/measure.sh 3 corpus/cache/faa-h-8083-25c.pdf`
and `python3 tools/check_repeated_conversions.py`; `SIMULATOR=<udid>` runs the harness in a
booted Simulator.
