# Hanging-indent entries and the titles over them (#134)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Work started on `ce2cf5b` and the tree was merged up to `9ec0608` (#147) before the lanes recorded
here. The baseline is the #138 candidate (`git archive 9ec0608` with #138's `NativeTextReader.swift`
hunks), so the comparison shows this change alone; the candidate is this tree:

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `9ec0608` + #138 | `8a05cf38230810040536d50562dfa35c9e4bea6e69b06812696208ed4c9d22a9` |
| candidate | this tree on `9ec0608` | `44349b3350ff8b6403e15a311f25994a87a138cd10320262775823b1f43799fc` |
| probe | `tools/probe-raster-environment.swift` | `811ff4532a8e17a7baff435d07ac30f92d0fbdf5e3ac768b3ea11f79f67854dd` |

No source PDF or EPUB is committed; each lane's EPUBs were deleted after its page diff. Three source
fixtures were added (`911-458`, `911-460`, `911-462`, captured with `tools/capture-layout-fixture.swift`
at `4fc3115`); no fixture was recaptured.

## Evidence

9/11 pages 457–465 (Appendix C, Commission Hearings; 110-DPI renders of 458 and 462) list each
hearing's panels: a 9-point bold panel title, then its witnesses, one to an entry, flush left at the
title's edge. An entry that does not fit wraps one em (8.8–9 points) into a hanging indent (`Ken Holden,
Commissioner, NewYork City Department of` / `Design and Construction`), and so does a title (`Law
Enforcement, Domestic Intelligence, and` / `Homeland Security`; `State of the System: Civil Aviation
Security` / `on September 11`). Entries and titles are set at ordinary leading; the space above a
title is about 5 points.

The baseline read each panel's witnesses as one paragraph (nothing sets one entry's first line apart
from the previous entry), and missed three kinds of title:

- a two-line title: #102's pair rule needs the second line on the first line's edge;
- a single-line title over entries narrower than itself (`Intelligence Oversight and the Joint
  Inquiry` over `Senator Bob Graham (D-Fla.)`): #76 asks for a paragraph opening beneath, wider than
  the title;
- either kind then also joined the witness paragraph.

Page 458 before: `<p><strong>Law Enforcement, Domestic Intelligence, and</strong> <strong>Homeland
Security</strong> Michael Wermuth, RAND Corporation Steven Brill, Author, …</p>`.

The report's transcripts (pages 38–61) set each speaker's turn the same way: the bold label on the
transcript's edge, the turn's wrapped lines one em in. #125's lead-in rule (`opensSection`) split some
turns, but others still ran together (page 60: `… Copy that? Controllers: Copy that, sir.`).

## Rule

`LayoutReconstructor.HangingEdge` / `hangingEntryEdges`: a pair is a line on an edge and the line
directly beneath it at ordinary leading, in its size, 0.5–2.5 ems further in and not centred under it
(the two insets differ by more than half an em). The pair is a wrapped entry when the upper line ends
no sentence (`.`, `!`, `?`, `:` or `;` past closing quotes and note markers), otherwise a paragraph
opening on a first-line indent. An edge qualifies when it has at least one wrapped-entry pair and no
opening. Not evidence: a wholly bold upper line (a title, so a two-line title cannot qualify its own
page), lines outside the page's body size (a numbered heading hung under its number is #83's), a list
line, code, a leader entry (an index's sub-entries, FAA page 521) and an upper line without letters (the
Supreme Court's footnote rule over an indented `*Together with …`).

In `blocks`, on a qualified edge (`opensHangingEntry`), a line on the edge opens a new paragraph after
the open paragraph's last line when

- that last line hangs in the indent and is not the paragraph's first line, the paragraph having
  opened on the edge or in the indent (an entry continued from the previous page, page 462); a
  paragraph whose indented first line is the only line so far continues (Loper Bright page 8); or
- that last line is on the edge and ended early: the new line's first word, estimated from its width,
  and half an em fit before the edge's widest line ends, or, where two or more entries wrap on the edge,
  the last line ends at least an em short of the widest line.

A line opening in lowercase, after a line-end hyphen or slash, or holding a leader never opens an
entry, and an entry opens with a word.

In `sectionLabels`, on a qualified edge in the book's recurring label style, a single-line bold title
may head entries on its own edge (neither bold nor a list) instead of a wider paragraph, and a
two-line title's second line may hang in the indent (`stacksUnderHeading(hangingIndent:)`); the paired
lines join into one heading in `blocks` (`continuesHangingTitle`).

## Contracts (`corpus/regressions.json`, gpo-911-2004)

- Page 41: the wrapped `Boston Center: . . . as far as the tape, …` turn is one paragraph; `Planes, as
  in plural.` and `It sounds like, …`, `There’s another aircraft?` and `A second one just hit the Trade
  Center.` are distinct paragraphs.
- Page 458: headings `Law Enforcement, Domestic Intelligence, and Homeland Security`, `Intelligence
  Oversight and the Joint Inquiry`, `State of the System: Civil Aviation Security on September 11` and
  (control) `Congressional Oversight`; paragraph `Ken Holden, … Department of Design and Construction`;
  distinct paragraphs for four adjacent witness pairs (one across a title, a control).
- Page 462: paragraphs `Management Department, …, Central Intelligence Agency` (the entry continued
  from page 461) and `Edmond L. Soliday, … and Security, United Airlines` (a wrapped entry); distinct
  paragraphs `Management Department …` / `Donna A. Bucella …` and `Andrew P. Studdert …` / `Gerard J.
  Arpey …`; heading `Aviation Security on 9/11: The Airlines` (control).

The baseline fails exactly 9 of the 17 new checks (3 headings and 6 distinct-paragraph pairs); the
candidate passes.

## Tests (`Tests/PDFReflowLibTests/HangingEntryTests.swift`)

| Test | Reproducer / control |
| --- | --- |
| `source911HearingPanelsHeadTheirWitnessesOneToAnEntry` | `911-458` with the label style its three appendix fixtures establish: the four titles are headings, seven witnesses (a wrapped one, one after a two-line title, one after a single-line title) are paragraphs of their own, no title text in a paragraph. |
| `source911EntryContinuedFromThePreviousPageEndsBeforeTheNextEntry` | `911-462`: the indented continuation from page 461 ends before `Donna A. Bucella`; a wrapped entry stays whole. |
| `hangingEdgesNeedAWrappedEntryAndNoIndentedParagraphOpening` | Synthetic evidence: a wrapped entry qualifies (with and without a body size); an opening under a sentence end or a colon, alone or beside an entry, disqualifies; lines above the body size, a rule over an indented note, index sub-entries, a centred second line, a 3.3-em step and a list line are no evidence. |
| `entriesSplitOnlyOnAHangingEdgeAndNeverInsideJustifiedOrIndentedProse` | Synthetic: entries split beside a wrapped entry; without one they run together as before; lines filling the measure, a lowercase opening and a line-end hyphen continue; a paragraph's indented first line is no continuation. |
| `hangingTitlesNeedTheirPagesHangingEdge` | Synthetic: a two-line hanging title and a single-line title over narrower entries are headings beside a wrapped entry; without one neither is. |

`FontWeightDetectionTests.source911TranscriptSpeakerLabelsOpenTheirOwnParagraphs` keeps its bold
negative control: without resource weights it now first sets the turns' wrapped lines flush, since the
hanging indent alone sets turns apart.

Negative controls (`tools/mutate.py`, `negative-mutations.txt`), over the hanging-entry, box-title and
two-line subhead, font-weight and FAA heading suites:

| Mutation | Failing tests |
| --- | --- |
| no entry splits | the four hanging-entry tests other than the evidence test |
| a continuation after any first line | `entriesSplitOnlyOnAHangingEdgeAndNeverInsideJustifiedOrIndentedProse` |
| no titles over entries | `hangingTitlesNeedTheirPagesHangingEdge`, `source911HearingPanelsHeadTheirWitnessesOneToAnEntry` |
| no hanging titles | `hangingTitlesNeedTheirPagesHangingEdge`, `source911HearingPanelsHeadTheirWitnessesOneToAnEntry` |
| openings ignored | `hangingEdgesNeedAWrappedEntryAndNoIndentedParagraphOpening`, `source911SemiboldSubheadStandsApartFromItsParagraph` |

## Corpus lanes

`tools/case.py` (as #138's), one case per call; `tools/pagediff.py` diffs each changed page's
markup, one block per line (`pagediff-<case>.txt`). 31–40 GB free.

| Case | Baseline | Candidate | Changed pages |
| --- | --- | --- | --- |
| gpo-911-2004 | fails the 9 new checks | pass | 16: transcripts 38, 40, 41, 44, 48, 60, 61; Table of Names 456; hearings 458–465 |
| ntrs-20200002975-gwl-2020 | pass | pass | 13: `Peak bending moment due to lift, research model` and `Maximum resultant bending moment, research` / `model`, two bullets (unmapped private-use markers) whose second wraps into the indent, become two paragraphs |
| arxiv-replay-clocks-2023 | pass | pass | 3: `Requirement 1.`, `2.` and `3.`, each a bold label with its text wrapped into a hanging indent, become three paragraphs |
| faa-phak-8083-25c, wallace-algebra-2010, fed-explained-2021, dga-2025-2030, gpo-our-flag-2003, cdc-zombie-pandemic-2011, cia-blue-book-14-1955, usgs-mcs2025-copper, scotus-loper-bright-2024, census-rrs2002-01, nbs-jres-geltman-1977, uscourts-pro-se-1-2016 | pass | pass | none |

No text, image, report field or warning changed; 9/11 navigation gains the 9 new titles (458: 3,
460: 5, 463: 1). Every 9/11 hunk was read (`pagediff-gpo-911-2004.txt`): those on pages 41, 456, 458
and 462 against 110-DPI renders, 459 and 464 against PDFKit's line geometry, and the other transcript
pages' splits each fall before a bold speaker label:

| Page | Blocks removed / added | New headings |
| --- | --- | --- |
| 38 | 2 / 4 | 0 |
| 40 | 1 / 3 | 0 |
| 41 | 2 / 8 | 0 |
| 44 | 2 / 5 | 0 |
| 48 | 1 / 4 | 0 |
| 60 | 3 / 7 | 0 |
| 61 | 2 / 5 | 0 |
| 456 | 3 / 8 | 0 |
| 458 | 8 / 32 | 3 |
| 459 | 7 / 23 | 0 |
| 460 | 8 / 24 | 5 |
| 461 | 8 / 23 | 0 |
| 462 | 7 / 19 | 0 |
| 463 | 6 / 17 | 1 |
| 464 | 5 / 25 | 0 |
| 465 | 2 / 7 | 0 |

Every split is at a source entry or turn boundary, and no wrapped entry or turn was cut. Pages 38–61:
one paragraph per speaker's turn. Page 456 (Table of Names, two columns): the names `Khalid Saeed Ahmad
al Zahrani`, `Mohammed Haydar Zammar`, `Ayman al Zawahiri` and four descriptions stand apart; the
names and descriptions still read column by column, as before. The venue lines under each hearing title
(`Congress and Civil Aviation Security` / `Hart Senate Office Building, Washington, D.C.` / `May 22–23,
2003`) are now separate paragraphs, one per source line. Page 38's first-paragraph note reference
target moved from `chapter-27.xhtml` to `chapter-28.xhtml` with spine packing; the note is unchanged.

During development, two over-reaches were found in these lanes and closed: FAA page 521's index
(`Very high frequency (VHF) omni-directional` / `radio range (VOR)….3-13`, split while sub-entries
counted as evidence) and the Supreme Court's pages 1, 8, 45 and 82 (an indented first line of a syllabus
paragraph or footnote after a letterless rule, split while any indented line counted as a continuation).

## Verification

On the merged tree (`f8a0a7a` with #138 and #134):

- `swift test`: 707 pass (5 in `HangingEntryTests`).
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 231 pass.
- `scripts/check-all.sh --fast`: exit 0, including the generated doc counts and byte-identical repeat
  conversions.
- Corpus lanes above: the 9/11 lane fails the baseline on exactly the 9 new checks it should and passes
  the candidate; every other English case passes both.

## Remaining defects

1. **An entry that nearly fills the widest line still runs into the next** (463 `The Honorable Louis J.
   Freeh, …` / `The Honorable Janet Reno, …`; 464 `Joseph F. Bruno, …` / `The Honorable Rudolph W.
   Giuliani, …` and `Adam B. Drucker, …` / `CIA Officials`). Expected: one paragraph per witness.
2. **Page 457's panels have no wrapped entry**, so the page has no hanging evidence: `The Attackers,
   Intelligence, and Counterterrorism Policy` stays fused with its four witnesses, and the witnesses of
   every panel on the page run together. Page 461's `Preventive Detention: Use of Immigration Laws and
   Enemy Combatant Designations to Combat Terrorism` is now its own paragraph but not a heading.
   Expected: headings and one paragraph per witness, as on 458.
3. **Table of Names (pages 449–456) reads its two columns one after the other**, so each name is
   separated from its description; a line opening in lowercase (`(a.k.a. …`, `see …`, `al Bashir`)
   never opens an entry, so some descriptions still run together (`… prior to 9/11 (a.k.a.Abdul Basit)
   Pakistani; …`). Expected: each name with its description.
