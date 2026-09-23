# Chapters, panel text and painted tables qualified together

Measured 2026-09-23 on macOS 27 arm64. Runtime `d548bfa`, probe source-list repair
`f44a330`, documentation reconciliation `7ac1bea`, and documentation-only merge
`934ee1eb` contain the final integrated tree. The frozen `pdf-reflow` binary's SHA-256
and individual case measurements are in `results.json`.

This batch closes #15 (source-verified chapter hierarchy and large-report qualification),
#182 (native text separated from decorative page grounds without losing diagram art),
and #215 (NOAA painted-cell tables and author-credit paragraphs). Individual evidence
lives in `chapter-outline-qualification`, `backdrop-separation` and
`noaa-painted-tables`. The Fed display-summary portion of #214 is also included and
qualified, but that issue remains open for its magazine cases.

All 763 Swift tests pass. The fast lane passed ten of eleven gates; the remaining
failure identified newly required source dependencies in documented standalone probes.
After adding them, all 15 probe source lists and six documented builds pass, as do
the focused source-list tests. The other gates include Python tool tests, fixture
EPUBs, policies, PDFKit concurrency, release builds and repository checks.

The frozen binary passes all 20 complete corpus conversions and their 890 sampled
source assertions, EPUBCheck, structure, progress and unchanged Mac memory limits.
Warren passes on its first attempt at normal host pressure with 1,181,335,552 bytes
peak RSS, below 1,610,612,736 bytes. No source or limit is reduced to obtain a pass.
The structure index peaks at 120,881,152 bytes for 39,198 references on 510 pages,
below 192 MiB. Three full Fed conversions in one process produce identical EPUBs
and add 1,761 leaked objects per conversion, below the 4,050-object ceiling.

The first repeated-conversion invocation exited 133 while the other integration lane
was using the harness's same default scratch directory. Its captured wrapper error
contains no crash diagnosis, so it is not counted as a pass or attributed conclusively
to scratch contention. The isolated-directory rerun passes. An intervening sandboxed
build could not write Swift's module cache; the successful run used the normal approved
build environment. Raw logs remain outside Git.

The #15 closure covers the issue's original acceptance, including the existing streaming,
subdivision, bounds, cancellation, progress and link behavior, with the source hierarchy
fix now present. Atomic blocks remain intact in their own bounded spine entry; inferred
footnote relationships remain #219. No new physical iOS device budget is claimed.
The corpus assertions are sampled qualification, not a guarantee of full-book fidelity
or ordinary Vision OCR determinism. All work was prepared in isolated worktrees.
