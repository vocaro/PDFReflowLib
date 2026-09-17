# FAA heading and folio leftovers (#97)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLIs. Diagnosis and
the first measurements ran on `d63bbbc`; the change was carried onto `213c944` (#88) and then
`0d4f24e` (#86/#78 column order) by re-applying the same patch, and every figure below compares an
unmodified `git archive 0d4f24e` release build (converter `36bda487…`) with this tree (`5ec88fdc…`).
Pinned conversions use `--package-identifier urn:uuid:00000000-0000-4000-8000-000000000001
--modification-date 2026-01-01T00:00:00Z`. The same twelve FAA pages and the same fourteen
headings changed on each of the three bases. Corpus `faa-phak-8083-25c` (SHA-256
`247929ca…95cb7`). No PDF or EPUB is committed.

## Diagnosis

Layouts were captured with `tools/capture-layout-fixture.swift` (pages 48, 228, 447, 459–461, 511,
512, 6, 7; none of #99's aborting pages) and replayed through `LayoutReconstructor.blocks` in a
temporary test; pages were read against `mutool draw` renders.

| Item | Page | What the issue said | What happens |
| --- | --- | --- | --- |
| 1 | 447 `Drugs` … `Tobacco`, `Hypoglycemia and Nutritional Deficiency`, `Motion Parallax` | fused | No usable tags. 10-point Times-Italic over 10-point Times-Roman, 15.7 pt clear above, 3 pt to the paragraph on the same edge: exactly #76's sub-heading geometry, but `sectionLabels` admits only wholly bold lines (`LabelStyle` recorded only a bold flag), so the line joins its paragraph. |
| 1 | 228 `Southerly Turning Errors`, `Acceleration Error` | fused | Same typography and geometry. On `d63bbbc` the page's two columns read interleaved line by line, with or without its 16 tags (the class of #86), so the titles stood alone; on `0d4f24e`, which reads the columns in order, both fuse (`Southerly Turning Errors When turning in a southerly…`). |
| 1 | 48 `Weather` | fused (untagged) | Not fused and tagged: `V = EnVironment` (11-point bold italic, the PAVE checklist title) has an `=` and fewer than two three-letter words, so it is not a prose row and seeds a displayed-formula crop (eb0197c's seed); label expansion admits `Weather` beneath it. Both titles appear only inside a `Preserved region from page 48` image. Page 47's `A = Aircraft` is lost the same way. `P = Pilot in Command (PIC)` and `E = External Pressures` read as prose rows and were already headings. |
| 1 | 48 `Airport`, `Airspace` | tagged, paragraphs | #90's tagged italic rule refuses a list line beneath. The bullets sit 9 pt (0.9 em) inside the title's edge. |
| 2 | 460 `A-8`, 512 `G-36` | kept, cause unknown | Both are blank pages whose only mark is the folio. `FurnitureDetector.record` did `guard let gap = inward.min(), …`: with no other line there is no inward gap, so the folio was never recorded. And `apply` refuses any removal that empties a page. |
| 3 | 6, 15 | `isContentsEntry` misses `…1-1`, `…G-1` | Its folio alternative took Arabic or Roman numbers only. |

`Distance` on page 410, listed among the fused titles in #90's record, is the header of a table
column (`Distance` over `(Miles)`), not a title; it is left alone and made a control.

## Changes

- **Italic title tier** (`LabelStyle`, `sectionLabels`). `LabelStyle` gains `italic`, set only on a
  line that is not bold and is wholly italic, so bold and bold-italic labels keep their existing key.
  The #76 sub-heading tier accepts a wholly italic line in a recurring italic style (three pages, the
  #73 table, recorded by `labelEvidence` as bold styles are) when it is in title case
  (`isTitleCase`, the #90 test, now shared), not a `Figure`/`Table` caption, and the line beneath is
  neither italic nor bold and is either body text on the title's edge (not a list line) or a list
  it heads (`opensListBeneath`). Clear space above, width, size and gap tests are #76's.
- **Titles over lists** (`opensListBeneath`, used by the tier above and by #90's tagged
  `setsItalicTitle`): a list line directly beneath whose marker stands from 0.5 em outside to 2.5 em
  inside the title's left edge.
- **Mnemonic titles are not formulas** (`isLetterMnemonic`, `graphicsWithLabels`): a wholly bold line
  of one capital, ` = `, a capitalised word of three or more letters and up to six more words of two
  or more letters seeds no formula crop.
- **Lone folios** (`FurnitureDetector`): a bare folio is recorded even when the page has no other
  line; `apply` may empty a page only when every removed line is a bare folio of a run
  (`Plan.bareFolios`). Empty pages already serialise as page-boundary markers.
- **Contents entries** (`isContentsEntry`): the folio after the leader may be `N-M` or `L-M`.

No option, public API, warning code or default changes.

## Results

**FAA** (`block-diffs/`): navigation 892 → 906 on `0d4f24e` (891 → 905 on `d63bbbc`): 14 added, none
removed, no level change, all h6:

| Page | Added heading | Review |
| --- | --- | --- |
| 47 | `A = Aircraft` | render: PAVE checklist title; was a crop; its text now reflows |
| 48 | `V = EnVironment`, `Weather` | render: title and italic sub-title over `Weather is a major…`; was a crop |
| 48 | `Airport`, `Airspace` | render: italic titles over their bullets; were paragraphs |
| 228 (dump page 227, inline marker) | `Southerly Turning Errors`, `Acceleration Error` | render: italic titles at the top of the right column and after `[Figure 8-36B]`; each now split from its paragraph |
| 447 | `Drugs`, `Exhaustion`, `Poor Physical Conditioning`, `Alcohol`, `Tobacco`, `Hypoglycemia and Nutritional Deficiency`, `Motion Parallax` | render: italic titles, each now split from its paragraph |

Folios: eight lone folios go as furniture, each on a page whose render shows nothing but the folio:
`4-10` (97), `9-14` (244), `10-12` (256), `12-26` (310), `15-12` (387), `17-30` (452), `A-8` (460),
`G-36` (512). Report: `imageCount` 581 → 579 (the crops on 47 and 48), `reflowedPageCount` 508 → 500
(the eight blank pages), `furnitureRemoved` on those eight pages, `imageRegion` gone on 47 and 48.
No other page's text changes (the block diff has 46 changed lines).

Contents entries: every leader entry on pages 6 and 15 now reads as one; no output changes, as the
#90 title rule already guarded leaders.

**Lane** (`0d4f24e` vs candidate, `tools/compare_conversion_runs.py --allow-different-converters`):

| Case | Checks | Baseline | Candidate | Changes |
| --- | ---: | --- | --- | --- |
| faa-phak-8083-25c | 329 | 18 fail (all new) | pass | pages 47, 48, 97, 228, 244, 256, 310, 387, 447, 452, 460, 512; navigation on 47, 48, 228, 447; 2 images; markers equal |
| fed-explained-2021 | 147 | pass | pass | none |
| gpo-911-2004 | 191 | pass | pass | none |
| wallace-algebra-2010 | 130 | 2 fail (new) | pass | pages 175, 437 only (blank pages carrying only `175`/`437`, render-checked); navigation unchanged |
| gpo-our-flag-2003 | 70 | pass | pass | none |
| arxiv-replay-clocks-2023 | 59 | pass | pass | none |

Heading sets of Fed, 9/11, Wallace, Our Flag and Replay Clocks are unchanged (no navigation change).
Every run passes EPUBCheck and the structural, progress and memory gates (FAA peak RSS 882 MB).

## Tests and contracts

- Fixtures `faa-48/228/447/460/512-tagged` (page 447 carries 2,825 paints, 534 KB).
- `FAAHeadingLeftoversTests.swift` (7 tests): italic style evidence and the unchanged bold-italic
  key; untagged titles on 447 and 228 above their paragraphs, with the no-style reproducers; page 48's mnemonic, italic and
  list titles with the crop reproducer; mnemonic controls; synthetic italic controls (no style, not
  italic, ordinary leading, sentence, not title case, caption, italic beneath, nested list); lone
  folios on 460 and 512 with controls (broken offset, blank page with a running head); contents
  entries with controls and every leader entry on pages 6 and 15.
- `TaggedSplitsAndTitlesTests`: #90's synthetic control "a list line beneath refuses the title" is
  reversed by this issue; it now expects a title over a list on its edge and keeps a list nested
  3 em deeper as the control.
- On `d63bbbc` and on `0d4f24e` sources (with a shim for the new symbols) all 7 new tests and the
  updated #90 test fail (37 issues); the other #90 tests pass. `mutations.txt` (on this tree): each of
  13 parts, disabled in turn, fails a test covering it.
- `corpus/regressions.json` (`tools/addcontract.py`): FAA headings on 47, 48, 228, 447; order on 48
  and 447; absent `A-8` (460) and `G-36` (512); controls: no heading `Distance` (410) or `Figure
  17-20. Self-imposed stress.` (447), heading `E = External Pressures` (48). Wallace: absent `175`
  and `437` on their blank pages. Two `absentText` checks for the fused `Drugs Drugs` were dropped:
  page text joins blocks with spaces, so they cannot distinguish heading from paragraph.
- `swift test`: 448 tests pass (441 at `0d4f24e`). `scripts/check-all.sh --fast`: exit 0 (448 Swift,
  196 Python, fixture conversions with identical bytes, 8/8 concurrency processes).

## Remaining and defects to file

1. **Formula seeds on title-like word equations.** Only bold single-letter mnemonics are exempted; a
   plain-type label such as `A = Aircraft` in another book would still crop. A general rule needs
   evidence that the line is a title (style recurrence) rather than a display.
2. **Two-line untagged italic titles** are not recognised (as for #76's bold tier).
