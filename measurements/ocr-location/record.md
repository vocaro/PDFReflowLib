# OCR text and the converter's location (#94)

Tier: Apple PDF stack plus Vision, library defaults, macOS 27.0 (26A428) arm64, Apple M5 Max,
release CLI. Trees: `d63bbbc` (release SHA-256 `0a0d8616c6719eb9…`) for reproduction and
diagnosis, `0d4f24e` plus this change (`848a0c4a829816d4…`) for the lanes. Six agents shared the
Mac; each measurement line records the one-minute load average. No PDF or EPUB is committed.

## Summary

The issue's premise is inexact. Census OCR does not depend on the binary's directory. It depends
on **which compile of Vision's document-recognition models the process uses**, and Vision keeps
those compiled programs in a cache keyed by the **executable's file name**
(`~/Library/Caches/<name>/com.apple.e5rt.e5bundlecache/26A428/<key>/…/H17C.bundle/H17C.e5`).
Separate compiles of the same model on this Mac produce programs that transcribe the same raster
differently. Every later process of that name reuses the cached programs, so each name looks
repeatable. The copies #51 measured had new names (`pdf-reflow-394147f`, …) and so got fresh
compiles, which usually read clean. Every worktree's `.build/release/pdf-reflow`, and any
same-name copy, shares one cache, and its current programs read noisy. Vision recompiles a
name's programs when a different binary of that name runs, so agents rebuilding `pdf-reflow`
redraw one another's compile. That fits the CDC variance recorded on #68.

This happens inside Vision. No public `RecognizeDocumentsRequest` option removes it. The library
now writes out its request settings (a no-op today), and the tooling records and flags the cache.

## Reproduction (`d63bbbc`, whole book; no page-range option exists)

| Launch | Load | EPUB SHA-256 | Page 2 |
| --- | ---: | --- | --- |
| `.build/release/pdf-reflow` | 137 | `26aadf2e51590656` | `re-identilicatiou`, `rauk`, `(see \|18)`, `uoise` |
| byte-identical copy `scratchpad/issue94/bin-a/pdf-reflow` | 144 | `26aadf2e51590656` | same |
| copy `scratchpad/issue94/tmpx/other-name/deep/pdf-reflow` | 148 | `26aadf2e51590656` | same |
| `.build/release/pdf-reflow`, tool sandbox disabled | 123 | `26aadf2e51590656` | same |
| copy renamed `pdf-reflow-i94base` (new cache) | 15 | `99f941710931292d` | `re-identification`, `rank`, `(see [ 18])` |

All builds report 19 OCR pages. The #51 difference (17 pages, `re-identilicatiou` vs
`re-identification`) is reproduced by renaming, not by moving the file. CDC gave `7279afa97b0c…`
from `.build/release` and from two fresh names, the hash #68 recorded 17 times. Its nine OCR
pages were unaffected by the current `pdf-reflow` programs, so pages 17 and 36 did not differ.
The Blue Book has no OCR pages under library defaults.

## Hypotheses tested

1. **Bundle context and dyld resolution (a).** `otool -L` lists only absolute system libraries,
   and the single `LC_RPATH @loader_path` has nothing relevant beside it. Moving the file changed
   nothing (table above). Refuted as stated. The real key is the name, via the model cache.
2. **Raster bytes (b).** Temporary instrumentation dumped the image `OCRReader` passes to Vision.
   Its RGBA bytes (`2269fd09cbf8a593…`) equal a standalone probe's raster of page 2, while the
   converter read noisy text and the probe read clean. Refuted.
3. **Environment, sandbox, quarantine (c).** No `xattr` on the build product or copies. The
   converter's `HOME` does not move the cache: it stays in the real home and output stays noisy.
   Disabling the tool sandbox changes nothing. There are no `DYLD_`/Vision variables. Refuted.
4. **Implicit request configuration (d).** `RecognizeDocumentsRequest.supportedRevisions` is
   `[.revision1]`. The defaults (automatic language detection, minimum text height 0.03125,
   three candidates, no custom words, `en-US`) print the same in every process. Compute stages:
   only `.main`, with Neural Engine, GPU and CPU supported and `nil` (automatic) by default. Not
   the cause. Pinned anyway (below).
5. **Pipeline state.** Instrumentation OCR'd page 2 at pipeline start, after structure and chapter
   reading, and before and after extracting pages 1 and 2. Under a stale-cache name every point
   gave `f8d5408e6e36` (default) / `6d8b74462ca4` (CPU). Under a new name every point gave
   `c606a4ceb6a1` / `4a0375378794`, matching the probe. Page order (1, 2, 4 vs 2, 4) made no
   difference. Refuted: the difference exists before the converter does anything.
6. **Model cache by name.** Same instrumented binary, same run conditions: named `i94fresh`
   (empty cache) it read clean twice; named `i94oldcache` with a copy of
   `~/Library/Caches/pdf-reflow` it read noisy. That cache held different `H17C.e5` programs
   for keys `27BD40…` and `572C10…` (`main_1024` models) than fresh compiles, while
   `model.anehash` differs on every compile. When a different binary (the probe) ran under a
   copied cache's name, Vision recompiled those entries.
7. **Compilation itself.** `sample-fresh-compiles.sh` runs `probe-page-ocr.swift` under names
   never used before, so every process compiles into an empty cache. Census page 2, default
   device, 16 processes at load 11–18: `c606a4ceb6a1` (clean) ×12, `f8d5408e6e36` ×3 and
   `b4c2ae8b70d0` ×1 (`rauk`, `re-identilicatiou`, `|18`, `uoise`). Programs track the draw:
   572C=`29c341` gave `f8d5…` 3/3 and 27BD=`189b04` gave `b4c2…` 1/1, while other variants read
   clean. The fresh `.build/release` lane evaluation (name `pdf-reflow-77114fe5`) also drew the
   noisy Census transcription. Confirmed: compilation is not output-deterministic.

## Can the library pin it?

- **CPU compute device.** Pinning the only stage (`.main`) to the CPU gave `4a0375378794` in 8 of
  8 fresh processes, but those draws never included the program variants that changed default
  output. With the stale `pdf-reflow` programs the CPU-pinned request still changed: bisect
  `6d8b74462ca4`, and whole-book page 2 `(villiam. e. yancey…)@censua. gor`, `protocted`.
  Vision still compiles the Neural Engine programs with the CPU pin, so some stage the API does
  not expose presumably keeps using them. A CPU pin would change every OCR book's text, add CPU
  time, and still not guarantee the result. Not adopted. GPU and CPU agreed on page 2 wherever
  both were tried.
- **Explicit revision and options.** Adopted: `OCRReader.recognitionRequest(language:)` builds
  `RecognizeDocumentsRequest(.revision1)` with every text option at its SDK default. The request
  equals the previous one (tested), and whole-book Census output under a new name is byte-identical
  before and after (`99f941710931292d`, three runs of the pinned build plus the `d63bbbc` run).
  No public API or default changes.
- **Cache location.** `HOME` is ignored, and no environment variable or default was found in the
  shared cache's strings. Only the executable name selects the cache.

Which transcription is right: the clean draw. Over Census OCR pages 2–20, the share of lowercase
words of four or more letters found in `/usr/share/dict/words` is 88.45% (clean) vs 85.25%
(noisy) and 85.56% (CPU-pinned, stale programs). The clean draw is also the common one, but the
library cannot choose it.

## Tooling change

- `conversion_provenance.vision_model_cache(executable)`: the name's cache directory, whether it
  exists, the program count and a SHA-256 over the compiled programs (excluding the per-compile
  `model.anehash`). Fresh compiles that transcribe identically can still differ in bytes (CDC:
  two fresh runs, identical EPUBs, different `27BD`/`572C` programs), so the fingerprint is a
  diagnostic.
- `evaluate-real-document.py` records `visionModelCache` (mode, before and after) in every
  receipt. `--fresh-vision-cache` (also on `run_corpus_regressions.py`) launches a copy named
  `<name>-<run id>` in the output directory and removes that copy and its cache afterwards. It
  refuses a name already in use. This isolates a run from other processes and builds of the same
  name. It is not reproducible: each run is a new draw.
- `compare_conversion_runs.py` reports `visionModelCaches`, `sameVisionPrograms` and
  `changedOCRPages` (changed pages that are `ocrUsed` in both runs). It adds an `ocrCaveat`
  unless both receipts record identical programs. `passed` is unchanged. An earlier candidate
  refused comparisons without fresh caches; the fresh-lane result below showed that would
  suggest a false remedy, so it was withdrawn.
- `check_reproducibility.py` records the shared name's `visionModelCache` before and after both
  conversions, and `changed`.

Docs: README (OCR bullet), `doc/conversion-options.md` (reproducibility),
`doc/corpus.md#comparing-conversion-runs`, `doc/regression-testing.md#repeat-run-identity`.

## Lanes (`0d4f24e` plus this change; `run_corpus_regressions.py`, EPUBCheck, capability probe)

| Lane | Census | CDC | Blue Book | Load |
| --- | --- | --- | --- | --- |
| `.build/release/pdf-reflow --fresh-vision-cache` | pass, 61 s, noisy draw | pass, 35 s | pass, 36 s | 15–20 |
| same-name copy in scratchpad `--fresh-vision-cache` | pass, 60 s, clean draw | pass, 53 s | pass, 34 s | 19 |
| `.build/release/pdf-reflow` (shared `pdf-reflow` cache) | pass, 5 s, noisy | pass, 7 s | pass, 34 s | 16–18 |
| renamed copy `pdf-reflow-i94lane` (new name) | pass, 59 s, clean | pass, 7 s | pass, 35 s | 13–16 |

Comparisons (`comparisons/`): fresh vs fresh and shared vs renamed each change Census pages 2,
4–11 and 13–20 (all OCR pages of both runs; 2 images; report warnings), with
`sameVisionPrograms: false` and the caveat. Fresh `.build/release` vs shared `.build/release`
Census passes because both drew the noisy transcription. CDC and Blue Book pass in every pairing.
Contract checks pass in all twelve evaluations, noisy or clean: the Census contract does not pin
the words that vary.

At the final tip (`9884ed6` plus this change, release `758d5ea767853bf1…`, load 15–17), library
defaults with the shared cache: `.build/release/pdf-reflow` and a same-name copy in the
scratchpad both pass all three cases (EPUBCheck 0). The first run found a different binary and
recompiled the `pdf-reflow` programs (fingerprint `3e4447b2…` → `3dc11f83…`, Census 33 s), this
time drawing the clean transcription (`(see [ 18])`). The copy reused them (Census 6 s).
The comparator reports no changed pages, images or report fields for any case, with
`sameVisionPrograms: true`. Both locations therefore give the same transcription whenever they
share a compile, and that is the most the converter can promise.

## Verification

- `swift test`: 458 tests at `9884ed6` (455 plus `OCRRequestTests.swift`'s three). Changing a
  pinned option (`minimumTextHeightFraction` 0.02) fails two of them. Positive controls
  `scannedTextUsesRealVision` and the four `selectiveOCR…` tests pass.
- Python: 71 tests in the touched suites, including `test_vision_cache.py` and new evaluator,
  runner, comparator and repeat-check cases. Mutants fail them: counting `model.anehash`
  (1 test), leaving the fresh cache behind (1), and flagging only differing, not unrecorded,
  programs (1).
- `scripts/check-all.sh --fast` at `9884ed6`: 458 Swift tests, 204 Python tests, six fixture
  conversions, 13 policy conversions and 22 rejection/cleanup cases, six fixture repeats with
  identical bytes.

## Defects to file

- **Vision compilation makes OCR text nondeterministic across processes.** Census page 2 draws
  among at least three transcriptions over fresh compiles (12/3/1 of 16), sticky per executable
  name. Worth an Apple Feedback report. Library options, if wanted: a CPU pin measured over
  enough draws to see the bad variants, or recognizing each OCR page more than once.
- **The book language never reaches Vision.** `supportedRecognitionLanguages` lists
  region-qualified languages (`en-US`, `fr-FR`), so `contains(Locale.Language("en"))` is false,
  and a bare `language` (the default `en`, or `fr`) leaves the recognizer on US English. Pinned
  as current behaviour in `ocrRequestAppliesOnlyAnExactlySupportedLanguage`. Expected: match by
  language code.
- **Shared `pdf-reflow` cache across worktrees.** Parallel agents' comparisons of OCR books are
  confounded until they use distinct names or read the new `ocrCaveat`.
