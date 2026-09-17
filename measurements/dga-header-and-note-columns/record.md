# Text on a band across a photograph, and notes in columns (#141)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27.0, release CLI. Diagnosis and the
first surveys ran on `ec22aff`; the patch was carried to `9ec0608` (#143, #147, two new corpus documents) and `f8a0a7a`
(#156, generated doc counts, tools only) by fast-forwarding and reapplying it (it applied cleanly). Every measurement
below except the diagnosis was rerun against `9ec0608`/`f8a0a7a`.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `9ec0608` (Sources identical at `f8a0a7a`) | `5bd04f24…` |
| candidate | `f8a0a7a` plus this change | `a8948ba0…` |

Corpus: `dga-2025-2030` (`c34f1bec…`), page 2; controls every other English document in the manifest. No PDF or EPUB
is committed. Tools in [`tools/`](tools/) ran from a scratch directory; paths inside them are those of the run. The
Swift tools compile the library sources (minus `EPUBWriter` and `PDFConverter`) with the tool (`tools/build.sh`).

## Diagnosis

**Defect 1, the header.** DGA page 2 paints the header photograph as two images (`[0 755 612 792]`,
`[0 702 612 792]`), a dark filled tab `[0 700 317 740]` holding the 18-pt `Message from the Secretaries`
(`[55 708 271.5 731.9]`), and a light filled rectangle band `[0 671.8 612 716.3]` holding the 12-pt welcome line
(`[54 679.2 344 695.1]`). #117's `withoutTitleBackdrops` already drops the tab as title art (the title lies inside
it). The band holds one line, so it is no tint (three prose lines are needed), and it overlaps the photograph, so the
two images and the band cluster into one seed `[0 671.8 612 792]`. Whole-line expansion then admits both lines, since
the seed captures them; no rule separated text set on a band from the picture it overlaps. Paint order is not in the
page model, so the evidence has to be shape: the lines sit on filled paints of their own that span the crop, at its
edge, with nothing but image beyond them.

**Defect 2, the notes.** The four notes are untagged 6-pt lines (`1 \u{07}https://…`: PDFKit reports a control
character after each raised marker), two per column: notes 1 and 2 at x 54, notes 3 and 4 at x 315, rows 2.5 pt apart,
4 pt below the rule under the signatures and 3.5 pt above the footer band. The rest of the page is tagged and ordered
by its tags. Tracing `LayoutReconstructor.ordered` (a temporary print) showed that no whitespace cut exists on the whole
page: every vertical gap is under 1.1 body and no gutter runs the page's height, so the 46 elements fall through to
`sortedByRows`, which reads the notes by row, 1, 3, 2, 4. `FootnoteDetector` does not take them (no dash separator; the
unruled form requires one left edge). `rowMajorLabels` (#78) reorders only `N)` labels in three or more columns.

Once the notes are reordered, a second defect shows: notes 1 and 2 share a left edge 2.5 pt apart, so the
paragraph rule joined them into one paragraph (and 3 and 4 likewise). The row order had hidden it.

## Change

No public API, option, default or warning code changed.

- **`TintDetector.withoutEdgeBands`**, applied by `compose` to the clustered seeds (the tint composition is unchanged,
  now `composeTints`). For a seed holding an image, when every line it meets reads as a title (1.25 body, a word of
  three letters) or prose (four words), each line's midpoint lies on a filled paint (taken from the page's paints before
  title-backdrop removal), those backdrops together span 90% of the seed's width, and the backdrops with the lines form
  a strip reaching the seed's lower or upper edge, the part beyond the strip must be at least a third of the seed's
  height and 90% covered by images. The seed becomes the images' part of that remainder. The remainder is measured
  before it becomes a rectangle (a strip past both edges, a box around a figure, leaves none). Cost: a page whose seeds
  times its images, lines and filled paints exceed `seedClusterWorkLimit` (2,000,000) keeps its seeds.
- **`LayoutReconstructor.noteColumnsInNumberOrder`**, applied to the result of `sortedByRows` at the end of `ordered`
  only. A contiguous run of the sorted elements that opens with a raised-number line (`raisedNoteNumber`: the first run
  is superscript, one to three digits once whitespace and control characters are trimmed, text follows) and holds only
  lines under 0.9 body, whose markers stand on at least two left edges more than 1.5 body apart, with every line at or
  right of an edge, column extents that do not overlap, at least three markers, and the numbers counting up by one down
  each column and on from column to column, reads column by column. A note continued at the head of the next column
  reads after it.
- **Paragraph break**: in `blocks`, a line opening with a raised number starts a new paragraph when the open paragraph
  opened with one.
- DGA page 2's crop keeps the photograph above the tab (`[0 740.5 612 792]`): the 38 pt of photograph beside the tab
  (x 317–612, y 702–740) are not in the EPUB, rather than a crop showing a sliver of the tab. A rectangle cannot hold
  both.
- Tests: `EdgeBandsAndNoteColumnsTests.swift` (8 tests) on #117's pinned DGA page 2 fixture (`dga-2-illustrated`) and
  synthetic pages. Docs: `doc/architecture.md` (both rules); counts regenerated with `tools/update_doc_counts.py`.

### Designs considered and rejected

- **Crop at the lines only** (`[0 732.4 612 792]`): keeps 8 pt more of the photograph but ends it with a strip of the
  dark tab under the photo's lower-left edge. Rejected on the render.
- **The whole photograph with the title reflowed too**: layout removes every line a crop intersects, so this needs a
  change to line ownership outside graphics and crop decisions, and would show the title twice.
- **Treating the band as a one-line tint**: the tab is already gone; a one-line tint rule would reach every shaded
  table header and legend box in the corpus, while the photo-edge evidence is specific.
- Guards found redundant by mutation and removed before the final run: text in the remainder (every held line is in the
  strip), `!image` on backdrops (images are never `filled`), backdrop containment and thinness, the run's image/table/box
  checks (those elements have no line), and "each column opens with a marker" (it wrongly refused a note continued at a
  column head). The first two guards of `withoutEdgeBands` (no image, no line) and `edges.count >= 2` are early exits
  whose mutation is equivalent.

## Survey: every crop holding an image and text, English corpus

`tools/cropsurvey.swift` (both builds) lists, for every page of the 17 English documents (Arabic USCIS and Chinese IRS
excluded), each composed crop from `graphicsWithLabels` and the lines it takes, then `tools/surveydiff.py` diffs the
builds. Pages with unsupported drawing are skipped; the pipeline's page-sized clearing is not applied, so the survey is
a superset.

| Document | Pages | Crops that change |
| --- | --- | --- |
| DGA | 10 | page 2 only: `[0 671.8 612 792]` (title, welcome line) → `[0 740.5 612 792]` (no lines) |
| FAA, Wallace, 9/11, Warren, Fed, NOAA, Our Flag, Blue Book, CDC, NBS, arXiv, USGS, Loper Bright, Census, US Courts form, NTRS | 1–1,834 each | none |

So DGA page 2's header is the only place in the English corpus where text leaves an image's crop.
`tools/edgesurvey.swift` lists every composed crop that holds an image and text, with the first condition of the rule it
fails ([`survey/`](survey/), one file per document):

| Document | Crops | First failing condition |
| --- | --- | --- |
| NOAA | 79 | 54 labels (map and chart labels, axis names); 16 no backdrop (front matter and contents set over photographs, pages 4–75; chart titles on their art, pages 351, 947, 1778); 9 no remainder (figure titles on the tint of a box around the figure: pages 223, 354, 701, 1189, 1190, 1433, 1448, 1503, 1767) |
| 9/11 | 10 | labels (maps, the organization charts) |
| arXiv | 8 | labels (plot tick and axis text) |
| FAA | 8 | 2 labels; 2 no backdrop (Figure 1-14 and 14-60 captions on their art); page 455 backdrop narrower than the art; pages 453, 454, 456 remainder not an image (performance charts are vector) |
| DGA | 6 | the running foot on the footer band of pages 2 and 6–9 (the strip is the whole band, so nothing lies beyond it); page 10's foot with `January 2026` (labels) |
| Fed | 3 | 1 labels; pages 126 and 132 no backdrop (a box's last prose line touching the screenshot beneath it; see Remaining gaps) |
| Wallace | 3 | 2 labels; page 121 no backdrop (a graph's annotation) |
| Our Flag, CDC, Blue Book, Warren, NBS, USGS, Loper Bright, Census, US Courts, NTRS | 0 | — (image-backed pages are cleared before crops; the others hold no text over images) |

Chart labels, map labels and FAA illustration callouts all stop at the first two conditions. Renders reviewed at 50–80 dpi:
DGA page 2 (before, after and both header crops), NOAA pages 701 and 1189 (boxed photographs with their titles, unchanged),
Fed page 68.

## Before and after (`9ec0608` → candidate)

**Byte identity** (`tools/pair.sh`: both builds, `--ocr never`, pinned identifier and date; `tools/epubdiff.py` on a
difference): Census, Loper Bright, USGS, arXiv, NBS, Our Flag, CDC, US Courts, NTRS, Wallace, 9/11, FAA and Blue Book
are byte-identical. DGA changes page 2 only; Fed changes page 68 only. Warren and NOAA exceed the default image-output
ceiling (#5), so `tools/blocksurvey.swift` compared every page's reconstructed blocks instead (tags, hidden-text
filter, composition, crops and `blocks`; no furniture removal or cross-page joins): NOAA none of 1,834 pages; Warren
pages 291 and 384 differ, but repeated runs of the baseline alone flip them too (a scanned page read here without the
pipeline's synthetic-style flag), so neither is this change.

| Page | Before | After |
| --- | --- | --- |
| DGA 2 | header crop holding the title and welcome line; notes `1, 3, 2, 4` | photograph crop above the tab; `h4` `Message from the Secretaries`, `p` `Welcome to the <em>Dietary Guidelines for Americans, 2025–2030.</em>`; notes `1, 2, 3, 4`, one paragraph each |
| Fed 68 | Figure 5.2's notes 1 and 2 in one paragraph | two paragraphs (source: two notes on consecutive lines) |

**Lanes** (`tools/lane.sh <case> base|cand`: `run_corpus_regressions.py` with EPUBCheck, the environment probe and the
memory gate, one case per call; `tools/cmp.sh`: `compare_conversion_runs.py --allow-different-converters`). Condensed
results are in [lane/](lane/); EPUBs were deleted after each comparison.

| Case | Contract (base → cand) | Changed pages | Images | Warnings | Peak RSS (base → cand, limit) |
| --- | --- | --- | --- | --- | --- |
| dga-2025-2030 | 89 checks: base fails 6 (exactly new checks), cand passes | 2 (id-only shifts 3–10) | `image-4` (the header crop) | identical | 98 → 101 MB (192) |
| fed-explained-2021 | 177: base fails 1 (the new check), cand passes | 68 (id-only shifts after) | none | identical | 262 → 294 MB (768) |
| faa-phak-8083-25c | both pass 502 | none | none | identical | 855 → 710 MB (1,280) |
| cdc-zombie-pandemic-2011 | both pass 33 | none | none | identical | 382 → 382 MB (512) |
| usgs-mcs2025-copper | both pass 50 | none | none | identical | 33 → 33 MB (128) |
| gpo-our-flag-2003 | both pass 104 | none | none | identical | 101 → 103 MB (192) |

RSS differences are run-to-run spread on this machine (the FAA and Fed EPUBs are otherwise identical or differ by one
paragraph). NOAA is excluded from the lanes (#5); its survey and block comparison above cover it.

## Tests and contracts

- `swift test`: 707 pass (699 plus 8). `scripts/check-all.sh --fast`: exit 0, including the generated doc counts.
- `EdgeBandsAndNoteColumnsTests.swift`: DGA page 2's crops, heading, welcome paragraph and reading order from the pinned
  fixture, with a negative control (without the tab and band the photograph's crop takes the title); its notes in number
  order, with the row sort's `1, 3, 2, 4` as the negative control; synthetic positive cases (lower and upper edge, a
  photograph narrower than its band); controls for a label, a caption on the photograph beside the tab, callout boxes
  narrower than the art, a stroked outline, a band across the middle, vector art with or without a small image, a boxed
  figure, too little art; note columns with a continuation and a note continued at a column head; controls for row
  numbering, a gap in the numbers, two notes, body-size lines, plain numbers, a line left of every column and
  overlapping columns; paragraph breaks at raised numbers with a continuation control and a raised reference inside
  prose; and the work limit, timed on `withoutEdgeBands` alone.
- Mutations ([mutants.log](mutants.log), `tools/mutate.py`): 21 of 21 single-guard mutations fail at least one test.
- Contract (`tools/addcontract.py`): DGA page 2 gains the heading, the welcome paragraph, ordered text from the title
  through the four note addresses, and three distinct-paragraph checks (welcome line / first body paragraph, notes 1/2,
  notes 3/4); Fed page 68 gains notes 1 and 2 as distinct paragraphs. 12 checks, one new page. The baseline fails
  exactly 7 of them (DGA 6, Fed 1); the distinct-note checks on DGA pass on the baseline, whose row order kept the
  joined lines apart, and guard the paragraph break (its mutation fails `dgaPage2FootnotesReadDownTheirColumns`).

## Cost

`#117`'s bounds are unchanged (`titleBackdropCandidateLimit`, `seedClusterWorkLimit` in `seedClusters`), and the new
rule is bounded by the same work limit. Composition per page (`tools/composetime.swift`, release, best of five, base →
candidate): FAA 448 (10,000 paints) 9.4 → 9.4 ms; FAA 226 5.4 → 5.4 ms; FAA 67 1.1 → 1.1 ms; FAA 288 3.3 → 3.2 ms;
NOAA 1834 (10,000 paints) 80.6 → 80.8 ms; DGA 2 0.2 → 0.2 ms. The note rule runs only on the row-sort fallback and is
linear in the run with one sort per column. Lane conversion times: DGA 0.7 s both, FAA 118 → 110 s, CDC 28 → 24 s (load
spread).

## Remaining gaps

- The header photograph loses the 38 pt beside the tab (see Change).
- The note markers still carry PDFKit's control character (`1 \u{07}`); it is dropped in the EPUB text, but it kept
  `FootnoteDetector.noteMarker` from reading them, and the notes remain paragraphs rather than footnote blocks linked from
  their references (two columns are outside the unruled form in any case).
- `tools/blocksurvey.swift` reads Warren pages 291 and 384 differently from run to run on the same binary when the
  synthetic-style flag is not set; the pipeline sets it on those pages, and the corpus repeat-run check does not cover
  Warren. Not investigated.
- Fed pages 126 and 132 (not changed here): the last prose line of Box 7.2 (`with the Federal Reserve.`) and of the
  box on page 132 (`other tools to achieve this goal.`) touch the screenshot set beneath them and are taken into its
  crop, so they are missing from the text on both builds.
