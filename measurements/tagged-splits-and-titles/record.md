# Paragraphs tagged in pieces beside figures (#89), tagged titles and lettered folios (#90)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLIs. The work
started on `090cc70` and was carried by fast-forward onto `9cf6b85` (#74/#85, #92) and `eb0197c`
(formula-crop seeding); the working-tree changes applied cleanly each time. Every before/after
figure below compares an unmodified `git archive eb0197c` build with this tree unless it says
otherwise. The FAA block-change set measured against `090cc70` and against `9cf6b85` is identical
line for line (321 changed block lines); against `eb0197c` it differs by one line only, because
`eb0197c` already makes page 389's `Sectional Charts` a heading. Pinned conversions use
`--package-identifier urn:uuid:00000000-0000-4000-8000-000000000001 --modification-date
2026-01-01T00:00:00Z`. No source PDF or EPUB is committed; EPUBs were deleted after dumping.

## #89: paragraphs split at a tag boundary with no wrap evidence

Each boundary was captured with a temporary diagnostic (removed) that printed, at every
tagged/untagged transition in `blocks()`, the two lines, the gap, the edge offset and the result of
`wraps(_:onto:)`, and was read against a 60–90 DPI `mutool draw` render. The 7c46377 side is
`measurements/form-tags-and-chapter-titles/block-diffs/faa-7c46377-vs-candidate.diff.gz`.

| Page | Boundary | What separates it from a genuine break | Why it split |
| --- | --- | --- | --- |
| 114 | `…horizontal tail surface.` / `Conclusion: with CG forward…` | no space (1 pt gap against 13.5 pt between paragraphs), same edge, full justified line | the upper group falls back (its text runs across figures 5-26/5-27), so the boundary is untagged→tagged; `wraps` returns true but was only consulted between two tagged groups |
| 127 | `…there is maximum thrust.` / `After liftoff, …` | same | same (untagged→tagged, `wraps` true) |
| 360 | `…other aircraft. [Figure 14-44]` / `In addition to basic radar service…` | same | the lower group crosses figure 14-44 and falls back: tagged→untagged, `wraps` true |
| 96 | `…affected portion of the airfoil.` / `Manufacturers have developed…` | no space; the lower line is letter-spaced to the measure | untagged→tagged, and `wraps` false: the column shows no same-size paragraph gap, because the figure crop swallowed the two spaced paragraphs above it (defect 3 below); its only space sets off `A Third Dimension` |
| 235 | `…propeller, or components.` / `This section also describes preventive maintenance that` | no space | tagged→untagged, `wraps` false: one same-size spaced gap in the column (two required); the other space sets off `Supplements (Section 9)` |
| 316, 317 | `+TSRA BR BKN008 OVC012CB 18/17 A2970 RMK` / `PRESFR` | none found | a coded METAR set in separate source paragraphs: the upper line is 19 pt short of the justified edge (set as a paragraph's last line), uppercase report tokens follow, no space. Page 316 splits identically at `7c46377`; page 317 was joined there. |
| 318 | `UA/OV GGG 090025/TM 1450/FL 060/TP C182/SK` / `080 OVC/…` | none found | a PIREP; the upper line is 22 pt short of the edge, where `080` and its space (about 17.5 pt in 10 pt Times) would have fitted, so the source broke the paragraph there |

The key question from the task: on these pages a genuine paragraph break always adds about 12.5 pt
(1.25 em) or sets a short last line; every rejoined boundary has ordinary leading (about 1 pt between
line boxes), a full justified upper line and a flush lower line. Using the page's spatial paragraph
decision as the evidence was tried and rejected: the spatial rule joins any two same-edge lines
unless the upper is short and ends a sentence, so it would merge page 319's TAF change groups
(`FM1500 …` / `FM120000 …`), the acronym list on page 462 and the report explanations on 318.

**Coded reports (316–318) are not fixed.** No geometric evidence separates their wrapped report lines
from page 319's TAF change groups, which are separate lines of the same kind of report at the same
geometry (ragged, uppercase, no punctuation, ordinary leading). Estimating whether the lower line's
first token would have fitted on the upper line admits `PRESFR` but not `080`, and misreads
`FM1500 …` / `FM120000 …` (43 pt left against a 49 pt token estimate). The source's own typesetting
(the upper lines are unjustified last lines of their paragraphs) says these are source paragraph
breaks, so they are left as tagged and recorded as a remaining item.

### Changes (`LayoutReconstructor.blocks`)

- **Transitions.** An untagged paragraph whose last line `wraps` onto the first line of a paragraph
  group opens that tagged block (the group's lines then join it in tag order); a paragraph group
  whose last line `wraps` onto an untagged line hands its text to the spatial paragraph, which the
  ordinary rules continue. Split-marker list groups and title groups (below) never take part.
- **Justified columns.** Where no two same-size gaps show paragraph spacing, a new sentence still
  continues when the column is justified (at least six same-edge lines, more than half reaching its
  right edge) and some line on that edge is set off by space (0.6–2.5 em, any size). A ragged list
  reaches the edge only with its longest entries (acronyms: fails), and a column with no space at all
  keeps #75's even-leading control.
- **Prose density.** Both lines must set at most 0.7 em per character. A right-aligned table row
  spreads a few words over the measure: page 416's `Compass Locator  Under 25  15` is 0.9 em, a
  loosely justified text line about 0.47 (page 96's letter-spaced line). Without this guard the
  transition rule joined `Compass Locator …` with `MH Under 50 …`.

### Results (FAA)

Changed pages for #89 (every one read against a render; no wrong join found):

| Page | Before (`eb0197c`) | After |
| --- | --- | --- |
| 96 | `…affected portion of the airfoil.` ¶ `Manufacturers have developed…` | one paragraph |
| 114 | `…horizontal tail surface.` ¶ `Conclusion: with CG forward…` | one paragraph |
| 125 | `A cross-section … Figure 5-43. …` ¶ `Blade angle, usually measured…` | one paragraph (render: no break) |
| 127 | `…there is maximum thrust.` ¶ `After liftoff, …` | one paragraph |
| 128/129 | `Precession is the resultant action…` ¶ `The rotating propeller…` | one paragraph |
| 178/179 | `During normal combustion…` ¶ `Detonation is an uncontrolled…` | one paragraph (render 179: no break after `[Figure 7-21]`) |
| 235 | `…or components.` ¶ `This section also describes…` | one paragraph (it still breaks around figure 9-7, as at `7c46377`) |
| 263 | `…the steeper it can climb.` ¶ `Maximum AOC occurs…` | one paragraph |
| 360 | `…[Figure 14-44]` ¶ `In addition to basic radar service…` | one paragraph |
| 366 | `…heading are aligned.` ¶ `Under certain circumstances…` | one paragraph |
| 411/412 | `…older types of heading indicators.` ¶ `The remote compass transmitter…` | one paragraph |
| 316–318 | METAR/PIREP report lines | unchanged (see above) |

To see what the column-spacing requirement protects, a probe build with it disabled was diffed
against the candidate over the whole FAA: it added exactly 96, 125, 178/179 and 235, plus fused
entries of the acronym list on pages 462–472; the justified-column evidence gives the first four
and none of the acronyms.

## #90: tagged run-in titles

A temporary diagnostic printed, for each short tagged `P` group, the #67/#84 tests line by line
(heading size, `sectionLabels` membership, `headingTypography`, recurring book style). A probe
(`tools/titles.swift`) listed every standalone line set wholly in one emphasised style on all 522
pages with its tag, and `tools/titlemap.py` found each one's element in the output.

- **Bold and bold-italic titles in the book's label styles** (27 `Pilot and Aeronautical Information`
  10 pt bold and `Notices to Airmen (NOTAMs)` 11 pt bold italic, 54 `PAVE Checklist: Identify Hazards
  and Personal` / `Minimums`, 72/285/311 `Introduction` 12 pt bold, 383 `Operating Rules and
  Pilot/Equipment Requirements`, 409 `Very High Frequency (VHF) Omnidirectional` / `Range (VOR)`, 429
  `Vestibular Illusions`). #84's book-style path is reached only through `headingTypography`, which
  for body-size lines is `sectionLabels`' sub-heading rule; that rule asks for body text directly
  beneath a label narrower than 90% of the prose. Stacked titles (27, 429), two-line titles (54,
  409), a near-full-width title (383) and `Introduction` under its chapter title (72, 285, 311) fail
  it. The groups were therefore neither `introduces` nor titled; they stayed paragraphs.
- **Italic titles** (27 `NOTAM (D) Information`, 45 `Likelihood of an Event`, 49 `Managing External
  Pressures`, 152 `Differential Ailerons`/`Coupled Ailerons and Rudder`, 429 `The Leans`…): 10 pt
  Times italic at body size. `LabelStyle` records only an all-bold flag, so no label test applies.
  114 standalone lines in the book are set wholly in it (48 of them index entries with leaders). Untagged pages do not make them headings either
  (228 `Southerly Turning Errors`, 447 `Drugs`: fused into their paragraphs), so for this class the
  tag boundary is the evidence untagged pages lack.
- **Placement on 54 and 152.** The paragraph under each title continues on the next page, and #63's
  `appendPage` moves only *headings* directly above a continued paragraph past the figure that closes
  the page. The title was a paragraph, so the paragraph moved and the title stayed ahead of the
  figure. Once the title is a heading, #63 handles it unchanged.
- (The task's page numbers 151 and 382 are the block dump's section pages; the titles are on
  physical pages 152 and 383.)

### Change (`taggedTitles`, emitted in `flushTagged`)

A heading-level-0 group not already read by #67/#84 is a title when it reads as one (one to three
lines, under 150 characters, first letter a capital or digit past brackets, no closing `.,;:!?`, no
list marker, contents entry or margin folio, no `....` leader on it or on the entry beneath it or
that entry's group, at most 0.7 em a character) and is not centred over the column's body text
(starting more than 1 em inside a body line and centred on it within 1 em), and either:

- every line is wholly bold, at least body size, in a recurring label or heading style
  (`labelStyles ∪ headingStyles`); or
- it is one line wholly in italic, within 10% of the body size, in title case (every word of four or
  more letters capitalised, at most ten words), directly over a wider, body-size, non-italic,
  non-bold, non-list line on its own left edge, with space (0.5 em) or a bold/heading line above.

It is emitted in tag order as a heading without a validated level (`taggedLevel = nil`), sized for
`rankHeadingLevels`. Title groups never join a neighbouring paragraph through `wraps`.

### Results (FAA navigation, `eb0197c` → candidate)

788 → 891 entries (h5 167 → 171, h6 592 → 691): 109 titles added, 6 folio headings removed, no
level change (`block-diffs/faa-headings-eb0197c-vs-candidate.txt`). By source typography: 10 pt
bold 37, 11 pt bold italic 21, 12 pt bold 4 (`Introduction` on 72, 285, 311, 388), 10 pt italic
47. Renders reviewed: 22, 27, 45, 48, 54, 72, 115, 152, 355, 384, 402, 416, 429, 435, 446; every
addition is a standalone title line in one of the book's title styles. Candidates excluded while
iterating, each read against its page: contents pages 6–15 (`Chapter 1`…, entries with `1-1` folios,
`Appendix A`/`B`), `Class (Watts) (Miles)` (a table header row), `NONDIRECTIONAL RADIO BEACON (NDB)` and
`VOR/VORTAC NAVAIDS` (centred table titles), and `Sample Problem 1`–`13` on 276–281 (bold labels
whose next line is a leader computation; left as paragraphs, which is conservative). Pages 54 and 152
now read caption, title, paragraph.

## #90: appendix folios `C-2`–`C-4`

`FurnitureDetector.record` treats a bare line as a folio only when both parts of `N-M` are integers,
and `folioValue` reads Arabic, chapter-numbered and Roman page numbers. `c-2` is neither, so no text
run (`bottom:5-#(offset)` for chapter folios) and no #62 offset run can form. The same holds for every
lettered part folio: `A-1`…`A-8`, `B-1`…`B-12`, `C-1`…`C-4`, `G-1`…`G-36`, `I-1`…`I-10` on 70 pages
(453–522) stayed in the text, `A-5`–`A-7` and `C-2`–`C-4` as `h6`. `C-1` was only dropped because
page 473's tags now apply. `LayoutReconstructor.isFolio`, behind `isHeaderLike`'s heading floor, did
not read them either.

Change: a single ASCII letter prefix is a part number like a chapter number, in the bare-folio text
group, in `folioValue` (kind `part-<letter>`, so part and chapter folios never share a run) and in
`isFolio`. Results: 68 of the 70 folio lines are removed as furniture (`furnitureRemoved` pages
430 → 498); the six headings go; the word multiset differs by exactly those 68 folios; nothing else
changes. `reflowedPageCount` falls 517 → 508: pages 453–459, 473 and 475 are figure pages whose only
text was the folio. `A-8` (460) and `G-36` (512), the last page of their parts, remain paragraphs.

## Tests and fixtures

- `tools/capture-layout-fixture.swift` records each line's applied tag (`structure`) where the page's
  structure validates, keeping every group `MarkedTextReader.apply` matched (as the pipeline does
  even when another group does not match), and omits a non-finite selection rectangle.
  `SourceLayoutFixture` decodes the optional `structure` and keeps it through `styledContent()`.
  Existing fixtures are unchanged.
- Eighteen `faa-N-tagged` fixtures: 6, 15, 27, 45, 54, 55, 72, 96, 114, 127, 152, 153, 319, 360, 416,
  429, 462, 476 (pages 474 and 475 abort the capture tool on another non-finite value; the folio test
  uses their extracted foot-line geometry instead).
- `TaggedSplitsAndTitlesTests.swift` (11 tests): the two transitions (114, 127, 360) with same-page
  paragraph breaks as controls; the justified column (96); controls for the acronyms (462), TAF
  (319) and NDB rows (416); bold-style titles (27 stacked, 72 opener, 429) with the no-style
  reproducer on 27; italic titles (45, 27); placement past the figure (54–55, 152–153); contents,
  centred table title and header row controls (6, 15, 416); synthetic italic controls (not italic,
  sentence, not title case, a list line or an indented line beneath); lettered folios (furniture
  run, heading floor, page 476 source lines kept, broken offset and two-letter prefix controls);
  the folio reading. Label styles are counted from the fixture pages' own evidence.
- On the `eb0197c` sources the new tests fail 9 of 11 (the two pure-control tests pass).
  `mutations.txt`: disabling each of 18 parts, on the merged tree, fails a test covering it
  (`TaggedFormAndTitleTests` included, which caught the justified column without any space).
- `swift test`: 421 tests pass (410 at `eb0197c`). `scripts/check-all.sh --fast`: exit 0 (421 Swift,
  196 Python, fixture conversions, repeat identity, 8/8 concurrency processes).

## Corpus lane

`corpus/regressions.json` (`tools/addcontract.py`): +66 checks on 30 pages. FAA: joined paragraphs on
96, 114, 127, 128, 179, 235, 263, 360, 366, 412 with distinct neighbours on 96, 114, 127, 235, 360;
distinct TAF groups (319) and NDB rows (416); headings on 27, 45, 49, 54, 72, 152, 285, 311, 383, 409,
429; order past the figure on 54 and 152 and after the chapter title on 72, 285, 311; absent headings
for page 27's fused title pair, contents labels (6, 15), the NDB table title (416) and folios A-5–A-7,
C-2–C-4. Our Flag: page 12's three joined quotations.

`tools/run_corpus_regressions.py --epubcheck /opt/homebrew/bin/epubcheck --environment-probe
<probe-raster-environment> --execution-context host-terminal --case <id>`, one case per call, then
`tools/compare_conversion_runs.py --allow-different-converters` (`lane-summaries/`):

| Case | Content checks | Candidate | `eb0197c` | compare_conversion_runs |
| --- | ---: | --- | --- | --- |
| faa-phak-8083-25c | 274 | pass | 37 fail (all new) | 146 pages (all in the reviewed block diff), 0 images, markers equal, navigation on 75 pages; report: warnings, `reflowedPageCount` |
| dga-2025-2030 | 19 | pass | pass | passed: no changes |
| fed-explained-2021 | 138 | pass | pass | passed: no changes |
| gpo-our-flag-2003 | 70 | pass | 3 fail (all new) | page 12 only |
| gpo-911-2004 | 191 | pass | pass | passed: no changes |

Every run passes EPUBCheck and the structural, progress and memory gates. Additional pinned
conversions against `9cf6b85` produced byte-identical EPUBs for Loper Bright, CDC, Blue Book, NBS,
Replay Clocks, USGS copper, the Census report and Wallace's algebra.

## Remaining and defects to file

1. **Coded weather reports split at source paragraph breaks** (FAA 316, 317, 318). Observed: the
   METAR example's `+TSRA … A2970 RMK` and `PRESFR`, and the PIREP's `…/TP C182/SK` and `080 OVC/…`, are
   separate paragraphs. Expected: one element per report. No geometric evidence separates them from
   page 319's TAF change groups; needs report-aware reading (or a preformatted representation).
2. **FAA page 317 interleaves its columns** (also at `7c46377`): the right column's `12. Remarks`
   item and the METAR example alternate line by line with the left column's items 9–11.
3. **FAA page 96's figure crop swallows two paragraphs.** Observed: `are identical. In both
   examples…` and `As an airfoil moves through air…` (the left column above `A Third Dimension`)
   appear in no text block. Expected: reflowed text beside the figure (crop ownership; #51/#77 area).
4. **Untagged italic titles fuse into their paragraphs** (FAA 228 `Southerly Turning Errors`,
   `Acceleration Error`; 410 `Distance`; 447 `Drugs`, `Exhaustion`, …; 48 `Weather`). Expected: headings,
   as their tagged siblings now are. Tagged italic titles over a bullet list (48 `Airport`, `Airspace`)
   also stay paragraphs.
5. **Last folio of a lettered part retained** (FAA 460 `A-8`, 512 `G-36`): paragraphs, not headings.
6. **`isContentsEntry` misses chapter-prefixed and lettered folios** (`Introduction To
   Flying.......1-1`, `Glossary.......G-1`); the title rule guards leaders itself.
7. **Capture tool aborts on FAA pages 474 and 475** (a non-finite value other than the selection
   bounds reaches JSON serialisation).
