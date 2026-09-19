# Page retention between extraction and reconstruction

> `identity.py` now lives at `tools/epub_identity.py`; the retired strategy tests and `measured-strategies.patch` were removed from the tree and remain at commit a28fb09; the paths below are as measured.

Bounded memory work under [#15](https://github.com/vocaro/PDFReflowLib/issues/15), on top of
`15f1985`, 2026-09-15, macOS 27 / Xcode 27, arm64. This implements the two retention
strategies that bound per-page memory, keeps the whole-document behavior as a control, proves
all three produce identical output, and measures them on every complete corpus book including
Warren and NOAA. **Issue #15 remains open**: the logical block list still accumulates until
writing finishes, and no physical-device measurement exists.

## What changed

Extraction is now one pass that retains only document-wide evidence: the hyphen-repair
vocabulary, margin-furniture candidates, note-heading pages, chapter matches and the running
character budget. Each extracted page goes to a `PageStore`. Reconstruction is a second pass
that loads one page at a time and needs only that page and its stripped predecessor.

`FurnitureDetector` is phased to match: `collect` records one page's candidates, `resolve`
decides removals from the accumulated ledger, and `apply` edits one page. The original `strip`
entry point runs those phases over an array, so the existing furniture tests still specify
the behavior and a new test proves the streamed path equals the array path on 28 source-derived
9/11 pages plus a synthetic-layer run that crosses the document-wide threshold. Furniture
warnings are inserted at their previous position between extraction and reconstruction
warnings; reconstruction reads only structure-fallback and hyphen warnings, never furniture.

`PageRetention` selects the store behavior:

| Strategy | Between passes | Structure index after extraction |
| --- | --- | --- |
| `resident` | Every page stays in memory (the pre-change behavior, the control) | released |
| `spill` | Each page is encoded as a binary property list in the workspace and reloaded once | released |
| `reextract` | Deterministic native extraction is repeated; pages shaped by recognition are spilled | retained |

Binary property lists round-trip finite, infinite and NaN doubles, which JSON rejects. They
share one slot for equal values, so a negative zero can reload as positive zero; a probe
confirmed this and no reconstruction step reads the sign of zero. Re-extraction cannot repeat
recognition, so any page where recognition was attempted is spilled regardless of outcome,
and re-extracted pages use the whole character budget as their guard, which no page that
passed the first pass can exceed. `PDFREFLOW_PAGE_RETENTION` selects a strategy for this
measurement only; an unknown value is an error, it is not a client API, and the losing
strategies are scheduled for removal.

## Identity gates

Every strategy must produce the identical logical document, assets, warnings and counts.

- `PageRetentionTests.swift` reconstructs all six bundled fixtures and a mixed
  recognition book under `resident`, `spill` and `reextract` and requires equal blocks,
  metadata, chapter starts, asset identities/formats/bytes, warnings and counts. It also
  checks exact reload of a page with styles, inline page markers, structure, drop-cap
  geometry, null rectangles and every flag; that `reextract` repeats only deterministic
  pages; that `resident` never touches disk; that spilled files are removed on reload; and
  that unknown selections are rejected.
- `identity.py` compares two complete EPUBs entry by entry, in order, allowing only the
  package identifier and modification timestamp to differ, and compares the CLI reports
  apart from the output path. `test_identity.py` rejects a changed markup byte, changed image
  bytes, missing, extra and reordered entries, malformed package metadata and changed reports.

## Method

`run.py` runs the retained pre-change converter, built from `15f1985` in a separate worktree,
and the candidate converter under each strategy through `tools/evaluate-real-document.py`,
which verifies the pinned source, records the child's `wait4` peak RSS, samples physical
footprint every 100 ms, checks monotonic progress and completion, and runs EPUBCheck on the
baseline output. Explicit `--reference-images automatic` keeps both binaries on the same
policy regardless of library defaults; Warren uses `never` so it completes under the default
budget, and NOAA uses the established explicit 4 GiB entry/final caps. The harness also samples
each run's own directory once per second, which includes staged images and spilled pages, and
deletes output EPUBs after comparison. One run per strategy per book; timings are single
observations on a shared machine, not distributions.

## Results

All ten complete books convert successfully under every strategy, and **every candidate
output is byte-identical to the pre-change converter's output** apart from the package
identifier and timestamp, with identical conversion reports. Every baseline output passes
EPUBCheck. `results.json` holds the per-run numbers; `summary.md` and `profile.md` are the
rendered tables; `receipts.tar.gz` retains each run's evaluator result, progress log, memory
samples, conversion report, launcher and EPUBCheck log.

| Case | baseline | resident | spill | reextract |
| --- | ---: | ---: | ---: | ---: |
| cdc-zombie-pandemic-2011 | 211.4 | 213.5 | 206.3 | 208.3 |
| cia-blue-book-14-1955 | 142.8 | 142.4 | 130.3 | 130.5 |
| dga-2025-2030 | 67.4 | 67.8 | 65.2 | 68.3 |
| faa-phak-8083-25c | 514.4 | 517.1 | 515.8 | 516.8 |
| fed-explained-2021 | 228.3 | 232.5 | 252.4 | 230.4 |
| gpo-911-2004 | 162.2 | 161.4 | 157.1 | 155.5 |
| gpo-our-flag-2003 | 154.4 | 158.6 | 162.9 | 156.0 |
| gpo-warren-1964 | 336.4 | 322.9 | 305.1 | 304.7 |
| noaa-nca5-2023 | 384.8 | 328.0 | 293.3 | 299.9 |
| wallace-algebra-2010 | 66.4 | 62.8 | 53.8 | 62.0 |

| Case | baseline | resident | spill | reextract |
| --- | ---: | ---: | ---: | ---: |
| cdc-zombie-pandemic-2011 | 364.8 | 366.5 | 366.1 | 366.5 |
| cia-blue-book-14-1955 | 158.0 | 157.7 | 145.4 | 148.1 |
| dga-2025-2030 | 100.9 | 100.8 | 100.6 | 102.2 |
| faa-phak-8083-25c | 810.2 | 809.5 | 793.1 | 812.3 |
| fed-explained-2021 | 283.0 | 281.0 | 279.7 | 282.1 |
| gpo-911-2004 | 125.8 | 102.6 | 93.4 | 102.5 |
| gpo-our-flag-2003 | 87.2 | 88.1 | 93.0 | 85.9 |
| gpo-warren-1964 | 937.6 | 919.8 | 902.0 | 901.7 |
| noaa-nca5-2023 | 981.9 | 935.9 | 910.1 | 911.3 |
| wallace-algebra-2010 | 84.7 | 82.9 | 73.0 | 80.5 |

| Case | baseline | resident | spill | reextract |
| --- | ---: | ---: | ---: | ---: |
| cdc-zombie-pandemic-2011 | 6.97 | 6.84 | 7.06 | 6.83 |
| cia-blue-book-14-1955 | 29.10 | 28.67 | 29.59 | 30.06 |
| dga-2025-2030 | 0.74 | 0.73 | 0.73 | 0.73 |
| faa-phak-8083-25c | 36.60 | 36.58 | 38.19 | 51.50 |
| fed-explained-2021 | 6.57 | 6.57 | 6.57 | 7.39 |
| gpo-911-2004 | 9.98 | 10.09 | 10.50 | 15.90 |
| gpo-our-flag-2003 | 1.24 | 1.25 | 1.25 | 1.66 |
| gpo-warren-1964 | 11.94 | 12.05 | 12.61 | 13.41 |
| noaa-nca5-2023 | 126.40 | 125.38 | 132.19 | 166.33 |
| wallace-algebra-2010 | 9.48 | 9.27 | 9.98 | 13.00 |

Per-stage footprint from the 100 ms samples, for the three largest books (`profile.md` has
every book):

| Case | Run | Extraction end MiB | Extraction peak MiB | Reconstruction peak MiB | Writing peak MiB | Peak MiB | Peak at |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| faa-phak-8083-25c | baseline | 113.5 | 514.4 | 218.5 | 179.8 | 514.4 | 2% extracting page 7/522 |
| faa-phak-8083-25c | resident | 109.9 | 517.1 | 217.8 | 181.2 | 517.1 | 2% extracting page 8/522 |
| faa-phak-8083-25c | spill | 95.6 | 515.8 | 188.5 | 165.8 | 515.8 | 2% extracting page 6/522 |
| faa-phak-8083-25c | reextract | 101.9 | 516.8 | 241.7 | 208.2 | 516.8 | 2% extracting page 7/522 |
| gpo-warren-1964 | baseline | 252.7 | 336.4 | 258.1 | 150.4 | 336.4 | 57% reconstructing page 9/920 |
| gpo-warren-1964 | resident | 234.8 | 322.9 | 267.3 | 135.3 | 322.9 | 57% reconstructing page 9/920 |
| gpo-warren-1964 | spill | 165.6 | 305.1 | 227.3 | 122.0 | 305.1 | 57% reconstructing page 9/920 |
| gpo-warren-1964 | reextract | 258.5 | 304.7 | 227.2 | 122.8 | 304.7 | 57% reconstructing page 9/920 |
| noaa-nca5-2023 | baseline | 319.8 | 362.7 | 384.8 | 170.5 | 384.8 | 58% reconstructing page 79/1834 |
| noaa-nca5-2023 | resident | 269.9 | 328.0 | 327.2 | 145.7 | 328.0 | 57% reconstructing page 60/1834 |
| noaa-nca5-2023 | spill | 226.5 | 290.0 | 293.3 | 113.0 | 293.3 | 58% reconstructing page 76/1834 |
| noaa-nca5-2023 | reextract | 245.8 | 299.9 | 296.7 | 156.3 | 299.9 | 57% reconstructing page 60/1834 |

## Analysis

**Quality is settled by construction.** The identity gate leaves no fidelity question between
strategies, so the selection rests on peak memory, with time as the tie-breaker.

**The refactor alone accounts for part of the gain.** `resident` is the new two-pass code with
every page still in memory. Against the pre-change binary it lowers NOAA's sampled peak from
384.8 to 328.0 MiB and Warren's from 336.4 to 322.9 MiB, because the structure index is
released after extraction and the vocabulary is accumulated per page rather than through a
whole-document flat map. On the smaller books it is within a few mebibytes either way, and
its timing matches the baseline everywhere.

**Spill lowers the peak further wherever pages are a material share of memory.** Relative to
`resident`, spill trims NOAA by another 34.7 MiB, Warren by 17.8, Blue Book by 12.1, algebra
by 9.0, and lowers the 9/11 reconstruction-phase peak from 71.4 to 59.4 MiB. Its extraction-end
footprint is the lowest of the four on eight of ten books; the difference between `resident`
and `spill` at that point, 43 MiB on NOAA and 69 MiB on Warren, is the retained page model.
It costs 0 to 5 percent wall time. On two short books, Fed Explained and Our Flag, its sampled
peak is 20 and 4 MiB above `resident`; a three-run repeat of those two books is recorded below.

**Re-extraction never beats spill on memory and is the slowest.** Its peaks tie spill within
7 MiB on NOAA, Warren and Blue Book and are above spill on algebra and Fed Explained. Inside
reconstruction it is the worst strategy on FAA, 241.7 MiB against 188.5 for spill and 218.5 for
the baseline, because repeating attributed PDFKit extraction stacks framework memory on top of
rasterization. Its writing-phase footprint on NOAA is 156.3 MiB against spill's 113.0 because it
must keep the structure index alive. Wall time rises 12 to 59 percent, and it carries two
design liabilities spill does not: correctness depends on PDFKit extraction being repeatable,
and any page that attempted recognition must be spilled anyway.

**Where the peaks actually are.** Page retention moves the extraction-end and reconstruction
footprints; it does not touch framework transients, and on several books those set the peak.
FAA peaks at 514 to 517 MiB in every run during pages 1 to 9, the first eight-page PDFKit
window, and drops by 200 MiB when the document is reopened for the next window; retained
pages on that book are under 20 MiB. The CDC comic peaks during Vision recognition. NOAA and
Warren peak early in reconstruction, where rasterization joins the retained model. The block
list still accumulates until writing finishes, which is the 113 to 170 MiB writing-phase
footprint on NOAA. The FAA spike was traced afterwards to PDFKit loading the whole structure
tree on the first tagged page, which no windowing changes; see the
[structure-tree investigation](../pdfkit-structure-tree/record.md). The remaining
library-side lever is streaming blocks to the writer.

**Disk.** Spilled pages are binary property lists in the workspace, each removed on reload and
the directory removed after reconstruction. The peak run-directory column is dominated by staged
images and sampled once per second, so it does not isolate spilled bytes; the largest visible
effect is 9/11 at 109.9 MiB against 79.4 for `resident`.

## Selection

`spill` is selected. It produces identical output, has the lowest or tied-lowest peak
footprint on every book where retained pages matter, the lowest RSS on nine of ten books, and
a wall-time cost within 5 percent. The physical-device runs below confirm the ordering.

### Retirement

After the device confirmation, `resident`, `reextract` and the `PDFREFLOW_PAGE_RETENTION`
variable were removed: `PageStore` is now spill-only and the pipeline has no strategy
parameter. `measured-strategies.patch` restores the measured three-strategy sources from the
retired ones, and `retired-strategy-tests.swift` is the measured test file, including the
cross-strategy identity test. The retained tests cover repeatable spilled reconstruction with
a clean workspace, exact page reload, the furniture ledger and cancellation. After retirement
184 Swift tests pass on macOS and the iOS Simulator, the six fixture conversions pass, and the
Python tool and measurement tests pass.

### Repeat runs on the two short books

Three further runs of Fed Explained and Our Flag, baseline against `resident` and `spill`,
all byte-identical again (`repeat-1.json` to `repeat-3.json`):

| Book | Run | Baseline MiB | Resident MiB | Spill MiB |
| --- | ---: | ---: | ---: | ---: |
| Fed Explained | 1 | 226.8 | 238.3 | 239.6 |
| Fed Explained | 2 | 206.8 | 238.1 | 220.6 |
| Fed Explained | 3 | 232.4 | 237.0 | 228.6 |
| Our Flag | 1 | 155.5 | 155.0 | 162.9 |
| Our Flag | 2 | 162.8 | 161.4 | 159.4 |
| Our Flag | 3 | 163.5 | 165.3 | 164.0 |

Identical baseline runs of Fed Explained spread over 25 MiB, and spill lands inside that band
on both books with no consistent ordering, so the single-run excess in the main table is
run-to-run variation rather than a cost of spilling. Retained pages on a 135-page or 56-page
book are too small to show above that noise.

## Gates

- **Swift**: 187 tests pass on macOS and on the iOS 27 Simulator (iPhone 18 Pro), including
  the eight new retention tests. `swift test` inside `check-all.sh --corpus` passed after the
  `finish` cleanup step; the earlier gate run exposed the empty page directory through the
  existing test that requires only `assets` in the workspace, and the step was added for it.
- **Python**: 102 tool tests pass, plus the nine measurement-tool tests here.
- **Fixture and policy conversions**: the six fixture conversions and the native concurrency
  smoke gate pass. The policy checker's `ocr-always` case fails on this working tree because
  it relies on the library's reference-image default, which a separate uncommitted change in
  the tree switches from `automatic` to `never`; the current build reports zero images under
  the default and one with `--reference-images automatic`, matching the pre-change binary.
  That is outside this work.
- **Structure index**: peak RSS 119,816,192 bytes under the 192 MiB ceiling.
- **Corpus lane under library defaults**: all eight books convert, pass their RSS ceilings,
  EPUBCheck and progress checks. Six content contracts fail solely on "missing preserved
  images", the supplementary references the changed default omits; Our Flag and algebra pass.
- **Corpus lane with the reviewed policy pinned**: rerunning the lane through a launcher that
  adds `--reference-images automatic`, with `spill` as the library default, passes all eight
  reviewed content contracts, RSS ceilings, EPUBCheck and progress checks. Warren and NOAA stay
  outside this lane as before under #5.

| Book (spill default, automatic references) | Peak RSS MiB | Sampled footprint MiB | Seconds |
| --- | ---: | ---: | ---: |
| cdc-zombie-pandemic-2011 | 365.8 | 208.5 | 6.84 |
| cia-blue-book-14-1955 | 150.0 | 130.0 | 30.56 |
| dga-2025-2030 | 100.5 | 75.8 | 0.73 |
| faa-phak-8083-25c | 799.9 | 510.2 | 38.57 |
| fed-explained-2021 | 279.6 | 230.7 | 6.67 |
| gpo-911-2004 | 93.6 | 152.0 | 10.63 |
| gpo-our-flag-2003 | 93.1 | 161.0 | 1.35 |
| wallace-algebra-2010 | 73.9 | 54.7 | 9.89 |


## Physical device

A temporary host app (`device/host/`) links the library, runs the public `PDFConverter` on a
bundled source with the same policies as the Mac runs, samples `task_vm_info.phys_footprint`
every 100 ms, and reports the conversion counts, warnings and a report fingerprint. Each
strategy runs in a fresh process launched through `devicectl` with the library's selection
variable, on an iPhone 17 Pro Max (iPhone18,2) running iOS 27.0 with 12 GB of memory and
about 3.5 GB available to the process at launch. Xcode's simulator is not involved.

| Book | Strategy | Peak footprint MiB | Peak RSS MiB | Seconds | Report fingerprint |
| --- | --- | ---: | ---: | ---: | --- |
| Warren | spill | 210.0 | 258.9 | 16.9 | 8ca90d2c… |
| Warren | resident | 220.3 | 272.7 | 15.7 | 8ca90d2c… |
| Warren | reextract | 240.0 | 290.1 | 18.6 | 8ca90d2c… |
| NOAA | spill | 236.2 | 450.7 | 179.7 | 9f49f75d… |
| NOAA | resident | 255.6 | 489.0 | 177.6 | 9f49f75d… |
| NOAA | reextract | 241.0 | 454.5 | 224.4 | 9f49f75d… |
| FAA | spill | 517.8 | 793.5 | 47.4 | 35d9c5e1… |

The device reproduces the Mac ordering on Warren: spill lowest, the resident control next,
re-extraction highest, with identical counts and warnings across the three. On NOAA, the
1,834-page conversion completes on the phone in about three minutes under every strategy,
including the 1.4 GB EPUB; spill peaks 20 MiB below the resident control and 5 MiB below
re-extraction, which is 25 percent slower and has the highest RSS after resident. Device
footprints are lower than the Mac's throughout, so the Mac corpus numbers overstate what
the phone needs, while the ordering between strategies is the same. FAA is the exception:
its 517.8 MiB device peak matches the Mac's, because it is PDFKit loading the document's
structure tree, not retained pages; see the
[structure-tree investigation](../pdfkit-structure-tree/record.md). Device numbers are
single runs and the app was in the foreground with the idle timer disabled; they are not a
latency distribution or a shipping budget.

## Limitations

- One run per strategy per book on a shared Mac. Footprint is sampled every 100 ms and can miss
  short spikes; RSS is the kernel high-water mark. Differences under about 10 MiB are inside
  run-to-run variation on the small books.
- The corpus tables are Mac memory. The device section covers one iPhone and two books,
  one run each; device budgets remain unqualified under #15, #5 and #28.
- The process peak on image-heavy or recognized books is set by PDFKit and Vision transients,
  which no retention strategy changes.
- The measured candidate binary is `f5b4cb9f…c05f`. After the measurement, the store gained
  a `finish` step that removes its empty page directory so the workspace again holds only
  assets; the full macOS, iOS Simulator and corpus gates run on that later build, and the
  change affects no output bytes.
- The working tree carried another in-progress change to the reference-image default; explicit
  `--reference-images` flags keep both binaries on the same policy, so it does not affect the
  comparison.

## Reproduction

```sh
git worktree add /tmp/pdfreflow-baseline 15f1985
(cd /tmp/pdfreflow-baseline && swift build -c release)
swift build -c release
python3 measurements/page-retention/run.py \
  --baseline /tmp/pdfreflow-baseline/.build/release/pdf-reflow \
  --candidate .build/release/pdf-reflow --output /tmp/retention \
  --epubcheck /opt/homebrew/bin/epubcheck
python3 measurements/page-retention/summarize.py /tmp/retention/results.json
python3 measurements/page-retention/profile.py /tmp/retention
python3 -m unittest discover -s measurements/page-retention -p 'test_*.py' -v
scripts/check-all.sh --corpus
```

All ten pinned sources must be present in `corpus/cache/`. Baseline SHA-256
`607dc2d9…6e44`, candidate `f5b4cb9f…c05f`; `results.json` records both in full.

