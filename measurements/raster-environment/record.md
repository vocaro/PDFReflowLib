# Issue #26: execution environment explains the observed output drift

On September 15, 2026, the two retained binaries used in the earlier CDC/DGA comparison were
run in both the Codex execution sandbox and the host environment on the same Apple M5 Max
Mac, macOS 27.0 build 26A428. The source PDFs retain the manifest identities. All eight cells
(two binaries × two environments × two documents) are retained locally under
`.build/raster-drift-investigation`; their parsed-page hashes, encoded and decoded RGB image
hashes, complete conversion reports, and progress logs are retained here.

## Result

| Comparison | CDC comic (42 pages) | DGA booklet (10 pages) |
| --- | --- | --- |
| Baseline vs candidate binary, within sandbox | No parsed-page, image-byte, or report difference | No parsed-page, image-byte, or report difference |
| Baseline vs candidate binary, on host | No parsed-page, image-byte, or report difference | No parsed-page, image-byte, or report difference |
| Same binary, sandbox vs host | Parsed pages 13, 15, 16, 17, 36 differ; 36 images differ in decoded RGB | Parsed pages agree; one image differs in decoded RGB |
| OCR pages reported, sandbox / host | 0 / 9 for both binaries | 0 / 0 for both binaries |

The retained baseline binary on the host matches the historical candidate output. The retained
candidate binary in the sandbox matches the historical baseline output. This holds for both
documents' normalized page records and every encoded image asset. The reported differences
therefore track execution environment, not the source/compiler revision. ZIP hashes differ
because generated metadata and output paths are not stable identities of content.

A separate page-13 probe of the CDC original used exactly the same retained probe binary in
both environments (`d06167f7e3b066bca61634aaf973b98a6e5b2234d8ed63d73c92ff2b99f5e6c0`).
Inside the sandbox it reports `metalDevice: unavailable` and Vision fails with
`Failed to create CVPixelBuffer`. On the host it reports `Apple M5 Max`, and Vision succeeds
with eight recognized lines. Packed pixel hashes differ. Both report DeviceRGB with no
available ICC profile. This experiment does not identify the underlying Apple rendering
mechanism and does not establish ColorSync causality or renderer nondeterminism.

## Evidence and verification

- `identity.json`: exact converter and source identities, system metadata, collector identity,
  and legacy probe identity. The current probe source hash refers to the new per-run tool,
  not to the legacy investigation probe binary.
- `runs.json.gz`: normalized page hashes, image inventories, encoded/RGB hashes and normalized
  reports, including historical output identities.
- `comparisons.json`: all eight historical matches, four within-environment binary comparisons,
  and four cross-environment comparisons.
- `*-report.json.gz` and `*-progress.log.gz`: all eight full conversion reports and logs.
- `probe-sandbox.json`, `probe-host.json`: the original paired page-13 capability observations.
- `pixel-samples.json`: decoded pixel difference summaries for CDC image 1 and DGA image 3.
  CDC's example has mean absolute channel differences of about 0.37/0.36/0.64 out of 255;
  DGA's about 0.40/0.21/0.29. These are measurements, not acceptance tolerances.

To recheck the retained eight-cell evidence (requires Pillow and the ignored local artifacts):

```sh
python3 measurements/raster-environment/collect.py
```

The collector verifies pinned sources, retained probe identity, every historical match,
within-environment full report equality, and the measured cross-environment deltas. It does
not rerun conversions or infer provenance from filenames alone. The original eight runs
predate the new per-run receipt format and remain diagnostic evidence, not inputs to the
strict comparator. The retained baseline is associated with revision `0eba8d4`; the retained
candidate includes the then-uncommitted experiment. Their exact binary hashes, rather than
an inferred candidate revision, identify this experiment. Current main is `7f0e25d`.

## Scoped tooling change

See [the capture and comparison procedure](../../doc/corpus.md#comparing-conversion-runs).
Every requested probe invocation is bound to the evaluator's new run ID, exact PDF path and
source hash, and the probe executable's independently captured hash. Both the probe JSON and
output EPUB are tied to their receipt by SHA-256. Missing, stale, failed, or incompatible
evidence prevents strict comparison; a matching caller-provided context label cannot bypass
these checks. Failed probe processes retain a failed evaluation receipt.

This change does not alter conversion or rendering policy. It does not select one environment's
output as correct, conceal OCR failures, loosen content contracts, or claim complete document
fidelity. The comparator deliberately covers normalized page records, markers, encoded images,
and reports; it does not inspect all styling/navigation semantics. The probe is a capability
sample, not a guarantee about the entire conversion or a cryptographic attestation.

## Final validation

The new probe compiled with `xcrun swiftc -parse-as-library -O` and the four library source
files listed in the corpus documentation. Fresh sequential host evaluations used that same
probe (`91fe500a1eec1f1e5c361f1191e8d2fe4131b7ad46907cac67a097a17b4f73d1`) with both the
retained baseline and current main executable. Both CDC and DGA passed the content,
EPUBCheck, progress, memory, and capability gates for both binaries. Current-main peak RSS
was 385,335,296 bytes for CDC and 105,496,576 bytes for DGA, below their existing ceilings.

`verified-cdc-comparison.json` and `verified-dga-comparison.json` both pass: no changed page
records, markers, encoded image assets, or report fields. Current main's converter hash is
`3698a8220cde5b578ccc5d9a5dc94a023d500351872d6f38cc06ae8897a7a2f5`.
Compressed evaluation receipts, probe results/logs, reports, memory samples, EPUBCheck logs,
and content assessments live under `verified-main-host/` and `verified-baseline-host/`.

The fresh sandbox DGA run deliberately declares the same `host` label. Conversion, structural,
progress, memory, and EPUBCheck checks pass, but Vision fails and the requested capability
gate correctly fails. `verified-cross-context-comparison.json` refuses comparison because the
candidate evaluation failed and measured Metal/Vision results differ, despite matching labels.
Its receipt and diagnostics are under `verified-main-sandbox/`. The page-1 DGA pixel hashes
match across environments, demonstrating why pixel equality alone is insufficient.

The final Python suite passes 102 tests (`python-tests-v1.log.gz`). Controls cover real child
memory/progress behavior, exact PDF argument forwarding without a corpus cache, supplemental
labels, stale run/source/probe identities, probe timeout/launch/nonzero/JSON failures, missing
capability fields, malformed OCR results, artifact mutation, and content/image/report drift.
The earlier retained `fast-gate.log.gz` records 161 Swift tests, 91 then-current Python tests,
the release build, 8/8 native extraction process checks, and EPUB/policy checks. It predates
the completed receipt implementation; no production Swift conversion source changed here.

No full-corpus or device fidelity claim is made. The six other reviewed corpus cases and two
known unsupported full conversions were not rerun for this scoped change.
