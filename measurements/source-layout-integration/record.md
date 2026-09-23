# Five source-layout fixes qualified together

Measured 2026-09-23 on macOS 27, arm64. Runtime commit `89ea015`; subsequent
`9070942` changes only documentation and the controlled-experiment record.
The frozen release executable retained the normal `pdf-reflow` basename; its
SHA-256 is recorded in `results.json` and in every case result.

This integration qualifies the fixes for #172 (detached dietary-guidelines cover
labels), #296 (sparse native chapter titles), #192 (drawn slide text), #295
(invisible-text word spacing), and #160 (a paragraph continuing past a column's
figure). The individual records document source identity, before/after comparisons,
negative controls, and the scope of each fix. The tree includes their implementation,
source fixtures, assertions and review guards; it does not rely on the abandoned
coordination branch's ancestry.

All 11 fast gates pass: 741 Swift tests, 250 Python tool tests, release and documented
probe builds, PDFKit concurrency, fixture EPUBs, conversion policies, and repository
policy/documentation checks. The frozen binary passes all 20 registered corpus
cases: 798 content assertions on 153 reviewed pages, with full-source conversion,
EPUBCheck, structure, progress and unchanged Mac RSS limits. These sampled assertions
are not a claim of full-book fidelity. All case metrics and scopes are in the JSON.

Warren's first attempt encountered elevated host memory pressure. The gate's existing
retry passed at normal pressure with peak RSS 1,178,632,192 bytes below the unchanged
1,610,612,736-byte limit. Neither an overloaded run nor a raised limit is counted as
qualification. The isolated structure-index gate peaks at 121,143,296 bytes for
39,198 references on 510 pages, below 192 MiB. Three full Fed conversions in one
process produce identical EPUBs and add 1,750.5 leaked objects per conversion,
below the existing 4,050-object ceiling. These are Mac gates, not iOS device budgets.

Ordinary Vision OCR is not claimed deterministic across rebuilt executables.
`../cli-name-recognition-control/` documents the measured executable-name sensitivity;
`../noaa-chapter-heading/qualification-guards.md` and its controlled experiment
separate title classification from recognition changes. The final corpus uses a
single frozen executable, not the earlier renamed or superseded candidates.

Raw logs, PDFs, EPUBs and memory samples remain outside Git under
`/tmp/pdfreflow-first-five-qualified-corpus` and the corresponding final gate logs.
