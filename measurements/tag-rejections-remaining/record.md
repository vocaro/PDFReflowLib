# Space-only shows and invisible text inside artifacts (#91)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0, release CLIs.
The work started on `d63bbbc` and was carried by fast-forward onto `213c944` (#88), `0d4f24e`
(#86/#78) and `ffc45a4` (#97). Each time `corpus/regressions.json` and the docs were re-applied
(`tools/addcontract.py`, one hand-merged section in `doc/regression-testing.md`). None of those
commits touches `MarkedTextReader`, `StructureTreeReader`, `NativeTextReader` or `GraphicsReader`,
so the census below, taken on `d63bbbc`, holds on `ffc45a4`. Conversions were repeated against each
new tip. The final figures compare these binaries:

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `git archive ffc45a4` | `64783bf6…` |
| candidate | this tree on `ffc45a4` | `f14e4854…` |
| earlier baselines | `git archive d63bbbc`, `213c944`, `0d4f24e` | `98301e0b…`, `3b7d8338…`, `747eff4b…` |

Pinned conversions (`tools/one.sh`) use `--package-identifier
urn:uuid:00000000-0000-4000-8000-000000000001 --modification-date 2026-01-01T00:00:00Z`. No source
PDF or EPUB is committed, and each output was deleted after dumping.

## Census on `d63bbbc`

`tools/gen-census-reader.py` derives an instrumented copy of either reader, and `tools/main.swift`
runs it per tagged page behind the pipeline's page-image and synthetic-style gates
(`tools/build-census.sh`, `tools/census.sh`). The copy records the first page-invalidating operator,
each rejected group's reasons, a byte sample per rejected anchor and, for the candidate, where each
ignored space-only show would have landed. Tables: `census/<book>-{base,cand}.tsv` and `.samples`.
Summaries: `tools/summarize.py <book>`.

The counts moved since #75 (`090cc70`). The form fix now scans text-free forms, and DGA is no longer
wholly invalid. The classes #91 names were unchanged:

| Rejected anchors on `d63bbbc` | FAA | DGA | Fed | Our Flag |
| --- | --- | --- | --- | --- |
| no line, spaces only | **145 / 65 pages** | **35 / 8** | **1 (page 36)** | 0 |
| no line, text run | 17 / 9 | 10 / 1 (page 7's sidebar) | 1 (44) | 3 (16) |
| in two lines, text run | 20 / 15 | 0 | 0 | 0 |
| short show (≤ 3 bytes), no line or two lines | 27 / 10 | 3 / 2 | 0 | 0 |
| page invalid: `3 Tr` | — | — | **page 131** | — |

The fonts behind every space-only show are simple fonts: FAA TrueType WinAnsi, DGA TrueType WinAnsi,
Fed Type1 with a `Differences` encoding. Each has a ToUnicode map that Adobe PDF Library writes as
one-byte `bfchar`/`bfrange` entries under a two-byte `<0000> <FFFF>` codespace. On the Fed's page 131
a `BT` inside `/Artifact` sets `3 Tr`, shows six spaces, and resets `0 Tr` before any marked text.

## Change (`Sources/PDFReflowLib/MarkedTextReader.swift` only)

No public API, option or default changed, and no reconstruction code changed.

- **Font tracking.** `Tf` resolves the font through the content stream's resources. It is saved and
  restored with `q`/`Q`, like the text state. An unresolvable or malformed `Tf` leaves the font
  without space codes, so its shows fall under the existing rules. `Tf` never invalidates a page.
- **Space codes** (`spaceCodes`). Only Type1, TrueType and MMType1 fonts have them. A font with a
  ToUnicode map uses the codes the map sends to U+0020. The Adobe `<0000> <FFFF>` codespace is read
  as one byte, because a simple font's codes always are, and `NativeSpacingReader.unicodeMap`
  parses the map. Any multi-byte entry or unparseable map gives no space codes. A font without a map
  uses code 32 under `WinAnsiEncoding`, `MacRomanEncoding` or `StandardEncoding`. Type3 and composite
  fonts, built-in encodings and encoding dictionaries without a map have none.
- **Blank shows.** A `Tj`/`TJ`/`'`/`"` show whose bytes (at least one) are all space codes draws
  nothing. It creates no anchor and costs no group, whether its origin is known, unknown, past a
  line, inside a line or in two lines. Its MCID still counts as shown, so a marked section of only
  spaces does not reject its group.
- **Render mode.** `Tr` accepts 0–3 (it accepted 0–2); clipping modes 4–7 still invalidate the page.
  The mode is saved with `q`/`Q` and judged when text is shown. A show in mode 3 inside an
  `/Artifact` (including spans nested in one) proceeds as any artifact show does. Anywhere else,
  marked or unmarked, it invalidates the page as before. This keeps invisible OCR text over scans
  refusing: `PDFReflowLibPipeline` already strips tags on image-backed pages with any invisible text
  and skips synthetic-style pages.

A narrower rule (ignore a blank show only when it lies in no line) was considered but not built or
measured. A space owns no line wherever it sits, so the reader ignores it everywhere. The census
shows the wider rule also clears groups rejected for an unpositioned space (FAA 7, 99, 150, 415;
Fed 128) and for a line shared with a space show (FAA 35, 79, 177). Every page whose conversion
changed was reviewed below.

## Census after the change

| Book | Pages where every group applies | Some groups rejected | Page invalid | Tagged lines |
| --- | --- | --- | --- | --- |
| FAA (510 tagged) | 138 → **155** | 333 → 316 | 34 → 34 (31 text-showing forms, 3 unmarked unplaceable) | 24,351 → 24,599 of 32,153 |
| DGA (9) | 0 → **5** (3, 4, 5, 6, 8) | 9 → 4 | 0 | 254 → 330 of 380 |
| Fed (118) | 73 → **75** (36, 128) | 44 → 43 (+131) | 1 → **0** | 1,903 → 1,911 of 3,984 |
| Our Flag (51) | 25 → 25 | 26 → 26 | 0 | 1,000 → 1,000 of 1,471 |

No space-only anchor is rejected any more in any book. FAA `noLineAtOrigin` groups fall from 160
to 27 (text runs PDFKit places elsewhere, and short markers). Every page whose status or tagged-line
count changed (`tools/summarize.py`):

- **FAA, all groups now apply (17):** 7, 81, 99, 111, 143, 150, 172, 209, 301, 307, 308, 321, 415,
  416, 418, 419, 420.
- **FAA, fewer groups rejected (60):** 18, 19, 24, 29, 31, 35, 36, 39, 45, 52, 55, 57, 62, 64, 69, 79,
  93, 105, 106, 136, 137, 162, 164, 177, 189, 194, 207, 208, 236, 237, 249, 251, 262, 272, 274, 280,
  313 (one group still rejected, now for run-in origins only), 314, 316, 318, 392, 396, 404, 410, 414, 428, 432, 438, 462–472, 491.
  Each keeps only rejections of other classes: run-in unknown origins (#67), text runs, or markers.
- **DGA:** 3, 4, 5, 6, 8 all apply; 2 (8 → 4 rejected groups, run-in origins remain), 7 (6 → 2, the
  CID sidebar runs remain), 9 (3 → 1: a two-line `12` marker and a shared line remain).
- **Fed:** 36 and 128 all apply. **131** is no longer invalid, but 3 of its 4 groups still fall back
  for run-in style changes (`unknownOrigin`) and a line shared with an unplaceable show, so 1 of 35
  lines is tagged. #75's estimate that 35 lines would apply was wrong: page 131 was not rejected for
  `3 Tr` alone.

## Conversions: navigation and reading order

`tools/pagesum.py`, `tools/pagediff.py`, `tools/navdiff.py`, `tools/block-dump.py` and `tools/nav.py`,
on pinned conversions. `pagediff.py` from earlier records ignored page markers inside a block and
misattributed some pages (416's rows appeared under 413); the copies here attribute them correctly.

### FAA on `ffc45a4`

- Navigation: 906 entries; h2/h3/h4/h5/h6 = 1/18/10/171/706 in both builds, with no heading added,
  removed or re-levelled. Only 3 spine file names differ (size-based chapter files shift by one
  paragraph's markup). `compare_conversion_runs` reports `navigationChanged: false`.
- Images (579) and the word multiset are identical. `structureFallback` pages 470 → 462 (7, 143, 172,
  301, 321, 416, 418, 420 removed; none added); warnings 1,664 → 1,647.
- 23 pages change, the same set on `d63bbbc`, `213c944`, `0d4f24e` and `ffc45a4`. Each was reviewed
  against its block diff and, where marked, a 50–60 DPI `mutool draw` render:
  - *Fixed, rows and lines the source tags separately stop fusing:* 24 and 236 (addresses), 55 (PAVE
    checklist entries), 64 (passenger briefing checklist), 207 and 208 (altimeter computations), 249
    (standard weights; render: one row per fuel), 251 (sample weight rows), 416 (NDB rows `MH Under 50
    25` / `H 50–1999 *50`, whose `H` had joined the row above), 392 (the four time-zone rows).
  - *Fixed, joined:* 318 (`Location: … 25 NM out on the 090° radial,` / `Gregg County VOR`).
  - *Fixed, list labels:* 462–472 (render 466): the acronym list's letter heads (`B`, `H`, `I`, `K`,
    `L`, …, `W`) are separate paragraphs, no longer fused into their first entries.
  - *Neutral:* 7. The contents folio `viii` (foot of the left column in the render) moves from between
    two entries to the top of the page; neither build removes it.
  - On `d63bbbc` and `213c944`, page 392 was also a reading-order repair: the two columns had
    interleaved line by line for eleven lines, with `Measurement of Direction` placed before the left
    column. The candidate read the left column first but left `Mountain`/`Pacific Standard Time` after
    the right column's first paragraph. `0d4f24e` repairs the column order in the baseline itself.
    On `ffc45a4` the candidate only separates the rows, in source order.
- Regressions: none found.

### DGA (lane comparison on `ffc45a4`; block review on `d63bbbc`)

Navigation (12; h2/h3/h4 = 1/1/10) and images (28) are identical; `structureFallback` pages 10 → 7
(3, 5, 8). Text pages 2, 4, 8 and 9 change; pages 3, 5 and 6 change warnings only. The one word
change is `nutrient- dense` → `nutrient-dense`, a hyphenated bullet that now reads whole.

- *Fixed:* 2 (render): `…for so many Americans.` and `The United States is amid…` separate as the
  page sets them. 8 (render): the middle-childhood bullets read left column then right, and the
  adolescence bullet that crosses the columns reads whole. Before, both lists interleaved line by line.
  9: the pregnancy bullets read whole.
- *Improved, residual:* 4 (render). `Incorporate Healthy Fats` came before the right column's
  `100% fruit or vegetable juice` bullet; it now follows `Vegetables and fruits serving goals…` but
  still precedes that bullet's sub-items `- Vegetables: 3 servings per day` / `- Fruits: 2 servings
  per day`. The sub-items are list lines, so their group falls back, and they are placed spatially.
- *Unchanged:* 9's `Older Adults` bullets still interleave (their group has a two-line marker).

### Fed

Pinned EPUBs are byte-identical on `d63bbbc` (`eb48727e…`) and `213c944` (`c057f9af…`). The lane
comparisons on `213c944`, `0d4f24e` and `ffc45a4` change only the `structureFallback` warnings on
pages 36 and 128. Navigation
164 (h1–h6 = 1/1/9/28/63/62) is identical. Page 131 converts identically: its remaining groups fall
back.

### Controls

Byte-identical pinned EPUBs, candidate against the same tip, on `ffc45a4`: 9/11 (`61898144…`),
Wallace (`65b20a45…`), Replay Clocks (`30ae2205…`), NBS (`49ff41d8…`), the nine-page Warren excerpt
built with `qpdf` from source pages 1, 7, 21, 30, 50, 100, 890, 910 and 920 (`f6588bc3…`). Pinned EPUBs were also byte-identical on
the earlier tips: on `d63bbbc`, Warren excerpt, NBS, Blue Book, Our Flag, Replay Clocks, 9/11, Wallace
and Fed; on `213c944`, the same eight; on `0d4f24e`, Wallace, 9/11, Replay Clocks, NBS and the Warren
excerpt. Our Flag and Blue Book lane comparisons on `0d4f24e` and `ffc45a4` report no change. NBS, Blue Book and Warren are untagged, so the reader does not run on
them; the refusal of invisible marked text is covered by the synthetic tests and by the pipeline's
existing gates (`ImageBackedStructureTests`).

## Tests

`Tests/PDFReflowLibTests/TaggedRejectionsRemainingTests.swift` (7 functions, 27 cases) uses a
synthetic tagged page (heading plus a paragraph tagged in two pieces) with independent line geometry:

| Test | `d63bbbc` reader | candidate |
| --- | --- | --- |
| `aSpaceOnlyShowCostsItsGroupNothingWhereverItLies` (next line start, past the line end, unpositioned, `TJ` array) | fails | passes |
| `aVisibleShowInTheSamePlaceStillRejectsItsGroup` (negative control) | passes | passes |
| `onlyAFontThatDeclaresItsSpaceCodeMakesAShowBlank` (Adobe map, one-byte map, WinAnsi without map; controls: map to a letter, built-in encoding, Type3, Type0, two-byte entry) | fails | passes |
| `aMarkedSectionShowingOnlySpacesCountsAsShown` | fails | passes |
| `anEmptyShowIsNotBlank` (negative control) | passes | passes |
| `theFontIsRestoredWithTheGraphicsState` | fails | passes |
| `invisibleTextCostsNothingOnlyInsideAnArtifact` (artifact spaces as on Fed 131, artifact text, restored by `Q`; refusing: marked body text, nested span, unmarked, left on after the artifact, clipping mode) | fails | passes |

`mutations.txt` (`tools/mutate.py`) runs the tests against the `d63bbbc` reader and against twelve
single-part removals. Every removal fails a test: blank shows not ignored, blank identifiers not
counted, no codespace normalisation, font or render mode not restored, invisible text refused
everywhere or nowhere, `3 Tr` refused when set, any mode accepted, Type3 treated as simple, no-map
fonts assumed spaced, and any map value counted.

## Verification

- `swift test`: 455 tests pass (448 at `ffc45a4` plus 7).
- `scripts/check-all.sh --fast`: exit 0 (455 Swift, 196 Python, fixture conversions, 8/8 concurrency
  processes).
- Contracts (`corpus/regressions.json`, `tools/addcontract.py`): 10 FAA checks (distinct paragraphs on
  24, 55, 64, 207, 236, 249, 251, 392 and 416, and page 318's joined value) and 7 DGA checks (page 2
  distinct, page 4's three ordered phrases, two whole bullets on page 8 and one on page 9). On the
  `ffc45a4` baseline all 10 FAA checks fail, and all DGA checks except page 4's first two phrases,
  which only anchor the order. Page 392's column-order checks, drafted on `213c944`, were dropped when `0d4f24e`'s
  baseline passed them.
- Corpus lane on `ffc45a4`: `tools/run_corpus_regressions.py --epubcheck /opt/homebrew/bin/epubcheck
  --environment-probe <probe-raster-environment> --execution-context host-terminal --case <id>`, one
  case per call, then `tools/compare_conversion_runs.py --allow-different-converters`
  (`tools/lane.sh`, `tools/compare.sh`, `lane-summaries/`). Every run passed EPUBCheck and the
  structural, progress and memory gates.

  | Case | Content checks | Candidate | Baseline | compare_conversion_runs |
  | --- | ---: | --- | --- | --- |
  | faa-phak-8083-25c | 339 | pass | 10 fail (all new) | 38 pages: 23 content (reviewed above), 15 warnings only; 0 images; navigation unchanged; markers equal |
  | dga-2025-2030 | 26 | pass | 5 fail (all new) | pages 2, 4, 8, 9 content; 3, 5, 6 warnings; 0 images; navigation unchanged |
  | fed-explained-2021 | 147 | pass | pass | pages 36 and 128, warnings only |
  | gpo-our-flag-2003 | 70 | pass | pass | passed: no changes |
  | cia-blue-book-14-1955 | 9 | pass | pass | passed: no changes |

  No memory-gate failure occurred, so no rerun was needed. Host load was high; one Blue Book
  candidate run took 103 s against 36–39 s for the others.

## Acceptance

- Pages rejected only for space-only shows now apply every tag group: FAA 81, 111, 143, 172, 209, 301,
  307, 308, 418, 419, 420, plus 7, 99, 150, 321, 415 and 416, where some or all of the space shows
  were unpositioned; DGA 3, 4, 5, 6, 8; Fed 36 and 128. On pages with other rejections, only those remain.
- The only page rejected for invisible mode inside an artifact (Fed 131) no longer is. Its remaining
  groups fall back for run-in origins (#67's boundary), and its output is unchanged.
- Navigation is identical per level in every book. Reading order is identical or better on every
  changed page; no regression was found. Invisible text outside artifacts still refuses the page.

## Defects to file

1. **Heading placed before the last bullet's sub-items** (DGA page 4). Observed: `h4 Incorporate
   Healthy Fats` precedes `- Vegetables: 3 servings per day` / `- Fruits: 2 servings per day`, the
   sub-items of the right column's last bullet. Expected: after them. The sub-item lines are list lines
   in a paragraph group, so the group falls back and they are placed spatially.
2. **Two-column bullets still interleave on DGA page 9** (`Older Adults`). Observed: `+ Some older
   adults need fewer calories but still` / `eggs, legumes, and whole plant foods (vegetables` / …
   Expected: each bullet whole. The group is rejected for a short marker in two lines and a line
   shared with it.
3. **Contents folio kept** (FAA page 7): `viii` is a paragraph (now at the top of the page). Expected:
   furniture. This predates the change.
4. **`NativeSpacingReader.unicodeMap` rejects Adobe PDF Library's simple-font ToUnicode maps**, which
   put one-byte entries under a `<0000> <FFFF>` codespace (every FAA, DGA and Fed font inspected). The
   #43 simple-font word-boundary evidence therefore never applies to these books. This is inferred
   from the parser's codespace test and was not measured. `MarkedTextReader.spaceCodes` normalises
   this codespace for its own use.
5. **Correction to #75's record:** Fed page 131 was not rejected for `3 Tr` alone. Three of its four
   groups also show text from unknown origins (run-in style changes).
