# 0007 Records cite commits and paths in prose; nothing pins them by machine

## Context

A measurement record describes one build: the commit it measured ("on top of `15f1985`",
"baseline `58da4de`"), the host, the Xcode and OS builds, the commands run and the paths those
commands used. Source files move, tools move from `measurements/` to `tools/`, retired code is
deleted, and the commit hashes a record names are not reachable by any checker once a branch is
closed out. Two ways to keep records honest were available: bind each record to its commit and
paths with a machine-readable manifest and a gate that fails when a cited path disappears, or
treat the record as frozen prose and leave the binding to the reader.

The same question arises for the receipts a measurement produces. The cross-environment
comparator (`tools/compare_conversion_runs.py`) verifies a retained EPUB, probe JSON and report
against the evaluation receipt that produced them, and refuses missing, failed, stale or
incompatible capability receipts before reporting drift. Those receipts are local consistency
checks, not signed attestation, and they bind one evaluation to its own outputs, not a record to
the repository.

## Decision

Records cite the commit, paths and identities they measured in prose, as measured, and are not
edited afterwards except to add a one-line pointer at the top when a file they name has moved or
been removed (for example: "`identity.py` now lives at `tools/epub_identity.py`; the retired
strategy tests and `measured-strategies.patch` were removed from the tree and remain at commit
`a28fb09`; the paths below are as measured."). There is no manifest binding records to commits,
no gate that fails when a cited path moves, and no rewriting of historical paths or hashes.
Recorded measurement outputs keep the historical paths and hashes of their measured builds.

Evaluation receipts remain what they are: per-run identity records (converter and probe
SHA-256, source identity, system and build, EPUB SHA-256) that the comparator checks against
the run's own outputs. Historical receipts without capability evidence must be recaptured, not
annotated, to become eligible for strict comparison.

## Consequences

- A record is read as history. Its commands may no longer run verbatim; the pointer line says
  where to look, and the commit it names holds the tree it measured.
- Moving or deleting a file a record cites costs one pointer line, not a rewrite, and the
  measurements-policy gate ([0006](0006-measurements-are-records.md)) keeps that edit small.
- Nothing fails automatically when a record's citations rot; the regression steps say to
  preserve historical measurement receipts, and a reviewer changing a measured path adds the
  pointer.
- Documentation that needs the current truth (this directory, [behavior](../behavior.md),
  the runbooks) states it itself and links to the record for how it was established, rather than
  relying on the record staying current.

## Evidence

The pointer lines atop `measurements/page-retention/record.md`,
`measurements/pdfkit-repeated-conversions/record.md` and `measurements/vision-titles/record.md`
(added by commit `61c1dd3`); the receipt rules in [corpus.md](../corpus.md#comparing-conversion-runs)
and the [raster-environment](../../measurements/raster-environment/record.md) record.
