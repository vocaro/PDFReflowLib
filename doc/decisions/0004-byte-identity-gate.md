# 0004 Byte-identical output is the gate for a refactor

## Context

The corpus lane checks reviewed content contracts, EPUB conformance, progress and resource
budgets; `tools/compare_conversion_runs.py` compares parsed page records, markers, image assets
and report fields between two evaluations. Neither detects a change in serialization that keeps
the checked content intact, and a refactor that claims "behavior unchanged" needs a check that
is stricter than either.

## Decision

A change that claims to preserve behavior must produce byte-identical output against the
previous converter on every corpus, policy-variant and bundled-fixture conversion that completes
under default budgets, and the books that stop at a budget must stop at the same page.
`tools/epub_identity.py` performs the check: every archive entry must match exactly, in the same
order, except the package identifier and modification timestamp that vary per run (normalized
to placeholders, each required to occur exactly once in the package document), and the
conversion reports must match except for the output path. Both conversions pin
`packageIdentifier` and `modificationDate`, and explicit image policies keep both binaries on the
same options regardless of library defaults. The tool has negative controls and its tests run in
the Python gate.

The claim is written into the commit message with the count of conversions checked, alongside
`scripts/check-all.sh --fast`.

## Consequences

- The two-pass page retention (all three strategies against the pre-change converter on every
  complete book), the one-request-per-page PDFKit change (all 23 cached sources, including
  Warren's 17 Vision-recognized pages and NOAA), and every decomposition commit on the
  pipeline-refactoring branch (64 corpus, policy-variant and fixture conversions each) were gated
  this way.
- Identity is a stronger claim than the corpus comparison and a narrower one: it holds on one
  host and OS build. Rendering, OCR and image encoding can differ across OS builds and device
  capabilities (#26), which is why cross-environment comparisons use capability receipts and the
  parsed-content comparator instead ([corpus.md](../corpus.md#comparing-conversion-runs)).
- A refactor that changes bytes on purpose (a fix) is not a refactor under this rule; it goes
  through the corpus lane with reviewed expectation changes, and its record says what moved.
- Warren and NOAA, which fail the default image-output budget, contribute "stops at the same
  page" rather than a full archive.

## Evidence

[page-retention](../../measurements/page-retention/record.md) (the first use of the identity
check); commit `5e6e5cc` ("Confirm byte identity on NOAA and Warren", #4) and the
pipeline-decomposition commits `fcef17b`, `d78ee1b`, `1e485f7`, `1fb3370`, `780deae`, whose
messages carry the 64-conversion claim.
