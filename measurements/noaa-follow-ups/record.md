# NOAA follow-ups: spaced entries, verse, figure leads, credits and backdrops (#200)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs, host
terminal. Date 2026-09-18. Work done on `07c1bbd` (the coordination tip); every measurement is on that
base.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `07c1bbd` | `0adc94637ea0ed7d46c6f193899877bb2d1eff2e199673aba86387150cb5b4e9` |
| candidate | `07c1bbd` plus this change | `8c8a33fdeec99a9da62552aba1f883e6a2124a4bb22cac3852aeeec7b86bfd05` |

Every lane below ran on the final candidate. No PDF, EPUB or raster is committed. Fixtures `noaa-5`,
`noaa-6`, `noaa-47`, `noaa-57`, `noaa-69`, `noaa-488`, `noaa-1182`, `noaa-1183` and `noaa-1738` were
captured with `tools/capture-layout-fixture.swift` on the base reader (text and geometry only). Scripts
used are in [`tools/`](tools/); paths inside them are those of the run.

## What the issue listed, on the base

`07c1bbd` already reads pages 343, 568 and 610 one entry per paragraph; page 27's table has its header
row (the word drop #181 saw was the running foot); page 77 lost only its running foot. Still wrong:

| Page | Base output |
| --- | --- |
| 488 | `Charles S. Colgan, …, Center for the Blue Economy Sarah R. Cooley, Ocean Conservancy` one paragraph |
| 1738 | `Samantha Basile, … / ICF Allyza Lustig, … / ICF` one paragraph |
| 5 | couplets 3–9 of the poem joined into two-line paragraphs |
| 6 | `Rebecca S. Dodder, … (from January` / `2023)`, and two more wrapped entries, split; `Federal Steering Committee for the Fifth National Climate` / `Assessment` split |
| 48 (and 177 more) | a figure's bold one-line lead and its caption one paragraph |
| 69 | a crop from the photo credit's underline took both columns' lower paragraphs (393 → 155 words) |
| 47 | the right column's last two lines in the painting's crop |
| 25 | shaded tables half cropped (rows in fills) — not changed here |

## Rules

**Spaced entries** (`LayoutReconstructor.spacedEntryEdges`, `evenRuns`, `edgeWraps`,
`HangingEdge.openings`, `opensHangingEntry`).

- A line of an even run (three or more lines, #181) now opens its entry by run membership, not by
  #134's ends-early test. The ends-early test measures against the edge's widest line, which on page
  488 (the citation aside) is Colgan's entry itself: `Sarah` would not have fitted after it.
- An edge's widest line fills its measure only where three lines reach that measure, as the wrap
  already asked. A lone widest line (page 343's LeDuc entry, with no citation on the page) no longer
  ends the run it belongs to.
- **Book spacings** (`spacingEvidence`, `bookSpacings(from:wraps:)`, `spacedEntryPairs`): each page
  records the gaps of its runs of three; the book keeps a gap seen on at least three pages (within a
  tenth of a size) that stands at least a fifth of a size over the book's wrap. NOAA at 10 pt: wrap
  0.15, spacings 2.23, 3.23, 4.65, 7.73 (71 pages of evidence); Wallace at 12 pt: 5.42, 9.74. Two
  lines on an edge at one of them, the upper not filling the measure, are two entries (page 1738's
  authors, 7.7 pt apart as page 1700's contributors). The pair qualifies no edge: an earlier draft let
  a pair make the whole edge a spaced edge, and page 6's committee title, 3.0 pt over its first entry,
  then held every entry of the column to that spacing.

**Verse** (`hangingWraps`, used by `continuesOpening`). A pair on an edge — a line and a line hanging
beneath it — is *full* when the hanging line's first word would not have fitted after the upper
line, short of the widest such upper line. Entries wrap because they are full; verse breaks where the
verse does. Page 5 has ten couplets, seven full and three short (`It is a forgotten pleasure, the
pleasure` / `of …`). A hanging line runs on only where at least two pairs are full and at most one in
four is short, both on #181's hanging-entry path (which asked for three first lines within a size of
the widest) and on #147's spaced hanging-indent path (reading lists), which is what joined the poem's
couplets on the base. Page 6 wraps two entries a column whose first lines end 19 pt apart, so #181's
three-line measure refused them; both are full.

**Wrapped titles over entries** (`opensHangingEntry`). Two lines of one size other than the edge's
entries' are none of its entries: page 6's 11-point committee title wrapped over its 10-point entries
no longer splits by the ends-early test (its measure was the running foot `Fifth National Climate
Assessment v`, kept on this page and spanning both columns). An 11-point title over a 10-point
sub-title (`… Coordination Office` / `NCA Leadership`) still splits. A draft that dropped the foot from
the measure was reverted: page 6's left column has one wrapped-entry pair (`J. Michael Kuperberg`
reads as a lettered list line), and the foot is what splits its widest entry from the next.

**Bold caption labels** (`opensBoldCaption`). A line whose first run is a bold `Figure N`/`Table N`
label opens a paragraph after a line ending a sentence, on the same edge in the same type, unless
the open paragraph is itself a caption. NOAA sets each figure's bold one-line lead directly over its
caption at ordinary leading; 178 pages split the lead from the caption.

**Captions broken overleaf** (`continuation`). A cross-page join steps over a caption at the page's
foot, since body text runs on past figures. A caption that ends at a line-end hyphen is left
open, so it is the text that continues: page 1182's Figure 25.8 caption ends `…with cropland prev-`
over page 1183's `alent in the eastern portion`. On the base that caption ran on only because the
figure's lead opened its paragraph; once the lead stood apart it split at the page. The rule also
joins page 453's Figure 9.3 caption (`re-` / `gardless`), split on the base.

**Underlined sub-headers** (`TableRegionDetector.underlinedColumnRegions`). A single underlined piece
heads a table column only where its column's next row stands within the block's leading beneath it.
USGS's `12–31–24` (tariff rows 11 pt below) and Wallace page 148's `+ 15 + 15` (`2x = 2` 14.4 pt below)
pass; NOAA page 69's `Tami Phelps`, a link under a painting, has the other column's prose beside it
and its own column 38 pt down. A first draft asked only that the row directly beneath reach under the
piece; it refused Wallace page 148's step table, whose next row is the left column's step label, and
split that table's crop, so it was replaced.

**Backdrops behind a picture** (`TintDetector.withoutTextBackdrops`). An image whose text block runs on
past it keeps what lies beyond the block (#158); where at least half of that lies under another
picture, it is the page's backdrop and keeps nothing. Page 47's corner art keeps a piece below the
left column that the painting covers 55% of; merged with the painting's crop it took the right
column's last two lines. Page 57's corner art keeps a piece above its column that a photograph covers
20% of, and keeps it (at any threshold under a fifth, page 57 leaves the page-image path and its
two-line panel becomes a crop).

### Designs measured and rejected

- **Stroke width in `GraphicsReader`** for page 40: its box title is one 20-pt stroked line, read as a
  thin rule through the title. Padding a wide stroke by its half width made it title art, but the
  pale tab strip above it still captures the title within its two-point padding, and the change moves
  every thick stroke in the corpus. Reverted; follow-up below.

## Before and after (`07c1bbd` → candidate)

`tools/run_corpus_regressions.py`, one case per call, both binaries, every English case except Warren
(#5). Output compared with `tools/pagediff.py` / `tools/classify.py` (block text per page; pure
splits/joins told apart from text changes) and `tools/imgdiff.py` (image bytes per page). Each case's
EPUBs deleted after review. 65–75 GB free throughout; load average 20–52 from other agents.

| Case | Contract | Pages changed |
| --- | --- | --- |
| noaa-nca5-2023 | base fails 14 of the 18 new checks, cand passes 60 | 197 (below) |
| wallace-algebra-2010 | both pass | 11 splits, 1 split across a page marker (119) |
| faa-phak-8083-25c | both pass | 55 (split) |
| usda-ars-agresearch-2012-11 | both pass | 22 (split) |
| the other 16 | both pass | none |

- **NOAA**: 178 pages split a figure's bold lead from its caption; 5 keeps its verse lines; 6 and 7
  join wrapped entries (7's label `UNC Asheville's National Environmental Modeling and Analysis` /
  `Center` now one paragraph); 34, 488, 1487, 1738 split fused author pairs; 14 (contents), 351, 701,
  1801, 1806, 1809 (glossary entries) split at spaced paragraph breaks, each read against the page;
  47 and 69 regain 18 and 238 words; 66 leaves the page-image path (the corner-art rule) with its
  text unchanged; 453/454 and 1182/1183 carry their captions across the page. Book text 724,484 →
  725,017 words. Image bytes change on pages 40, 47, 66 and 69 only.
- **Page 40 is worse in one respect**: the photo credit's false table no longer sends the page down
  #117's page-image path, so its box now reflows as crops read it — the box title, on the 20-pt stroke
  above, is inside a crop (text 374 → 371 words; the title reads only in the image), and the box's
  bullet panels read as a two-column table. Its source-page image is gone. On the base the page's
  fallback reflowed everything as text beside that image: `<h6>Box 1.1. Mitigation, Adaptation, and
  Resilience</h6>` and the three bullets as `<ul><li>`. So the title's eight words are no longer text
  a screen reader reaches (its crop's alt text is `Illustration`); the bullets' text is still there,
  as table cells, with their wrapped lines in separate rows. Follow-up below.
- **Wallace** (book spacings 5.42 and 9.74): worked-example annotations split one note per step
  (49, 75, 120, 135, 160, 163, 168, 171), and 119, 240, 299 split at real paragraph breaks (6.2–6.5 pt
  gaps against a 2.7 pt wrap), all read against the source geometry. **FAA 55** splits the T-E-A-M
  items; **magazine 22** splits two index entries.

## Tests and contracts

- `swift test`: 1013 pass (eleven new tests in `NOAAFollowUpsTests.swift`; `RuleAdjacentProseTests`'s
  synthetic tariff rows now reach under their sub-header, as the copper page's do, with a control for
  rows that do not). `python3 -m unittest discover -s tools -p 'test_*.py'`: 248 pass.
  `tools/update_doc_counts.py --check`: clean.
- Mutations ([mutants.log](mutants.log), `tools/mutate.py`): 13 of 13 single-guard mutations fail a
  test; the backdrop threshold survived a first pass and the page-57 control was added.
- Contract (`corpus/regressions.json`, noaa-nca5-2023): new pages 5 (three couplets distinct), 6
  (three wrapped entries and the wrapped title whole; title and sub-title, and two entries, distinct),
  47 and 69 (the recovered passages), 488 and 1738 (the fused pairs distinct), 453 and 1182 (the
  caption continues overleaf; 1182's lead reads whole); page 48 gains the lead and caption as distinct
  paragraphs. The review file lists the new pages.

## Cost

Per page, `spacingEvidence` and `spacedEntryPairs` each read `edgeWraps` once more, and `hangingWraps`
pairs the page's lines once per edge (memoized). Alternating base and candidate under the same load:
NOAA 156.8 / 158.4 s user, Wallace 37.3 / 36.0 s.

## Remaining gaps and follow-ups

1. **Page 40's box title** (`GraphicsReader` ignores stroke width: a 20-pt stroked band is a thin rule
   through its title) and **its bullet panels read as a table**; with the false credit table gone,
   the page no longer falls back to its page image.
2. **Page 25's shaded tables** (rows in fills the table reader does not read; region crops with
   "Mathematical expression" alt text), #150's area.
3. **Page 1738's `Cover Art` / `Diane Burko`**: both lines are wholly bold, so neither is evidence on
   the edge, and they stay one paragraph (page 488's pair splits through its three-run edge).
4. **Page 6's `J. Michael Kuperberg` lines** are preformatted: `J.` reads as a lettered list marker
   (#194's list pass).
