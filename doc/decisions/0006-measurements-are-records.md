# 0006 Measurements are records, not captures

## Context

`measurements/` grew as the record of every experiment: baselines, fidelity fixes, memory
investigations, policy comparisons. Alongside each record accumulated the raw material it was
written from (1,518 gzipped logs, page renders and run logs), and two `check-all.sh` gates plus
the byte-identity comparison came to live there too (`repeated_conversions/`, the vision-titles
captures and `review.json`, `identity.py`). Nothing read the captures after the record was
written, every package client clones the whole repository, and a directory whose name says
"record of past experiments" was running live tooling.

## Decision

`measurements/` holds each experiment's record and the small summaries it quotes, and nothing
else. Raw captures (logs, archives, renders, converted books: `.gz`, `.tgz`, `.zip`, `.tar`,
`.png`, `.jpg`, `.jpeg`, `.log`, `.epub`, `.pdf`, `.plist`) stay out of the tree, and a change may
add at most two megabytes under `measurements/`. Tooling a gate runs lives under `tools/`: the
repeated-conversions harness (`tools/repeated_conversions/`), the vision-titles captures and
review (`tools/vision_titles/`, read by `tools/test_vision_titles.py`), and `tools/epub_identity.py`,
whose own tests run in the Python gate. `tools/check_measurements.py` enforces the rule as the
`measurements-policy` gate in every `check-all.sh` lane, counting committed, staged, unstaged and
untracked additions relative to the base branch (`--base`, default `origin/main`).

The existing captures were pruned in one commit; every removed file remains in history at the
commit each record cites. Each record whose files moved keeps its measured paths and gained a
one-line pointer at the top saying where the file now lives ([0007](0007-records-cite-commits-in-prose.md)).

## Consequences

- A new measurement commits its record and the summaries it quotes (a JSON of results, a short
  table); the logs, EPUBs and renders it was written from are kept outside the repository or
  regenerated from the commands the record gives.
- Records are frozen: the paths and hashes they cite are those of the measured build, and the
  pointer line is the only edit a move makes.
- The gate is fast and offline, so it runs in `--fast` too. A legitimate large addition
  (a summary over two megabytes) needs `--maximum-added-bytes` and a reason in the commit.
- Third-party review derivatives that are rasters (algebra, government-document and Replay
  Clocks renders) are covered by the same rule; the notices in
  [third-party notices](../third-party-notices.md) describe what remains and its provenance.

## Evidence

Commits `61c1dd3` ("Keep gate tooling out of measurements, and stop raw captures at the door")
and `50fd357` ("Prune the raw captures from the measurements tree"); `tools/check_measurements.py`
and `tools/test_check_measurements.py`.
