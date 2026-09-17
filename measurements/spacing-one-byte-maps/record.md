# Adobe one-byte ToUnicode maps in NativeSpacingReader (#104)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0, release CLIs.
Work started on `9884ed6`. It was carried by fast-forward onto `bc5eb8c` (#94) and `36c6265`
(#99/#101). Neither touches `NativeSpacingReader`, `MarkedTextReader` or their tests. Every figure
below was measured against `36c6265`.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline CLI | `git archive 36c6265`, `swift build -c release` | `386e70ce…` |
| candidate CLI | this tree on `36c6265` | `6735a25a…` |
| census `base` / `cand` / `gs` | `tools/build-all.sh`: `36c6265` sources / this tree / this tree with the `gs` experiment | — |

No source PDF or EPUB is committed. Lane outputs were deleted after comparison.

## Question

#104 says that `NativeSpacingReader.unicodeMap` (#43) rejects the simple-font ToUnicode maps
Adobe PDF Library writes (one-byte entries under a `<0000> <FFFF>` codespace), so that the #43
missing-space repair "probably never gathers evidence" on FAA, DGA and Fed. #91 found the same maps
in `MarkedTextReader` and read them as one byte.

## Census

`tools/main.swift` is compiled with a tree's library sources and a generated, instrumented copy of
that tree's reader (`tools/gen-census-reader.py`). For every page it records:

- each simple font (Type1, TrueType, MMType1) with ToUnicode and Widths in the page's resources.
  These are the only fonts the reader measures. For each, whether the strict parser accepts the
  map, whether the one-byte reading of the Adobe codespace does, and why any remaining map fails.
- the reader's evidence (shows, decoded shows, measured shows), gated as
  `PDFReflowLibPipeline` gates styled extraction.
- the first check that disqualified the page. Every `invalid = true` in the copy records its
  operator and source line, and operator loops are unrolled so each operator is named.
- every native line that the copy's `apply` changes, mirroring `NativeTextReader`'s loop
  (`census/<book>-<label>.repairs.tsv`, with the matched shows).
- every native line from the product `NativeTextReader`, for a baseline-to-candidate diff.
  These are kept in the scratchpad and deleted after the diff.

`tools/run-book.sh <book>` runs all three labels. `tools/summarize.py` writes `census/summary.txt`.

### Maps

| Book | Pages with measured simple fonts | Pages with a rejected map | … with an Adobe one-byte map | Pages still rejected after | Font-page uses rejected, before → after | What still fails |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| FAA | 521 | **521** | 512 | 514 | 2,603 of 2,603 → 820 | 820 mixed maps: one-byte entries plus a two-byte `<0020> <0020>` entry |
| DGA | 9 | **9** | 9 | 0 | 21 of 21 → 0 | — |
| Fed | 128 | **128** | 127 | 1 | 500 of 500 → 3 | 3 maps under a two-range `<00> <EF>` + `<F000> <FFFF>` codespace |
| Our Flag | 52 | 0 | 0 | 0 | 0 of 164 | — |
| 9/11 | 577 | 0 | 0 | 0 | 0 of 1,047 | — |
| Wallace | 429 | 0 | 0 | 0 | 0 of 811 | — |
| Loper Bright | 114 | 114 | 0 | 114 | 241 of 241 → 241 | all: the two-range codespace, one-byte entries (subset Century Schoolbook) |
| USGS | 2 | **2** | 2 | 0 | 5 of 5 → 0 | — |
| Replay Clocks | 12 | 0 | 0 | 0 | 0 of 111 | — |

So the map half of #104 holds: every FAA, DGA and Fed page with measured fonts had its maps
rejected, and the one-byte reading accepts all DGA and USGS maps, 497 of 500 Fed uses and 1,783 of
2,603 FAA uses.

### The maps were not what kept evidence away

The first disqualifying check per page, identical on the `base` and `cand` labels:

| Book | First disqualifying check (pages) | Shows gathered |
| --- | --- | ---: |
| FAA | `gs` 520, nonzero `Tc` 1 | 0 |
| DGA | `gs` 9 | 0 |
| Fed | `gs` 128 | 0 |
| Our Flag | `gs` 52 | 0 |
| 9/11 | `gs` 577 | 0 |
| Wallace | `gs` 429 | 0 |
| Loper Bright | `gs` 114 | 0 |
| USGS | nonzero `Tc` 2 | 0 |
| Replay Clocks | none on 11 pages; one page has an unpositioned show | 3,407 (3,399 decoded) |

The reader treats `gs` (ExtGState) as unmodeled state and disqualifies the whole page. Every page
in these books that has measured fonts uses `gs` (DGA page 2 sets `/GS0 gs` on its second line,
before any text). A disqualified page yields no evidence, so whether its maps parse never matters. Replay Clocks,
the only pdfTeX book, uses no `gs`. #104's inference was right about the maps but not about the
cause: accepting the maps alone cannot change the output of any of these books.

### Experiment: `gs` without a font accepted (census only, not in the product)

`build-census.sh … --accept-textless-gs` lets the instrumented copy accept a `gs` whose ExtGState
has no `Font` entry (the only ExtGState key that changes text state this reader models). This shows
what the next gates are and whether the accepted maps would then insert anything:

| Book | Next disqualifying check (pages) | Shows / decoded | Pages with decoded shows | Lines changed | Spaces inserted |
| --- | --- | --- | ---: | ---: | ---: |
| FAA | `Tc` 235, `Tw` 216, unpositioned show 54, none 16 | 288 / 94 | 7 | 0 | 0 |
| DGA | none 8, `Tc` 1 | 564 / 211 | 8 | 2 (Type3 removals, below) | 0 |
| Fed | unpositioned show 102, `Tw` 21, `Tc` 4, `Tr` 1 | 0 / 0 | 0 | 0 | 0 |
| Our Flag | `Tc` 52 | 0 | 0 | 0 | 0 |
| 9/11 | `Tc` 576, `Tw` 1 | 0 | 0 | 0 | 0 |
| Wallace | none 429 | 90,787 / 14,596 | 418 | 0 | 0 |
| Loper Bright | `Tc` 114 | 0 | 0 | 0 | 0 |
| USGS | `Tc` 2 | 0 | 0 | 0 | 0 |

Even then, nonzero character or word spacing and shows that continue an implicit cursor
(consecutive `Tj` without `Td`/`Tm`, as Adobe and Word write running text) disqualify nearly every
remaining page. Where evidence survives (FAA 16 pages, DGA 8, Wallace 429), the missing-space
rule inserts nothing: there is no font-change gap of at least 0.15 em between letters that PDFKit
had not already spaced. The experiment was not carried into the product. It would widen a
disqualification gate for no measured repair, and the next gates (`Tc`/`Tw` advance modelling,
implicit-cursor tracking) are a separate design (defect 1).

## Change

- `NativeSpacingReader.simpleFontUnicodeMap(_:)` (internal) rewrites exactly
  `begincodespacerange <0000> <FFFF> endcodespacerange` to the one-byte codespace, then calls the
  unchanged strict `unicodeMap`. Any two-byte entry, any other codespace (including `<0000>
  <00FF>` and the two-range symbol form), a second codespace block, `usecmap`, and streams over
  65,536 bytes still fail.
- `NativeSpacingReader.font` uses it for simple fonts only. Type3 space removal keeps its own
  `characterMap`, which still requires an explicit `<00> <FF>` codespace.
- `MarkedTextReader.spaceCodes` calls the same helper in place of its inline normalization (#91).
  The behaviour is identical: the same regular expression and the same 65,536-byte bound, checked
  before decoding.
- No public API, option or default changed. Docs: `doc/architecture.md` (the spacing paragraph)
  and `doc/regression-testing.md`.

## Every spacing change, per book

The product `NativeTextReader` lines are byte-identical from `base` to `cand` on all nine books:
FAA 32,250 lines, DGA 388, Fed 4,399, Our Flag 1,530, 9/11 25,984, Wallace 27,789, Loper Bright
4,389, USGS 132, Replay Clocks 1,008.

| Book | Inserted spaces, baseline → candidate | Removed spaces, baseline → candidate |
| --- | --- | --- |
| FAA | 0 → 0 | 0 → 0 |
| DGA | 0 → 0 | 2 → 2 (page 1, Type3, #14: `Protein, Dair y` → `Protein, Dairy`, `Ve getables` → `Vegetables`) |
| Fed | 0 → 0 | 0 → 0 |
| Our Flag | 0 → 0 | 0 → 0 |
| 9/11 | 0 → 0 | 0 → 0 |
| Wallace | 0 → 0 | 0 → 0 |
| Loper Bright | 0 → 0 | 0 → 0 |
| USGS | 0 → 0 | 0 → 0 |
| Replay Clocks | 72 on 61 native lines → the same 72 (repair lists identical in page, before and after) | 0 → 0 |

No new insertion exists, so nothing needed review against `pdftotext -layout` or renders, and no
narrowing was needed. The Replay figure counts every PDFKit selection line on pages 1–9, 11 and 12
(10, 6, 10, 7, 4, 6, 13, 6, 8, 1, 1). #43's "62 on 10 of 12 pages" counted differences in EPUB
page text between builds, a different unit (for example, #43's algorithm floats take listing lines
on pages 3–5 out of the page text). The two figures were not reconciled line by line. The native
repair list is identical, and the EPUB comparison below shows Replay's output unchanged, so both
are unchanged. No corpus contract was added, because there is no
repaired space to pin. The reproducer carries the positive and negative checks instead.

## Tests

`Tests/PDFReflowLibTests/NativeSpacingTests.swift`, two new functions:

| Test | Strict reader (`font` → `unicodeMap`) | Candidate |
| --- | --- | --- |
| `adobeOneByteMapsUnderATwoByteCodespaceSupplyWordBoundaryEvidence`: both fonts in the Adobe form, and one of each, decode `event`/`e`/`must`, measure ends 65/73/96, repair `event emust` → `event e must`. Controls: a 0.14 em gap stays joined; a map with a two-byte entry leaves its show undecoded and the line unchanged | fails (4 issues) | passes |
| `onlyTheAdobeCodespaceIsReadAsOneByteAndOnlyForSimpleFonts`: the helper equals the strict parse of the one-byte form, and the strict parser still rejects the Adobe form. Rejected: FAA's mixed `<0020>` entry, the two-range symbol codespace, `<0000> <00FF>`, a second codespace block, `usecmap`, oversized. A Type3 font with the Adobe form gets no removal text; the one-byte form does (`Dairy`) | passes | passes |

The #91 tests (`TaggedRejectionsRemainingTests.swift`, including the `adobeMap` and `twoByteEntries`
font cases) now exercise the shared helper, and they pass. The Type3 label controls
(`sourceType3KerningRepairsOnlyTheTwoDgaLabelSpaces` and the other Type3 tests) and
`sourceFontBoundariesRestoreReplayClocksWordSpaces` pass unchanged.

## Verification

- `swift test`: 465 tests pass (463 at `36c6265` plus 2).
- `scripts/check-all.sh --fast`: exit 0. It covers 465 Swift tests, 204 Python tests, 8/8 fresh
  concurrency processes, 6 fixture conversions, and 13 policy conversions with 22
  rejection/cleanup cases.
- Corpus lane: `tools/lane.sh <case> base|cand` runs `tools/run_corpus_regressions.py --epubcheck
  /opt/homebrew/bin/epubcheck --environment-probe <probe-raster-environment> --execution-context
  host-terminal --case <id>`, one case per call. `tools/compare.sh <case>` then runs
  `tools/compare_conversion_runs.py --allow-different-converters` (`lane-summaries/`). Every run
  passed EPUBCheck and the structural, progress and memory gates. No memory-gate failure occurred,
  so nothing was rerun.

  | Case | Content checks | Baseline | Candidate | compare_conversion_runs |
  | --- | ---: | --- | --- | --- |
  | faa-phak-8083-25c | 339 | pass | pass | passed: 0 changed pages, OCR pages, images, navigation, report fields; markers equal |
  | dga-2025-2030 | 26 | pass | pass | passed: no changes |
  | fed-explained-2021 | 147 | pass | pass | passed: no changes |
  | arxiv-replay-clocks-2023 | 59 | pass | pass | passed: no changes |
  | gpo-our-flag-2003 | 70 | pass | pass | passed: no changes |

  Both runs had the same Vision programs (`sameVisionPrograms: true`).

## Acceptance

- Rejections measured per book, before and after (tables above).
- The one-byte reading is accepted for simple fonts through one helper that both readers share.
- Spacing changes: none in any of the nine books. Replay Clocks' repairs and DGA's Type3 label
  removals are identical. No spurious insertion exists, so none needed narrowing.
- #104's expected benefit, math-spacing evidence on FAA, DGA and Fed, is **not** delivered by this
  change. The `gs` gate blocks it first, and `Tc`, `Tw` and implicit-cursor shows block it next.
  With textless `gs` accepted, the evidence that survives produces no insertion.

## Defects to file

1. **NativeSpacingReader gathers no evidence on any Adobe, Word or GPO book.** A `gs` operator
   disqualifies the page whatever the ExtGState sets. That is 100% of measured pages in FAA, DGA,
   Fed, Our Flag, 9/11, Wallace and Loper Bright. Behind it, nonzero `Tc`/`Tw` (FAA 451 pages,
   9/11 577, Our Flag 52, Loper Bright 114, USGS 2) and shows that continue the text cursor (Fed
   102, FAA 54) disqualify them again. Whether these books have word boundaries PDFKit drops at
   font changes was not measured. Accepting textless `gs` alone produces zero insertions in all
   nine books.
2. **Mixed simple-font maps stay rejected** (FAA: 820 font-page uses on 514 pages). They hold
   one-byte entries plus one two-byte `<0020> <0020>` entry under `<0000> <FFFF>`. This affects
   `MarkedTextReader.spaceCodes` too: such a font declares no space code, so any space-only show in
   it would still cost its tag group under #91's rule. The effect on tag rejections was not measured.
3. **Two-range symbol codespace rejected** (`<00> <EF>` + `<F000> <FFFF>` with one-byte entries):
   Loper Bright 241 uses on all 114 pages, Fed 3. This has the same consequence for
   `MarkedTextReader`'s space codes. The effect was not measured.
4. **Correction to #43's record.** "Nothing changes in any control book" held because no control
   book's page reached the missing-space rule (`gs` on every page), not because the books lack
   such gaps.
