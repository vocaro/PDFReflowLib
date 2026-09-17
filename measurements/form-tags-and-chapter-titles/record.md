# Text-free Form XObjects (#75) and chapter openers tagged as paragraphs (#84)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0, release CLIs.
The work started on `4bc0914`, was carried onto `583713f` (#80/#79) and then `7c46377` (#87) by
fast-forward and 3-way patch; the only conflict each time was `blocks`' parameter list. Every
before/after figure below compares `git archive 7c46377` with this tree (`identity.txt`); the
FAA, DGA, Fed, Our Flag and Replay Clocks EPUBs of both binaries are byte-identical to their
`583713f` counterparts, so the review done on `583713f` carries over unchanged. Pinned conversions
use `--package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 --modification-date
2026-01-01T00:00:00Z`. No source PDF or EPUB is committed; EPUBs were deleted after dumping.

## #84: why chapter openers became paragraphs

`textless-form-proposal.patch` (`measurements/tag-rejections/`) applied cleanly to `4bc0914`. With
it FAA navigation fell from 785 to 773 entries (`block-diffs/faa-navigation-form-patch-vs-4bc0914.diff`):

- **Pages 88, 98, 231, 335.** `Chapter N` (16 point, style 32/20/regular) and the chapter title
  (48 point) are each a `P` group of their own. #67's rule reads a heading-type `P` as a title only
  when the next text in its column is ordinary text, and here the next line is the other title or
  the `Introduction` heading. A temporary diagnostic (removed) listed every heading-type `P` group
  that rule refused: on FAA exactly these eight plus page 203's title and page 473's `C-1`; on the
  Fed the cover label `PUBLIC EDUCATION & OUTREACH` and seven multi-line pull quotes; on Our Flag
  the title-page imprints on pages 3 and 4; none on DGA.
- **Page 203.** One `P` (group 3217) holds `Introduction`, its paragraph, `Pitot-Static Flight
  Instruments` and its paragraph, and the chapter title (`FlightChapter 8` / `Instruments`, group
  3218) follows it in tag order. Read literally, both section titles fuse into one paragraph and
  the chapter title trails the page.
- **Page 473.** `C-1` is the appendix page's folio, 10 point over an 8-point caption, which the
  `4bc0914` spatial reading promoted to an `h6`. Losing it is correct; the same folios `C-2` to
  `C-4` remain headings (see defects).
- Page 96 (`A Third Dimension` before `Chapter Summary`, confirmed against the render) and page 89
  (`Friction`, whose columns no longer interleave) reorder because the tags repair the column order.

## Changes

`MarkedTextReader.swift`: the proposal patch as measured in #75, unchanged. A `Do` of a Form
XObject scans the form and every form it draws (depth 12, 2,000,000 operators per page, one scan per
stream); only a form that runs no `Tj`/`TJ`/`'`/`"`, and whose nested resources all resolve, leaves
the page's tags standing.

`LayoutReconstructor.swift` and `PDFReflowLibPipeline.swift` (no public API, option or default change):

- **Recurring heading styles** (`headingEvidence(on:)`, `blocks(headingStyles:)`). Extraction records,
  per page, the `LabelStyle` (size and body to the half point, all-bold) of each heading-size line
  outside painted graphics and running heads, with at least two letters and not a contents entry
  (the margin bands stay in: a chapter label sits high on its page). A style on three or more pages
  is the book's heading typography. A heading-type `P` group that is not a pull quote and whose every
  line is in a recurring heading or label style (#73/#76's table) reads as a title wherever it
  stands. Evidence per book: FAA 96/20 on 18 pages and 32/20 on 11; Fed 28/20 on 55, 32/20 on 26,
  48/20 on 8, 24/20 on 7, 20/16 on 6; DGA 36/24 on 4; Our Flag 44/18 on 16, 44/14 on 4, 36/18 on 3.
  The Fed cover label (28/22) is on two pages and Our Flag's imprints (24/14, 24/18) on one and two,
  so they keep #67's column test and stay paragraphs; the Fed's 28/20 pull quotes stay paragraphs
  through the pull-quote test.
- **A paragraph tag over a title and its body** (`structuredOrder(headingTypography:)`). A `P` group
  holding a heading-type line with two or more letters followed by a line that is not heading type
  falls back (`structureFallback`: "A paragraph tag spanning a heading and the text beneath it…").
  Only FAA page 203 has one in the five books.
- **Paragraphs tagged in pieces** (`wraps(_:onto:)`, #75). Applying the form fix exposed a second
  class, measured below: the FAA source often tags one paragraph as two `P` elements split at a line
  (page 211 `…in the AFM/` / `POH. These airspeeds include:`, page 105 `…upon stability.` / `The
  allowable location of the CG…`), and captions as a `Figure N.` group plus a continuation group
  (pages 216, 218, 227), so the rejected caption group's continuation became a paragraph. The upper
  line wraps onto the lower when both share the left edge (0.5 em) and type (15%, same bold flag),
  the gap is ordinary leading (under 0.4 em), neither is a heading, list line or `...` leader, the
  upper line reaches its column's right edge and the page's justified measure (three other lines
  within 0.75 em of its width), and either the lower line's first letter is lowercase, the upper
  line breaks at a hyphen or slash, or the column marks paragraphs with space (two gaps of 0.6 to
  2.5 em between same-edge lines). Then two consecutive tagged `P` groups emit one paragraph, and a
  `P` group continuing the last line of a caption, list or oversized-heading group that falls back
  falls back with it.

## Results against `7c46377`

### FAA (`faa-phak-8083-25c`)

| | `7c46377` | candidate |
| --- | ---: | ---: |
| Navigation entries | 785 | 784 |
| Headings h2/h3/h4/h5/h6 | 1/18/10/167/589 | 1/18/10/167/588 |
| Tagged lines (all tagged pages, `tools/tagcount.swift`) | 11,886 / 32,153 | 24,492 / 32,153 |
| Tagged pages with tagged lines / where every group applies | 176 / 49 of 510 | 472 / 141 of 510 |
| `structureFallback` pages | 480 | 470 |
| reader / unsafe / run / tree / titled-group | 456 / 86 / 2 / 1 / — | 367 / 313 / 2 / 1 / 1 (203) |
| Warnings | 1,449 | 1,589 (`uncertainHyphen` 37 → 38) |
| Images | 598 | 598, byte-identical |
| Word multiset | | identical |

- **Navigation.** The only loss is page 473's folio `C-1`; every other title keeps its text and
  level. Two entries reorder with fixed column order (89 `Friction`, 96 `A Third Dimension`). The
  spine's size-based chapter-file boundaries shift with the paragraph markup (file 7 opens at
  `Low Pressure Above` instead of `Airfoil Design`, and so on), with page markers unchanged.
- **Text and block changes** (`block-diffs/faa-7c46377-vs-candidate.diff.gz`): 32 pages change text
  order, 84 only block boundaries; 273 are identical. `tools/classify.py` flags each page (line-level
  paragraphs removed, heading changes, new open-ended paragraphs); every flagged page and every page
  without an interleave-repair flag was read in the block diff, the interleave repairs were
  spot-read (37, 41, 44, 89, 99, 109), and the pages marked "render" were checked against 60-DPI
  `mutool draw` renders or, marked "source order", `mutool draw -F txt`:
  - *Fixed, column interleaving repaired* (the two columns read line by line before): 37, 41, 44,
    89, 99, 109, 110, 115, 130, 150, 154, 176, 193, 351; 96 (render) keeps its
    interleaved paragraphs but now orders its two titles as the page does.
  - *Fixed, paragraphs rejoined or separated as the page sets them*: 22, 32, 78, 93, 102, 105
    (render), 123, 128 (source order), 139, 143, 146, 159, 160 (render), 166, 171, 174, 177,
    185–187, 192, 204, 211, 212, 216, 218, 224, 227, 246, 258, 260, 266, 271, 300, 308, 318, 321,
    336, 342 (render), 353, 369, 392, 398, 410, 418, 424, 442.
  - *Fixed, run-in titles separated from the paragraph they had fused into* (still paragraphs, as
    before): 27, 28, 45, 49, 72, 78, 222, 227, 235, 236, 285, 296, 298, 311, 314, 323, 336, 360, 382,
    384, 388, 402, 404, 409, 413, 429, 430, 446.
  - *Fixed, list, data and reference entries one per paragraph* (fused before): acknowledgements 5,
    contents 6, index 513, glossary letters 477 and 481–511, SAFETY list 62, Mach ranges 139, weight
    table 249, sample problems 276/279/281, report explanations 318 and 321.
  - *Neutral*: 103 and 368 (two column titles swap within a page that still falls back), 206, 345,
    444 (paragraph order within still-interleaved text), 322 (wrapped AIRMET lines joined), 461
    (acronym order), 473 (folio no longer a heading), 474 and 477 (folio position).
  - *Mixed*: 54 and 151 separate a run-in title (`PAVE Checklist: …`, `Coupled Ailerons and
    Rudder`) from its paragraph, but the title, still a paragraph, stays ahead of the page's trailing
    figure while its paragraph joins after it (#63 moves only headings).
  - *Remaining regressions, minor* (tags split at a line with no evidence the rule accepts): 114
    (`Conclusion: with CG forward…` after `…horizontal tail surface.`), 127 (`…there is maximum
    thrust.` / `After liftoff…`, one paragraph in the render), 235 and 360 (the sentence before a trailing figure becomes its own
    paragraph; the paragraph already broke around the figure at `7c46377`), 316/317 (`… A2970 RMK` /
    `PRESFR`, an uppercase METAR wrap on a short line), 318 (`…/TP C182/SK` / `080 OVC/…`), 96
    (`Manufacturers have developed…` after a sentence-ending full line on a page with interleaved
    columns).
- `tools/splits.py` counts mid-sentence boundaries: the candidate introduces the METAR and PIREP
  splits above and no other, and joins 40 that `7c46377` split.

### Dietary Guidelines (`dga-2025-2030`)

Tagged lines 0 → 254 of 380 on 9 tagged pages; `structureFallback` pages 10 → 10 (reader 9; unsafe
+2, pages 4 and 7); navigation 12, identical; images identical; word multiset identical. Text order
changes on pages 2, 3, 9 and 10, blocks on 4 and 5 (`block-diffs/dga-7c46377-vs-candidate.diff`):
the two-column bullet lists no longer interleave (page 3's protein bullets read whole) and fused
bullets separate on 4 and 5. These are the pages #75 reviewed against 60-DPI renders; the
candidate's DGA EPUB equals the plain form patch's (`90ab3828…`), so the wrap rules change nothing
here.

### Controls

- **The Fed**: EPUB byte-identical to `7c46377`; navigation 164; tagged lines 1,891 → 1,903;
  `structureFallback` pages 57 → 56 (page 20's text-free form); warnings 528 → 527.
- **Our Flag**: navigation 38, headings, images and word multiset identical; title-page imprints
  (pages 3, 4) remain paragraphs. Page 12 changes (`block-diffs/our-flag-7c46377-vs-candidate.diff`,
  reviewed against a 70-DPI render): its quoted passages (Beecher, Wilson), tagged one line per
  group, were a paragraph per line; lowercase continuations now join into longer paragraphs, a
  partial repair (other line fragments remain). The printed `princi-`/`ples` break reads `princi ples`,
  as the extracted text already lacked the hyphen.
- **Replay Clocks**: byte-identical. Byte-identical as well (`583713f` vs candidate): Loper Bright,
  CDC, NBS, USGS copper, Blue Book, 9/11, Wallace's algebra. NOAA exited 1 with both binaries under
  the pinned options and was not investigated. The Arabic USCIS guide (outside this task's English
  scope) was converted by mistake once; its output changed (two headings gained on pages 15 and 82)
  and was not reviewed.

## Verification

- **Swift tests** (`Tests/PDFReflowLibTests/TaggedFormAndTitleTests.swift`, 8 functions, 12 cases):
  a text-free form, a nested text-free form, a form showing text, a text-free form nesting one that
  shows text, and an unresolvable form resource; FAA page 88's opener without and with the book's
  heading styles; heading evidence from the third page and without a folio; Our Flag's imprint beside
  another recurring style, with its own style as control; page 203's titled group; two wraps that join
  (slash, spaced new sentence) and three that do not (even leading, short line, leader); a caption
  continuation. `mutations.txt`: disabling each of ten parts fails the test covering it.
- `swift test`: 393 tests pass (385 at `7c46377`). `scripts/check-all.sh --fast`: exit 0 (393 Swift,
  186 Python, fixture conversions, repeat identity, 8/8 concurrency processes).
- **Contracts** (`corpus/regressions.json`, 52 checks on 10 new pages): FAA 88, 98, 203, 231, 335
  (titles as headings, in order, before the first paragraph), 89 (column order and a whole
  paragraph), 105, 211, 227 (joined paragraph and caption); DGA 3–5 (whole and distinct bullets).
- **Corpus lane**, `tools/run_corpus_regressions.py --epubcheck /opt/homebrew/bin/epubcheck
  --environment-probe <probe-raster-environment> --execution-context host-terminal --case <id>`, one
  case per call (`lane-summaries/`), plus `compare_conversion_runs.py --allow-different-converters`:

  | Case | Content checks | Candidate | `7c46377` | form7 (reader only) | nowrap7 | Peak RSS MiB base / cand. | compare |
  | --- | ---: | --- | --- | --- | --- | --- | --- |
  | faa-phak-8083-25c | 201 | pass | 4 fail (89 ×3, 105) | 18 fail (#84 titles on 5 pages, 105/211/227) | 3 fail (105/211/227) | 819 / 790 | 510 page records (paragraph counter), 0 images, markers equal, warnings |
  | dga-2025-2030 | 19 | pass | 4 fail (pages 3–5) | — | — | 101 / 101 | pages 2–10, 0 images, markers equal, warnings |
  | fed-explained-2021 | 135 | pass | pass | — | — | 284 / 283 | 0 pages, warnings |
  | gpo-our-flag-2003 | 67 | pass | pass | — | — | 94 / 94 | 44 records from page 12 (counter), 0 images |
  | arxiv-replay-clocks-2023 | 59 | pass | pass | — | — | 165 / 165 | passed, identical |

  Every run passes EPUBCheck and the structural, progress and memory gates.

## Recommendations and defects to file

1. **Appendix folios as headings.** FAA pages 474–476: `C-2`, `C-3`, `C-4` (10-point folios over
   8-point captions) are `h6` navigation entries; page 473's `C-1` was one at `7c46377`. Expected:
   folios, not headings.
2. **Run-in titles tagged as paragraphs stay paragraphs.** FAA pages 27, 45, 49, 54, 72, 151, 285,
   311, 382, 409, 429 (`Pilot and Aeronautical Information`, `Likelihood of an Event`, `Introduction`,
   `PAVE Checklist: …`, `Vestibular Illusions`…): now separate blocks, but paragraphs; on 72, 285
   and 311 `Introduction` is a label in the book's recurring style yet not a heading. Expected:
   headings, as untagged pages read them. On 54 and 151 the title also stays ahead of the trailing
   figure.
3. **Tag splits without wrap evidence** (the remaining minor regressions above: 96, 114, 127, 235,
   316/317, 318, 360). Expected: one paragraph each.
4. **Space-only shows and `3 Tr` inside an artifact** (#75 recommendations 2 and 3) remain open; the
   reader fallbacks left on DGA (9 pages) and FAA (367) are those and run-in style changes.
