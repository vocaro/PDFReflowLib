# Questionnaire items and single marked lines (#195)

The owner's decision on two of the classes the [survey](../semantic-lists/record.md) left
ambiguous after the [first list conversion](../real-lists/record.md) (#194):

- **CIA questionnaire items**: an ordered list only where the printed numbers run consecutively,
  under #194's verification rule; otherwise unchanged.
- **Single marked lines**: an ordinary paragraph that keeps its printed marker; no one-item lists.
- Follow-up rulings: Warren's verified numbered runs list too (they are #194's approved class), and
  no list element holds one item: a piece of a verified run that other blocks set apart is a
  paragraph keeping its printed marker, everywhere, including #194's native-text runs.

Nothing else moves. The NOAA bibliography, Warren's endnotes, lettered sub-items and Wallace's
exercises and answer keys stay preformatted.

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLI. Baseline:
`48afc81` (converter SHA-256 `21228712…`). Candidate: `48afc81` plus this change (`89a4f98c…`).
Both ran all 21 gated cases (Warren included, #202) through `tools/run_corpus_regressions.py` one case at a time with one
environment probe, and each pair was compared with `tools/compare_conversion_runs.py
--allow-different-converters` and a block-level diff of the two EPUBs. No EPUB is committed.

## Root cause

`ListBuilder` skipped every block whose text transcribes a scan (`ListEvidence.recognized`), so the
CIA report's inherited text layer could offer no candidate at all, whatever its numbering. And a
marked line no run reached stayed preformatted, whether or not anything list-shaped stood near it.

## The change (`Sources/PDFReflowLib/ListBuilder.swift`)

1. **Transcribed numbered items are candidates.** A transcription of a scan now offers numbered
   items, held to exactly #194's rules (ascending by one, a `1` opens a run, at least two items, at
   least one contiguous pair, the contents, exercise, reference and answer-key rules). Its bullets
   stay excluded: in the CIA report they are recognition of table headers (`- Per Cent`).
   One rule is added for transcriptions only: a run whose numbering the list-shaped block beside it
   continues (`1.`–`3.` followed by `4. Isaacs DE 1 : CE 1159.`, which reads as no item) is a
   fragment of a notes apparatus whose other entries recognition garbled, and stays preformatted.
   Without it, Warren page 897's notes `1.`–`3.` and `6.`–`9.` became two lists. The CIA
   questionnaire's runs are set off by lettered options or other blocks, never by a number that
   continues them.
2. **Lone marked lines become paragraphs.** Before runs are built, a single-line block opened by a
   bullet or number marker, reading as words and not a contents entry, becomes `.paragraph` with its
   text (marker included) unchanged when no other list-shaped block is its neighbour on its page or
   the pages beside it. Two exceptions keep the printed form:
   - a number whose nearest same-punctuation numbered line either way, however far, is a sibling
     (one or two apart): numbered section titles spread over a paper (Geltman's `3. Quantum
     Description` on page 3, between `2.` on page 1 and `4.` on page 6), which the issue records as
     staying preformatted;
   - a note's asterisk (`* Leverage ratio is…`, Fed page 55), which is not a bullet.
3. **A one-item piece is a paragraph.** After runs are verified, an accepted item with no other
   accepted item beside it (only page boundaries may stand between) becomes `.paragraph` with its
   printed marker, instead of a one-item `<ul>`/`<ol>`. A piece is the whole stretch of touching
   items, nested ones included, so a numbered item with its own bullets still lists, and so does a
   lone bullet nested inside a longer list (9/11 page 147, DGA page 7, TechPort page 2: four nested
   one-item lists remain, each inside a list element of several items).

## What changed, per book

Against the `48afc81` baseline, pages changed only where listed; every other page of all 21 cases
compares equal (ids normalized). Every case: words in reading order identical (list numbering and
bullets restored as printed markers, except DGA's three `+` items on pages 3 and 9, which the
baseline's one-item `<ul>` rendered as `•` and which now print their own `+`), no image asset changed, navigation unchanged, page markers
equal, conversion report unchanged.

| Book | New `<ol>` (items) | Lone line → `<p>` | Run piece → `<p>` | Baseline one-item lists → `<p>` | Pages changed |
|---|---:|---:|---:|---:|---|
| faa-phak-8083-25c | 0 | 0 | 0 | 23 | 23 pages (25, 30, 32, 43, 47, 98, 99, 179, 210–213, 237, 238, 313, 317, 349, 366, 369, 370, …) |
| gpo-warren-1964 | 10 (37) | 4 | 22 | 0 | 46–51, 53–55, 61, 178, 211, 212, 420, 545, 628, 636, 667 |
| noaa-nca5-2023 | 0 | 1 | 0 | 8 | 42, 65, 588, 817 |
| gpo-911-2004 | 0 | 0 | 0 | 7 | 356, 405, 421, 422, 426, 430, 441 |
| ntrs-20190030725-dasc-2019 | 0 | 0 | 0 | 5 | 6 |
| cia-blue-book-14-1955 | 4 (12) | 3 | 5 | 0 | 1, 22, 62, 269, 270, 283–287 |
| fed-explained-2021 | 0 | 0 | 0 | 4 | 18, 60, 113, 114, 117 |
| wallace-algebra-2010 | 0 | 1 | 0 | 4 | 2, 64, 391 |
| dga-2025-2030 | 0 | 0 | 0 | 3 | 3, 9 |
| cdc-zombie-pandemic-2011 | 0 | 1 | 0 | 0 | 6 |
| census-rrs2002-01 | 0 | 1 | 0 | 0 | 5 |
| the other 10 | 0 | 0 | 0 | 0 | none |

"Baseline one-item lists" are #194's one-item `<ul>`/`<ol>` elements in the baseline, 54 in all, each
now a paragraph with its printed `•`, `+` or number: for example FAA page 211's `• White arc—…`
(its wrapped lines are paragraphs between the items), FAA page 317's `12. Remarks—…`, NOAA page
42's four key-message bullets, each split from the next by its wrapped line, and Wallace page 64's
`• More than…` and `• Less than…`, which a worked example separates. "Run piece" counts the new
runs' own one-item pieces.

**CIA questionnaire.** Verified runs `21.`–`28.` (pages 269–270), `17.`–`22.` (pages 283–284) and
`32.`–`34.` (pages 285–287) give four lists of two or more: `22.`–`27.` (page 270), `17.`–`18.` and
`20.`–`21.` (283–284) and `32.`–`33.` (285–286). `21.`, `28.`, `19.`, `22.` and `34.` each stand between
lettered options or answer lines, so each is a paragraph keeping its number. Every other
questionnaire item keeps its preformatted form: page 266's `1.`, `2.`, `10.`, `11.` and page 288's
`39.`–`41.` (never two touching), pages 272–278's questions (each followed by lettered options,
which end a run), `16.`/`18.` on page 275 (a gap), and the lettered options themselves.

**Single marked lines** now paragraphs:

- CDC page 6 `1) Get a Kit`; Census page 5 `3. If R < Tx, then designate pair as a nonlink.`
- CIA page 1 `• Authorizati6n Ac-e' for Fiscal Year 2024`, page 22 `• identification as a common
  object or some` (a wrapped line whose first glyph was read as a bullet) and page 62 `36.
  COMPARISON OF EVALUATION OF OBJECT SIGHTINGS…` (a table title).
- **Flagged for the owner:** NOAA page 817 `18. Sector interactions, multiple stressors, and complex
  systems. In: Fifth National Climate Assessment.` is the wrapped third line of a chapter's
  *Recommended Citation* (`… 2023: Ch.` / `18. Sector…`), not a bibliography entry; its neighbouring
  lines are already `<p>`, so it now matches them. Wallace page 391 `1) Which of the following is a
  function?` is the only text exercise of its set (the rest are pictures between `a)`…`d)`
  paragraphs). Neither is renumbered or listed: both keep their printed marker as a paragraph. If
  the owner wants exercise and reference text untouched even as paragraphs, the rule needs a
  document-level signal for those apparatus, which #195's prerequisites would supply.

The survey's other singletons stay preformatted because something list-shaped stands beside them:
the CIA's 29 others sit among recognition debris of its data tables (`- Per Cent` over `I) 0 0.0`),
and lettered names (`J. Cofer Black`, `D. L. Mills.`) carry no bullet or number marker.

## Warren

Warren is also a scan with an inherited text layer, so the transcription rule reaches its own
verified numbered runs, the survey's `numbered-list-item` class; the owner confirmed they list. Ten
lists of two or more: the Commission's conclusions (pages 46–51) and recommendations (53–55), the
Dealey Plaza map key (61, `2. DAL-TEX BUILDING` … `11.`), Oswald's instructions to Marina (211–212),
his statement (420) and the appendix's ten subjects (667): ten `<ol>` elements holding pieces of two
or more (conclusions `3.`–`4.`; recommendations `2.`–`3.`, `7.`–`8.`, `9.`–`10.`, `11.`–`12.`; map key
`2.`–`11.`; instructions `3.`–`5.` and `7.`–`8.`; statement `1.`–`2.`; subjects `1.`–`10.`). Items whose
wrapped lines stand between them and the next are paragraphs with their numbers: conclusions `1.`,
`2.`, `5.`–`12.`, recommendations `1.`, `4.`–`6.`, instructions `1.`, `2.`, `6.`, `9.`–`11.` and statement
`3.`, `4.`. The endnotes do
not move (page 897 pinned), nor do the testimony turns, elisions or lettered items. Four OCR
fragments with a bullet read into them become paragraphs (178 `• SCHOOL BOOK`, 545, 628, 636).

## Contracts

`corpus/regressions.json`: Warren pages 46 (conclusion `1.` a paragraph), 47 (`ol` from 3), 53 (from
2) and 54 (from 7 and from 9); CIA page 270 (`ol` from 22) and page 283 (`ol` from 17, with its lettered
options still preformatted), page 288 (`39.`–`41.` stay preformatted); Warren page 897 (the
notes `1.`, `2.`, `6.` stay preformatted); CDC page 6 and Census page 5
(paragraphs with their markers); Geltman page 3 (the section title stays preformatted) and Fed
page 55 (the note asterisk stays preformatted). Seven existing #194 checks that pinned one-item
lists now pin the paragraph with its printed marker instead (DGA pages 3 and 9, FAA 211 and 317,
Wallace 2 and 64 twice). The list and paragraph checks fail on the baseline output; the
preformatted controls pass on both.

## Lanes

All 21 gated cases pass with the candidate.
