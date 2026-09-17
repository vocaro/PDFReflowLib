# Run-to-run variance (#140, #169 item 3)

Tier: Apple PDF stack plus Vision, macOS 27.0 (26A428), Apple M5 Max (36 GB), release CLI,
library defaults except where an option is named. Baseline is tip `b1c7043`, candidate is
`b1c7043` plus this change. Six agents shared the Mac, so every measurement line records the
one-minute load average. Every converter ran under the executable name `pdf-reflow-i140c` and
every Vision probe under `pdf-reflow-i140`, `pdf-reflow-i140p` or `pdf-reflow-i140x<n>`; each
compiled-program fingerprint is recorded where it matters (#94). No PDF, EPUB, render or probe
binary is committed.

## Summary

Three reported symptoms, three different causes.

- **Reconstruction read a decision out of a `Dictionary`.** `LayoutReconstructor.bodySize` took
  the rounded type size carrying the most characters with `weights.max { $0.value < $1.value }`.
  When two sizes carry the same number of characters, which one wins is the dictionary's order,
  which changes from process to process. Warren pages 291 and 384 (#169 item 3) are exactly such
  pages: read outside the pipeline they came back as 4 or 11 blocks, and 1 or 2 blocks, from one
  binary. The tie now reads as the smaller size. Six runs before: two outcomes on each page.
  Eight runs after: one outcome on each page.
- **The OCR retry set is a property of the compiled Vision models, not of the run.** Eleven fresh
  compiles of one binary read Blue Book page 6 five different ways, retrying it under four of
  them and page 111 under six; compiles sharing a `programsSHA256` always agreed. Eight complete
  Blue Book `--ocr always` conversions under one compile retried the same 61 pages every time,
  and the six with pinned packaging were byte-identical. A few pages do sit on the threshold
  (page 244's uncovered share is 0.2032, page 180's 0.1977), but the compiles that flip a page
  move its share by 0.1–0.25, so no margin or hysteresis around the threshold would bridge what
  actually varies. The library change here is none; the evidence and the caveat are documented
  instead.
- **Peak resident size is a system measurement, not a library one.** Under load, identical
  conversions of one book differ by about 50 MiB (Blue Book `--ocr always`, 8 runs) to 100 MiB
  (earlier records), while their output is byte-identical. The evaluator now records the
  kernel's exact lifetime peak physical footprint as well, and the memory gate takes the lowest
  peak of up to two conversions, so a ceiling near a book's peak no longer flaps while a
  regression that raises every attempt still fails.

The candidate's reconstruction is identical to the baseline's on every page of all 21 English
corpus documents, and the three default lanes pass unchanged.

## 1. A tie in the page's body size (#169 item 3)

### Reproduction

`blocksurvey.swift` (from [#141](../dga-header-and-note-columns/tools/blocksurvey.swift)) reads
a page's reconstructed blocks without the pipeline's synthetic-text-style flag. Six runs of the
baseline build on Warren pages 291 and 384, load 12–13:

| Page | Distinct outcomes in 6 runs | What differs |
| --- | ---: | --- |
| 291 | 2 (4 of 6 / 2 of 6) | 4 blocks (one `preformatted` run, two headings) or 11 blocks (five headings, five `preformatted`) |
| 384 | 2 (4 of 6 / 2 of 6) | `heading` + `preformatted`, or one `preformatted` block |

`stages.swift` hashes each stage of that page's reconstruction. `graphics`, `lines` and the
composed `content` were identical in every run; only `LayoutReconstructor.blocks` differed. With
`SWIFT_DETERMINISTIC_HASHING=1`, eight runs agreed, which names the cause: a decision read in a
hashed collection's order.

Warren page 384 carries two type sizes with the same character count, so
`weights.max { $0.value < $1.value }` returned either. The page's body size sets the heading
threshold, the paragraph measure and the preformatted test, so the whole page changes with it.

### Change

```swift
return CGFloat(weights.max { ($0.value, -$0.key) < ($1.value, -$1.key) }?.key ?? 12)
```

Tied sizes read as the smaller one: on these pages the smaller size is the body the larger
lines stand out from, and it is the size an extra character usually decides for anyway.

### After

| Page | Runs | Distinct outcomes |
| --- | ---: | ---: |
| 291 | 8 | 1 |
| 384 | 8 | 1 |

`DeterministicDecisionTests.swift` covers the rule without depending on a process's hash seed:
sixty-four tied pairs must each read as the smaller size (the baseline fails several of them in
any process, and which ones changes per process), a shuffled page's body size is constant over
100 shuffles, a size holding more characters still wins, and one tied page gives the same blocks
twenty times over. The same file pins the coverage check's row order (below).

### Where else a hashed collection is read

Every `Dictionary`/`Set` iteration in `Sources/PDFReflowLib` was reviewed. Most are membership,
counting or grouping whose result cannot depend on the order (`rejected.formUnion`,
`Dictionary(grouping:)` into a `Set`, per-key memo caches, `largestTagged…min()`). Two order-
dependent reads remained:

- `LayoutReconstructor.spanningFigures` chose a caption's owner with `caption.first(where:)`. It
  now reads the members in page order. A matching member must lie within half a body size of the
  line in x and within a body size in y, so two candidate owners are in the same band and the
  choice is usually unobservable; the survey below shows no corpus page where it mattered.
- `OCRTextCoverage.measure` scanned text rows sorted by their top-left corner only, and stops at
  a work bound of twice the page area, so rows sharing a corner could cut the scan at different
  places. The sort key is now the row's whole geometry and ink.

`FurnitureDetector.apply` reads `plan.dependencies` in dictionary order, but every dependency
points at the outermost row, which depends on nothing, so no chain exists to reorder; it was
left alone rather than changed without a reproducer.

### Corpus survey

`pipeprobe.swift` runs `PDFReflowLibPipeline.reconstruct` (`--ocr never`, references off, 72 DPI
JPEG regions) and hashes each source page's blocks, plus the whole block list, warnings, note
links and chapter starts. `survey.py` repeats it in fresh processes per document and
`compare_surveys.py` compares two builds.

| Build | Documents | Source pages | Runs each | Pages differing between runs | Pages differing from the baseline |
| --- | ---: | ---: | ---: | ---: | ---: |
| `bd80eb2` (the tree before the merge) | 21 | 5,145 | 4, NOAA 3 | 0 | — |
| Baseline `b1c7043` | 21 | 5,145 | 1 | — | — |
| Candidate | 21 | 5,145 | 3, NOAA 2 | 0 | 0 |

(The 21 English documents; the Arabic and Chinese cases are outside this work. Load 9.9–20.2.)
So the tie occurs in the corpus only where the pipeline's own flags make it moot — Warren's
scanned pages carry the synthetic-text-style flag, which the standalone survey tool does not set
— and the fix changes no corpus page.

## 2. Which pages the #116 retry takes (#140 item 1)

### One compile repeats itself

`ocrprobe.swift` replays `OCRReader.read`'s decision steps on chosen pages and prints the
raster hash, the first recognition's line count and text hash, the coverage measurement and, when
a retry runs, both band recognitions and the kept/not-kept verdict.

| Probe runs | Pages | Result |
| --- | --- | --- |
| 6 sequential, load 10–12 | Blue Book 5, 6, 111, 148 | identical raster, text, coverage and verdict every time |
| 4 concurrent, load 10–12 | Blue Book 1–12, 105–115 | identical in all four processes |

Complete conversions agree. Eight Blue Book `--ocr always` conversions (four baseline, four
candidate) under one compiled cache (`programsSHA256 22a4a0e73af782e6`, unchanged by any run):

| Run | Load | Seconds | CPU s | Peak RSS | Peak footprint | Sampled footprint | Retried pages | EPUB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| baseline 1 | 13.4 | 302 | 275 | 550 MiB | 526 MiB | 525 MiB | 61 | (unpinned) |
| baseline 2 | 8.7 | 293 | 265 | 567 | 468 | 468 | 61 | (unpinned) |
| baseline 3 | 8.1 | 301 | 272 | 548 | 491 | 488 | 61 | `af9ee14e25fb7e82` |
| baseline 4 | 8.7 | 300 | 274 | 580 | 471 | 471 | 61 | `af9ee14e25fb7e82` |
| candidate 1 | 8.3 | 310 | 280 | 593 | 603 | 601 | 61 | `af9ee14e25fb7e82` |
| candidate 2 | 9.7 | 301 | 276 | 577 | 543 | 543 | 61 | `af9ee14e25fb7e82` |
| candidate 3 | 9.1 | 303 | 279 | 568 | 473 | 473 | 61 | `af9ee14e25fb7e82` |
| candidate 4 | 9.4 | 304 | 277 | 544 | 476 | 476 | 61 | `af9ee14e25fb7e82` |

The retried pages are the same 61 in every run (121, 123, 124, 125, 129, 130, 132, 134, 136,
138, 140–143, 148, 152, 156, 157, 159, 160, 166, 168, 169, 171, 172, 175, 190, 194, 198, 200,
202, 203, 205–207, 210, 216, 218, 220, 222, 224–227, 230–234, 236, 238, 242, 244–246, 248, 252,
254, 260, 262, 311), the same set #129 recorded, and no page reports remaining uncovered text.
The six runs with a pinned identifier and date are byte-identical. Runs 1 and 2, whose packaging
was not pinned, differ only in ZIP dates and `package.opf`: the repeat check's normalized
comparison reports no changed page at all, so even the recognized text repeated.

### Compiles do not

`freshcompiles.sh` copies the probe to a name no process has used, so Vision compiles its
document models into an empty cache, and records each compile's fingerprint with the pages'
verdicts. Eleven compiles of one binary on one raster:

| Compile fingerprint | Compiles | Page 6 | Page 111 | Page 113 |
| --- | ---: | --- | --- | --- |
| `5f35057eb818e6ce`, `b18ef3a189b64610` | 2 | 0.094, kept | 0.269, **retried** | 0.104 |
| `2dda869df5640452`, `c4c51e08d27ae518` (×2), `22614cb0d67a8299` | 4 | 0.027 | 0.138 | 0.059 |
| `ddd048e42667a122` (×2), `1d83732cbc871b3f` | 3 | 0.271, **retried** | 0.257, **retried** | 0.175 |
| `22a4a0e73af782e6` (the converter's) | 1 | 0.027 | 0.133 | 0.059 |
| `659fda39a6ae257e` | 1 | 0.271, **retried** | 0.288, **retried** | 0.175 |

Five distinct transcriptions of page 6 and four of page 111; the retry takes page 6 under four
of the eleven compiles and page 111 under six. Compiles that share a fingerprint always agreed,
and the compile whose fingerprint equals the converter's gave exactly the converter's verdicts,
so the fingerprint predicted the reading in every case here. `c4c51e08d27ae518` is the
fingerprint #129 recorded, and under it pages 6 and 111 are not retried, as in #129's runs.
Program bytes recur between compiles (three of the five programs are byte-identical in most
draws) while `model.anehash` differs in every one, so a compile is not identified by its
programs alone; excluding `model.anehash` from the fingerprint (#94) remains right for
comparing, since it changes even when the programs and the reading do not.

### No threshold is borderline

`ocrprobe.swift` over all 312 Blue Book pages under the converter's compile
(`histogram.py`): 61 pages indicate loss. Of the 312:

- 20 pages have an uncovered share within 0.03 of the 0.2 threshold; the closest are pages 180
  (0.1977), 163 (0.1971), 244 (0.2032), 250 (0.1966), 132 (0.2047) and 123 (0.2049).
- 9 pages are within one row of the 8-row threshold while over the fraction threshold (125, 140,
  175 at 8 rows; 178, 217, 223, 243, 257, 258 at 7).

So pages do sit near the thresholds, and a *small* perturbation would flip them. But the
perturbation that actually happens is not small: the compiles above move page 6's share from
0.027 to 0.271 and page 111's from 0.133 to 0.288, because the first recognition reads 49–58
lines instead of 50–56 and drops different paragraphs. A margin or hysteresis of the size those
near-threshold pages suggest (±0.03, ±1 row) would not have changed a single one of the eleven
draws, and a margin wide enough to bridge 0.24 would retry most of the book. The retry threshold
is therefore left as it is, and the reproducibility claim is stated per compile instead.

## 3. Memory (#140 item 2)

### What varies

CDC under defaults, eight consecutive conversions of one binary (load 7.1–14.6, identical
output `860308a96d0de135` every time):

| Metric | Lowest | Highest | Spread |
| --- | ---: | ---: | ---: |
| Peak RSS (`wait4`) | 418.7 MiB | 443.2 MiB | 24.5 MiB |
| Peak physical footprint (`proc_pid_rusage` v4, exact) | 325.3 | 336.6 | 11.3 |
| Sampled peak footprint (0.1 s sampling) | 231.9 | 264.4 | 32.5 |

On this book the exact footprint is the steadiest measure, and the sampler misses the true peak
by 61–94 MiB. On Blue Book `--ocr always` (the eight runs in section 2) the order reverses: peak
RSS spans 543.8–593.3 MiB (49.5) and the exact footprint 468.2–602.9 MiB (134.7), because the
retry's purgeable Vision IOSurfaces (#129) are counted or not depending on the machine's memory
pressure at the moment. Earlier records saw ~100 MiB on RSS for both books. Neither measure is
stable enough for a ceiling set near a book's peak, and the output of every one of these runs
was identical, so none of the variance belongs to the library.

### Change

`tools/evaluate-real-document.py`:

- reads the kernel's exact lifetime peak physical footprint from the exited process before
  reaping it (`waitid(WNOWAIT)` then `proc_pid_rusage` with `RUSAGE_INFO_V4`) and records it as
  `converterPeakPhysicalFootprintBytes`;
- takes the lowest peak RSS of up to `--memory-attempts` conversions (default 2). The repeat
  runs only when the first peak exceeds the ceiling, converts the same source with the same
  options purely to measure, and deletes its output; the checked conversion, its EPUB, its
  report and every other gate are untouched. `memoryGate` records every attempt, the lowest
  peak, the footprint and the scope sentence.

A genuine regression raises every attempt and still fails; the noise measured above no longer
does. `--memory-attempts 1` keeps the old single-sample behaviour.

`tools/test_memory_gate.py` gains four tests: a converter over the ceiling on every launch
records three attempts under `--memory-attempts 3` and still fails, keeping its checked EPUB and
leaving no repeat EPUB; one attempt gates on the checked conversion alone; a converter that
allocates 80 MiB on its first launch and 1 MiB afterwards passes with the default two attempts
and fails with one; and the footprint is recorded for the checked conversion and in the gate.
Mutating the tool fails them: gating on the first attempt fails the third test, and dropping the
`WNOWAIT` wait leaves no footprint to record.

### Effect on the lanes

The three default lanes' peaks sit far below their ceilings, so no case took a repeat:

| Case | Ceiling | Baseline peak RSS / footprint | Candidate peak RSS / footprint | Attempts |
| --- | ---: | ---: | ---: | ---: |
| `cia-blue-book-14-1955` | 512 MiB | 256.7 / 234.9 MiB | 264.4 / 242.5 MiB | 1 |
| `census-rrs2002-01` | 512 | 259.9 / 359.4 | 252.6 / 353.6 | 1 |
| `cdc-zombie-pandemic-2011` | 512 | 445.3 / 326.9 | 430.1 / 326.3 | 1 |

Census's footprint exceeds its resident size, which is why both are recorded.

## Gates

- `swift test`: 743 Swift tests pass, including the four new ones.
- `scripts/check-all.sh --fast`: pass (see below).
- `tools/check_reproducibility.py --fixtures --case cdc-zombie-pandemic-2011 --case
  census-rrs2002-01 --case cia-blue-book-14-1955` on the candidate: all nine identical bytes,
  one inherited cache, unchanged during the check.
- Lanes with EPUBCheck and the content contracts, baseline and candidate:
  `cia-blue-book-14-1955`, `census-rrs2002-01`, `cdc-zombie-pandemic-2011`, all pass on both.
  `pairdiff.py` (the repeat check's normalized comparison) reports no changed page on any of the
  three between baseline and candidate; the EPUBs differ only in ZIP dates and the generated
  package identifier, which the lane does not pin.

## Limitations

- **One machine, one OS, one Vision version**, under a load of 7–20 from five other agents.
- **The retry evidence is one book.** Warren's retried pages were not re-examined, and no
  other book was surveyed across compiles.
- **Eleven compiles are a small sample** of a distribution whose shape is unknown; "compiles
  sharing a fingerprint agree" held in eleven draws and is not proof.
- **`--ocr never` for the corpus survey.** Recognized pages' reconstruction is covered only by
  the CDC, Census and Blue Book lanes and the repeat check, not by the 21-document survey.
- **The memory gate's repeat is a second conversion**, so a failing case costs twice the time,
  and two attempts still sample a noisy measure: a regression smaller than the ~50–135 MiB
  spread of a heavy-OCR book remains invisible to it, as it was before.
- **No device measurement** (#28): all figures are Mac process peaks.

## Defects noted for filing

1. **`sampledPeakPhysicalFootprintBytes` under-reports the peak** by 61–94 MiB on CDC, because
   it samples every 0.1 s. The exact figure is now recorded beside it; existing records that
   quote the sampled value understate peaks.
2. **Vision's compile draw decides which pages the retry recovers.** Worth adding to the #94
   Apple Feedback report: eleven compiles of one binary gave five readings of one page. A
   library that wants reproducible `--ocr always` output across compiles would have to recognize
   every page in bands, at about +46% time (#129).

## Files

- `tools/pipeprobe.swift`: whole-pipeline per-page hashes (`survey.py`, `compare_surveys.py`).
- `tools/ocrprobe.swift`: `OCRReader.read`'s recognition and coverage decisions, page by page.
- `tools/stages.swift`: per-stage hashes of one page's reconstruction (`DUMP=<path>` writes the
  composed page).
- `tools/freshcompiles.sh`, `tools/anehash.py`, `tools/compilesummary.py`: fresh Vision compiles
  and what each one reads.
- `tools/histogram.py`: how close a book's pages sit to the coverage thresholds.
- `tools/evalrun.sh`, `tools/memrepeat.sh`, `tools/summarize.py`: pinned evaluations with load,
  retry set and both memory measures.
- `tools/pairdiff.py`: the repeat check's normalized comparison between two evaluations.
- `tools/build.sh`: compiles a probe against a source tree (the library minus `EPUBWriter` and
  `PDFConverter`).

Build a probe with `zsh tools/build.sh tools/pipeprobe.swift /tmp/pipeprobe [source-dir]`.
EPUBs, probe binaries, survey outputs and the `pdf-reflow-i140*` Vision caches were deleted
after recording.
