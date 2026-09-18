# Questionnaire items and single marked lines (#195)

The owner's decision on two of the classes the [survey](../semantic-lists/record.md) left
ambiguous after the [first list conversion](../real-lists/record.md) (#194):

- **CIA questionnaire items**: an ordered list only where the printed numbers run consecutively,
  under #194's verification rule; otherwise unchanged.
- **Single marked lines**: an ordinary paragraph that keeps its printed marker; no one-item lists.

Nothing else moves. The NOAA bibliography, Warren's endnotes, lettered sub-items and Wallace's
exercises and answer keys stay preformatted.

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLI. Baseline:
`f90a567` (converter SHA-256 `c11d1146…`). Candidate: `f90a567` plus this change (`1066bf92…`).
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

## What changed, per book

Against the `f90a567` baseline, pages changed only where listed; every other page of all 21 cases
compares equal (ids normalized). Every case: words in reading order identical (list numbering
restored as printed markers), no image asset changed, navigation unchanged, page markers equal,
conversion report unchanged.

| Book | New `<ol>` elements (items) | `<pre>` → `<p>` | Pages changed |
|---|---:|---:|---|
| cia-blue-book-14-1955 | 9 (17) | 3 | 1, 22, 62, 268–270, 283–287 |
| cdc-zombie-pandemic-2011 | 0 | 1 | 6 |
| census-rrs2002-01 | 0 | 1 | 5 |
| noaa-nca5-2023 | 0 | 1 | 817 |
| gpo-warren-1964 | 32 (59) | 4 | 46–51, 53–55, 61, 178, 211, 212, 420, 545, 628, 636, 667 |
| wallace-algebra-2010 | 0 | 1 | 391 |
| the other 15 | 0 | 0 | none |

**CIA questionnaire.** Four verified runs: `21.`–`28.` (pages 269–270), `17.`–`18.` and `19.`–`22.`
(pages 283–284, split by `18.`'s lettered options) and `32.`–`34.` (pages 285–287). Where a lettered option or a figure stands between two items the
run's list element closes and the next opens with `start`, so each piece keeps its printed number
(page 270: `<ol start="22">` of six items, then `<ol start="28">`). Every other questionnaire item
keeps its preformatted form: page 266's `1.`, `2.`, `10.`, `11.` and page 288's `39.`–`41.` (never
two touching), pages 272–278's questions (each followed by lettered options, which end a run),
`16.`/`18.` on page 275 (a gap), and the lettered options themselves.

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

## Warren: the same rule reaches its numbered lists — owner decision needed

Warren is also a scan with an inherited text layer, so the transcription rule that lists the CIA
questionnaire lists Warren's own verified numbered runs too; no document-agnostic signal separates
them. These are the survey's `numbered-list-item` class, the class #194 approved but could not reach
in a transcription: the Commission's twelve conclusions (pages 46–51) and twelve recommendations
(53–55), the key to the Dealey Plaza map (61, `2. DAL-TEX BUILDING` … `11.`), Oswald's eleven
instructions to Marina (211–212), his four-point statement (420) and the appendix's ten subjects
(667). Every number printed is kept (`start`), words are identical, and each piece is a run whose
printed numbers ascend by one. The endnotes do not move (page 897 is pinned), nor do the testimony
turns, elisions or lettered items. Four OCR fragments with a bullet read into them become paragraphs
(178 `• SCHOOL BOOK`, 545, 628, 636).

If the owner wants Warren untouched, the transcription rule has to be narrowed by something other
than the document's name; I found no such signal, so this is reported rather than hidden.

## Contracts

`corpus/regressions.json`: CIA page 270 (`ol` from 22) and page 283 (`ol` from 17, with its lettered
options still preformatted), page 288 (`39.`–`41.` stay preformatted); Warren page 897 (the
notes `1.`, `2.`, `6.` stay preformatted); CDC page 6 and Census page 5
(paragraphs with their markers); Geltman page 3 (the section title stays preformatted) and Fed
page 55 (the note asterisk stays preformatted). The list and paragraph checks fail on the baseline
output; the preformatted controls pass on both.

## Lanes

All 21 gated cases pass with the candidate.
