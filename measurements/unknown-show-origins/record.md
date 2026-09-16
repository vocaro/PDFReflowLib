# Text shows whose origin the reader cannot derive (#67)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI.
Baseline: branch tip `b339e39` (after #11 note links, #62 furniture, #50/#64 list items and
#60/#61 notes), Xcode 27.0, macOS 27.0. Both binaries are built from this worktree; the candidate's
SHA-256 is in `lane-summaries/*-result.json`.

Corpus: *The Fed Explained* (`corpus/cache/the-fed-explained.pdf`), with Our Flag, the FAA
handbook, the 9/11 report, Replay Clocks and Wallace's algebra as controls. Every conversion here
was run with `--package-identifier urn:uuid:00000000-0000-4000-8000-000000000001` and
`--modification-date 2026-01-01T00:00:00Z`, so EPUB bytes compare directly.

## Diagnosis

`MarkedTextReader.apply` returned false on 117 of the Fed's 135 pages, so its well-formed tag
tree never reached reconstruction. Page 8's decompressed stream
(`mutool show -b corpus/cache/the-fed-explained.pdf pages/8/Contents`) shows why:

```
BT
/Artifact <</O /Layout >>BDC
/T1_0 1 Tf
8 0 0 8 58.8 750.5121 Tm
(vi)Tj
EMC
/Artifact <<>>BDC
( )Tj              <- no positioning operator; the cursor continues from (vi)
EMC
```

`show()` required a positioning operator before every text-showing operator and treated its
absence as unknown cursor advancement that invalidated the whole page. The running head is an
`/Artifact`, which carries no structure, so it was invalidating tags it does not own.

`census-unknown-origins.py` tokenizes all 135 decompressed page streams and classifies every show
whose origin the reader cannot derive (`operator-census.txt`):

| Mark context | Shows | Cause |
| --- | ---: | --- |
| inside an `/Artifact` | 150 | no positioning operator |
| inside a marked section with an MCID | 536 | no positioning operator |
| outside any marked content | 0 | — |
| leading non-zero `TJ` adjustment | 0 | — |

The 536 marked ones are run-in style changes: a second show continues the first show's cursor
after a font change (page 27: `[(Emplo)15(yment.)]TJ /T1_0 1 Tf [( In the statement,…)]TJ`).
Their origins need glyph widths, which this reader deliberately does not decode. No Fed page shows
text of unknown origin outside marked content, and none fails for a Form XObject, a `Tz`/`TJ` case
or the 256 `Tf` cap.

A second reason rejected the seven chapter openers: the 70-point numeral and the first title line
are one extracted line whose box contains the origin of the title's *second* line, so that show
matched two candidate lines. (Those pages' tags are discarded later anyway; see the defects.)

## Changes

`MarkedTextReader` (`show`, new `unknownOrigin`, `Mark`):

- A show pops its operand and then scopes an unknown origin to what it can affect: nothing inside
  an `/Artifact`; inside a marked section, the group of that section's identifier alone; the whole
  page still for text outside any marked content (the existing unknown-cursor rule). Artifact-ness
  is inherited by nested spans. A leading non-zero `TJ` adjustment is scoped the same way.
- When several extracted lines contain a show's origin, a single candidate whose left edge is that
  origin (within the existing 0.75 tolerance) owns it; any other ambiguity still rejects the group.

`LayoutReconstructor`:

- **Heading levels** (`rankHeadingLevels`). A tagged heading keeps its validated level (#43)
  unless that level is incomparable with the typographic ranking: an untagged heading larger than
  *every* heading the document tags at that level already ranks at that level or deeper. Once a
  level yields, every deeper level yields with it, and yielded headings rank by size on a scale that
  includes exactly the headings ranked on it. The Fed's 16-point `H3` sections yield to the 24-point
  chapter titles whose `H2` never reaches this stage, so the book keeps its contents-page nesting;
  Our Flag tags `H3` from 9 to 21 points, so its untagged 20-point `"The Star-Spangled Banner"` is a
  sibling inside that range and its `H3` levels hold.
- **Paragraph tags in heading type** (`blocks`). A `P` group set entirely in the page's heading
  typography keeps its spatial reading when the next text *in its own column* is ordinary text that
  starts no further left than the group (one body size of slack), because a section title and the
  body it heads share a column edge. The column matters: on FAA page 194 the untagged left column
  interleaves in reading order between `Pressurized Aircraft` and its body. Sources tag real section
  titles as paragraphs (Fed `Contents`, `Advisory Councils`; FAA `History of Flight`). A cover label
  followed by the title (Fed `PUBLIC EDUCATION & OUTREACH`) and a title page's centred imprint (Our
  Flag `JOINT COMMITTEE ON PRINTING`, 61 points right of the line under it) head nothing and stay
  paragraphs.
- `headingTypography`, extracted from `isHeadingCandidate`, matches `sectionLabels` on a
  structure-free copy of each line. `TextLine` equality includes its tag, so dropping a tag used to
  make a line stop matching its own label entry — a latent defect that already affected groups
  `structuredOrder` rejects.
- **Cross-page joins** (`continuation`, #45). Two different validated identities refuse a join only
  when one side's role is not a plain paragraph. Two `P` groups fall through to the geometric rule,
  which already refuses headings, list openers, captions and folios. A side whose role no group
  vouches for keeps #45's refusal, so #45's own synthetic contract is unchanged. The Fed tags each
  page's fragment of six continuing paragraphs as its own `P`, while 22 of its 657 groups do span a
  page, so the identity difference is not evidence of separation there.

`ReflowDocument`: `ReflowBlock.taggedLevel` records the validated role of every tag-built block
(0 for a paragraph, 1–6 for a heading); tagged headings also carry `headingSize`.

No public API or default changed.

## Before/after: The Fed Explained

Of 135 pages, 115 carry a validated tag tree:

| | `b339e39` | this tree |
| --- | ---: | ---: |
| Pages where `MarkedTextReader` rejected a group | 117 | 46 |
| Tagged pages where every group applies | 0 of 115 | 72 of 115 |
| Tag groups rejected, of 597 | 597 | 66 (11.1%) |
| `structureFallback` pages (all stages) | 118 | 57 |
| Cross-page joins | 21 | 21 (same page pairs) |
| Navigation entries | 161 | 164 |

The 46 remaining reader-level pages are the run-in style changes above; 13 pages fall back later in
`structuredOrder` on the existing #43 caption/list/oversized-heading and run-barrier rules.

Navigation (`heading-diffs/fed.txt`): all 161 baseline headings keep their exact level (h1 1, h2 1,
h3 9, h4 28, h5 63; h6 59 → 62). The 7 chapter titles stay h3 and the 28 contents-page sections
stay h4. The three new entries are section titles the spatial rules had run into the paragraph
beneath them, now separated by the tags: page 76 `Supervisory Ratings`, page 97 `How ACH Works`,
page 98 `The Federal Reserve's Role in ACH Development`.

Text and structure (`block-diffs/fed.txt.gz`, reviewed by hand): 262 image files byte-identical
with identical names, 7 tables, 1233 → 1240 blocks. The tags separate fused paragraphs on pages 32,
44, 47, 53, 58 (the #54 sidebar's `General authority during times of crisis.` and `Broad-based
lending only.`, and its box title), 80, 126 and 128 (a figure caption from its body), and repair two
hyphenated words the spatial rules had split *within* a page: `macro-`/`prudential` (page 60) and
`li-`/`quidity` (page 84). The word multiset gains `macroprudential` and `liquidity` and otherwise
does not change. The shaded tables are unchanged.

New contract checks (`corpus/regressions.json`, Fed 108 → 110): `continuedParagraphs` on page 32
(`…broader financial condi` / `tions, and the actions of households and businesses`) and page 91
(`…gave all depository institutions access to` / `the same pricing for the Federal Reserve's
payment services`), both read against the source render with `mutool draw -F txt`. They pass at
`b339e39` and on this tree, and fail on this change before the #45 narrowing (both joins refused),
so they pin the joins the tags must not break.

## Controls

`join-counts.txt` lists each book's baseline and candidate EPUB hashes and joined page pairs.

| Book | EPUB | Joins | Headings | Shared headings at baseline level | Words |
| --- | --- | ---: | ---: | ---: | --- |
| 9/11 report | byte-identical | 245 → 245 | 133 → 133 | 133 / 133 | identical |
| Replay Clocks | byte-identical | 3 → 3 | 24 → 24 | 24 / 24 | identical |
| Wallace algebra | byte-identical | 28 → 28 | 217 → 217 | all | identical |
| FAA handbook | differs | 129 → 129 | 176 → 191 | 172 / 172 | identical |
| Our Flag | differs | 3 → 3 | 36 → 38 | 35 / 35 | identical |

No join is gained or lost in any book, so none of the #45 record's refused joins (folios, captions,
run-in headings, swallowed prose) reopens; #45's synthetic tests pass unchanged.

FAA (`heading-diffs/faa.txt`): 19 genuine section titles the source tags as `P` become headings
(`History of Flight`, `Human Behavior`, `Theories in the Production of Lift`, `Exhaust Systems`,
`Starting System`, `Combustion`, `Electrical System`, `Aircraft Inspections`, `Airworthiness
Directives (ADs)`, `Air Masses`, `Aviation Forecasts`, `Pilotage`, `Lost Procedures`, `Flight
Diversion`, `Health and Physiological Factors Affecting Pilot Performance`, four `Chapter Summary`).
Four entries go: three truncated fragments of two-line titles (`Minimum Equipment Lists (MEL) and`,
`Function Display (MFD) Weather`, `Parallels)`), and page 43's half-title `Single-Pilot Resource
Management`, whose whole title is now one paragraph (see gaps). 9155 → 10430 blocks: tags split run-in
headings and fused paragraphs on 112 pages, including page 194, whose two columns the baseline
interleaved line by line.

Our Flag (`heading-diffs/our-flag.txt`): text identical, 739 → 693 blocks (page 4's statutory text
goes from eight fragments to four correct paragraphs). It gains the Flag Code sections `§174. Time
and occasions for display` (h5), `§175. Position and manner of display` (h5) and `§176. Respect for
the Flag` (h3; the source tags §174 and §175 `H4` but §176 `H3`). Page 3 is identical to the
baseline: its imprint lines stay paragraphs. Page 4's `JOINT COMMITTEE ON PRINTING` stops being an
h4: it is the tail of the same centred imprint (`PRINTED UNDER THE DIRECTION / OF THE / JOINT
COMMITTEE ON PRINTING`), a baseline heading only because the spatial rules split that imprint.

### Our Flag heading levels

An intermediate version of the ranking moved eight Our Flag headings deeper. Seven of them, with
their validated and typographic levels:

| Page | Heading | Size | Tagged | Typographic | Intermediate | Now |
| ---: | --- | ---: | :---: | ---: | ---: | ---: |
| 2 | `“I PLEDGE ALLEGIANCE` | 12 | — | 4 | 5 | 4 |
| 2 | `STATES OF AMERICA AND TO` | 12 | — | 4 | 5 | 4 |
| 2 | `GOD, INDIVISIBLE, WITH LIBERTY` | 12 | — | 4 | 5 | 4 |
| 16 | `Flag Anatomy` | 18 | H3 | 4 | 4 | 3 |
| 17 | `Title 36, Chapter 10—PATRIOTIC CUSTOMS` | 10 | H3 | 5 | 6 | 3 |
| 29 | `How to Obtain a Flag Flown Over the Capitol` | 18 | H3 | 4 | 4 | 3 |
| 31 | `How to Obtain a Burial Flag for a Veteran` | 18 | H3 | 4 | 4 | 3 |

The eighth was page 4's `JOINT COMMITTEE ON PRINTING` (h4 → h5), now not a heading at all. The moves
were not correct consequences of tags applying. The intermediate rule let *any* larger heading at
the same level contradict a validated level, so the 20- and 21-point `H3`s and the untagged 20-point
`"The Star-Spangled Banner"` demoted the 18-, 10- and 9-point `H3`s. Their sizes then joined the
typographic scale and pushed the untagged Pledge lines down a tier. With the final rule no Our Flag
`H1`–`H3` level yields; only `H4` (§174, §175 at 9 points, below the untagged 12-point Pledge lines)
yields and ranks by size. Every shared heading keeps its baseline level.

## Reproducibility (#68)

`repeat-runs.sh` and `concurrent-runs.sh` run one binary repeatedly on one source with identifier
and date pinned (`repeat-runs.txt`). The reported nondeterminism does not reproduce on this machine:
the baseline gives `1748ac37…` with 118 `structureFallback` pages on three consecutive Fed runs and
`7cc7dc2e…`/37 on three Our Flag runs; the candidate gives `8244e44a…`/57 and `4f8bb64b…`/33; three
*concurrent* candidate Fed conversions are byte-identical. Every before/after figure here pairs runs
of two binaries each self-consistent over three runs.

An audit of the tag path found no order-dependent iteration that reaches the output.
`MarkedTextReader`'s dictionaries and sets feed only set unions, per-line assignment and a
`min(by: order)` over unique orders; `StructureTreeReader`'s final filter and `structuredOrder`'s
groupings are order-independent; the new ranking and paragraph-type rules reduce over sets and
maxima. `StructureTreeReader` keys `pages` and `seen` by CoreGraphics object pointers, which differ
between runs but serve only as identities within one live `CGPDFDocument`. The likeliest source of
a reported 67/118 pair is two runs of different binaries, such as a shared `.build/release/pdf-reflow`
rebuilt between them: 67 is what an early build of this change produced and 118 is every baseline
run. That is evidence against the reported cause, not a fix; #68 stays open.

## Verification

- `swift test`: 327 tests pass (321 at `b339e39` plus six new).
- `scripts/check-all.sh --fast`: exit 0 (327 Swift, 166 Python, 6 fixture conversions, 13 policy
  conversions with 22 rejection/cleanup cases).
- `tools/run_corpus_regressions.py --converter <candidate> --epubcheck /opt/homebrew/bin/epubcheck
  --output <dir> --case …` (`lane-summaries/`): Fed 110, 9/11 133, Our Flag 67, FAA 61 and Replay
  Clocks 55 content checks pass, with EPUBCheck, progress and memory gates.
- One early full `swift test` run failed `referenceOmissionKeepsFallbacksAndFreshOCRWarnings` after
  39 seconds, then passed in isolation and on every rerun. That test drives Vision; the flake is
  unrelated to this change and is noted, not diagnosed.

New tests (those marked † were run against the code without their rule and fail there):

- `StructureTests`: a Fed-shaped `/Artifact` running head whose later shows have no positioning
  operator, every group applies †; an unpositioned show inside one tagged paragraph, only that group
  falls back and the heading beside it keeps its role †; a display initial whose tall line box covers
  the next line's origin †, with the negative control where no single candidate starts there; the
  level rule on Fed-, Our Flag- and cover-shaped scales, with hand-derived expectations; a paragraph
  tag in heading type over its body, above a title and as a centred imprint †, plus a right-column
  heading as a positive control (FAA page 194's reading-order interleave is covered by the corpus
  comparison, not reproduced in the synthetic page).
- `PageContinuationTests`: two tagged `P` fragments across a page with a hyphenated wrap join into
  one paragraph (`conditions`) †; the same fragments stay separate
  when the far side is a tagged heading or a list-marker line. #45's
  `oneUntaggedSideKeepsTheHeuristicWhileTwoIdentitiesRefuse` passes unchanged.

## Remaining gaps

- The Fed's seven chapter-opener `H2` titles never reach reconstruction: those pages carry a
  page-sized background photo, and the pipeline's image-backed-text rule clears every line's
  structure. With them, the book's own `H1`/`H2`/`H3` hierarchy could settle navigation directly.
- 46 Fed pages still reject a group because a run-in style change shows text from a cursor the
  reader cannot follow without glyph widths. That is the documented boundary, not a defect.
- FAA page 43's two-line title `Crew Resource Management (CRM) and Single-Pilot Resource Management`
  is one paragraph rather than one heading: its first line is neither heading-size nor a label.
- Our Flag's §176 ranks h3 beside its chapter while §174 and §175 rank h5, following the source's
  own inconsistent `H3`/`H4` tags.
- Our Flag page 4 splits `ROBERT W. NEY, … Senator from Georgia,` from `Chairman Vice Chairman`
  where the baseline kept them as one line group; text is unchanged.
