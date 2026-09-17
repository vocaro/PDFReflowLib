# Repeat-run identity (#68)

Tier: deterministic Apple PDF stack plus Vision, library defaults, macOS 27 arm64 release CLI,
one Mac. Every conversion pins `--package-identifier urn:uuid:00000000-0000-4000-8000-000000000001`
and `--modification-date 2026-01-01T00:00:00Z`.

| Tree | CLI SHA-256 |
| --- | --- |
| `b9efcc9` | `5affa14bcbc1280b6e04531abcbe31ea902036a69e9fffc667725204af1b83f9` |
| `04efe85` (#69/#70 merged; tooling changes in the working tree do not touch the CLI) | `af5c17019a1e59c165ba14deaa421f6ddaa669066c7e2e663ca5040f7a8fb7bb` |

## Question

#68 reported two runs "of the same binary" on The Fed Explained giving 67 and 118
`structureFallback` warnings, and Our Flag alternating between 688 and 732 blocks. Two later
investigations (see [#67's record](../unknown-show-origins/record.md#reproducibility-68) and
[#72's](../image-backed-structure/record.md)) found byte-identical repeats, and argued that the
pair came from two binaries: a shared `.build/release/pdf-reflow` rebuilt between runs. CDC's
comic produced different Vision text on pages 17 and 36 in one of #72's runs.

## What was added

- `tools/check_reproducibility.py`: converts each source twice with one binary and fails on
  any difference outside `ocrUsed` pages. Rules are in
  [regression testing](../../doc/regression-testing.md#repeat-run-identity).
- Binary identity guards against the probable cause: `compare_conversion_runs.py` refuses
  differing `converterSHA256` unless `--allow-different-converters`; `evaluate-real-document.py`
  re-hashes the converter after conversion (`converterSHA256AfterConversion`) and fails the run
  if it changed; `run_corpus_regressions.py` records `converterSHA256` in its summary and stops
  the lane if the binary changes between cases; the repeat check hashes before and after both
  conversions. The four retained measurement scripts that deliberately compare two builds now
  pass `allow_different_converters=True`.
- `scripts/check-all.sh`: every lane repeats the six fixtures; `--corpus` also repeats Fed
  Explained, Our Flag, CDC (OCR pages) and Replay Clocks (untagged, born-digital).

Tests (20 new, `tools/test_reproducibility.py` plus additions to the comparison, runner and
evaluator tests): identical EPUBs pass; a changed non-OCR page fails and names the page, also for a
heading-to-paragraph change with identical text; a changed OCR page passes and is reported, as does
OCR text that moves spine packing; the exemption needs `ocrUsed` in both runs; packing changes
without OCR, a changed image (named with its referencing page), a ZIP-metadata-only change, a
navigation text change and report differences fail; a stub converter that rewrites itself during
the check is refused in both modes, as are differing hashes in the comparator, a rebuilt lane
binary and a binary changed during evaluation. Mutating the tool (no OCR exemption; no re-hash;
no archive-comment check) fails 3, 2 and 1 tests respectively.

## Sequential or concurrent

Default `concurrent`: both conversions launch together. It halves wall time (Fed 7–9 s instead of
16–17 s) and a result that depends on a sibling process (shared staging, Vision under load) is a
defect this check should catch. The resource gates stay sequential in the runner, which finishes
before the repeat check starts. Both modes were run on every book below with identical outcomes;
`--mode sequential` stays available.

## Evidence

Driver: `run_case.py <scratch> <case> <mode>` (refuses under 5 GiB free, copies `result.json`
with warning tallies to `results/<tree>/`, deletes the output), `loaded_cdc.py` (two CDC checks at
once, four simultaneous conversions), `ocr_control.py`, and `run_all.sh` for the whole set:

```sh
swift build -c release
zsh measurements/reproducibility/run_all.sh "$SCRATCH/evidence"
```

### `04efe85` (merged tree)

| Case | Mode | Result | EPUB SHA-256 | Wall s | Warnings | structureFallback pages | OCR pages |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| Fed Explained | concurrent | identical bytes | `feb80a171101…` | 9.2 | 528 / 528 | 57 / 57 | 7 |
| Fed Explained | sequential | identical bytes | `feb80a171101…` | 16.8 | 528 / 528 | 57 / 57 | 7 |
| Our Flag | concurrent | identical bytes | `4f8bb64bbefe…` | 1.9 | 103 / 103 | 33 / 33 | 2 |
| Our Flag | sequential | identical bytes | `4f8bb64bbefe…` | 3.2 | 103 / 103 | 33 / 33 | 2 |
| CDC comic | concurrent | identical bytes | `7279afa97b0c…` | 9.3 | 85 / 85 | 0 | 9 |
| CDC comic | sequential | identical bytes | `7279afa97b0c…` | 17.8 | 85 / 85 | 0 | 9 |
| CDC comic | concurrent ×2 at once | identical bytes (both) | `7279afa97b0c…` | 9.7, 9.8 | 85 / 85 | 0 | 9 |
| Replay Clocks | concurrent | identical bytes | `65fcd6acbddd…` | 2.0 | 48 / 48 | 0 | 0 |
| Replay Clocks | sequential | identical bytes | `65fcd6acbddd…` | 3.7 | 48 / 48 | 0 | 0 |
| USGS copper | concurrent | identical bytes | `b42402102044…` | 0.3 | 2 / 2 | 0 | 0 |
| USGS copper | sequential | identical bytes | `b42402102044…` | 0.5 | 2 / 2 | 0 | 0 |

### `b9efcc9`

Same books and modes, all identical bytes: Fed `3390f7a859fa…` (57 / 57 structureFallback
pages, 7.3 s concurrent, 15.9 s sequential), Our Flag `4f8bb64bbefe…` (33 / 33), CDC
`7279afa97b0c…`, Replay Clocks `65fcd6acbddd…`, USGS `b42402102044…`. CDC was also repeated four
more times concurrently and twice as two simultaneous checks. With one hand-run pinned pair before
the tool existed and the timed `--corpus` command, that is 12 CDC pairs on this binary, all
`7279afa97b0c…`.
The six fixtures were byte-identical in both modes. Our Flag's hash is the one #67 recorded for
its candidate, and #69/#70 do not change it.

Across both trees, counting the timed `--corpus` command and `check-all.sh --fast` runs: 38 book
repeat checks (76 conversions) plus the hand-run pair, and 30 fixture repeat checks, with zero
failures.

### OCR normalization on real output

Vision gave identical text in all 17 CDC pairs (34 conversions) across both trees, so the
exemption was not exercised by genuine variance. `ocr_control.py` exercises it on real output instead: it converts once and
compares the EPUB with rewritten copies of itself, keeping ZIP metadata (`results/*/ocr-control-*.json`):

| Control | CDC (OCR page 17, plain page 5) | Fed (OCR page 7, plain page 32; 7 OCR pages, multi-document spine) |
| --- | --- | --- |
| every paragraph on the OCR page replaced | pass; `page markup differs on OCR pages [17]` | pass; `[7]` |
| one paragraph on the plain page changed | fail; `non-OCR pages [5]` | fail; `[32]` |
| an image on the OCR page changed | fail; `EPUB/images/image-17.png … (referenced on pages [17])` | fail; `image-8.png … [7]` |
| first navigation heading outside OCR pages renamed | fail; `pages [6]` | fail; `pages [1]` |

Same verdicts on both trees.

## Did the original report reproduce?

No. On both trees, every Fed run (six pairs, sequential and concurrent) gives the same 57
`structureFallback` pages and the same bytes; Our Flag's bytes, and so its blocks, never alternate.
Neither 67 nor 118 appears: 118 is what #67 measured for `b339e39`, 67 an early build of #67's
change. The pair fits two binaries, not one. That is not proof; but the same mistake is now
refused: the comparator rejects mismatched hashes unless told otherwise, and the evaluator,
runner and repeat check fail when the binary changes while they run.

## Runtime cost

- Every lane: six fixtures twice, 1.2–2 s.
- `--corpus`: four books twice, concurrently: 17.9 s on `04efe85`, 22.3 s on `b9efcc9`
  (Fed 7–9, Our Flag 1.5–1.9, CDC 7.7–9.2, Replay Clocks 1.4–1.8). Sequential would be about 35 s.
- Passing cases keep only reports, logs and `result.json` (under 1 MB); failing cases keep both
  EPUBs.

## What this does not show

- Determinism on other machines, OS or Vision versions, with other options, or for books not run.
- OCR stability: text on `ocrUsed` pages is exempt, so a non-Vision defect limited to those pages
  would also be exempt. An OCR page's images, its warnings' page set and every other page stay strict.
- Behaviour under other schedules: two simultaneous processes and four under load were tried.
- Navigation list nesting when bytes differ (heading levels are covered in the page markup).
- Why #72 saw CDC OCR variance: it did not recur in 34 conversions here.
