# Citation-leading wrapped lines (#39)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI.
Baseline: repository `56e70e2`, Xcode 27.0 (27A266a), macOS 27.0 (26A428). `identity.json` pins
both converter binaries, the Loper Bright source and the four new fixtures.

## What was wrong

`LayoutReconstructor.isList` matched `^(?:[•*−-]|[0-9]+[.)]|[A-Za-z][.)])\s` on every line by
itself, so any wrapped body line that happened to begin with an initial (`U. S.`, `F.`, `v.`,
`E. Booker`) or a number followed by a period (`2016.`, `180.`, `p. 785`) became its own
preformatted block and split its paragraph. In *Loper Bright Enterprises v. Raimondo*
(`corpus/cache/22-451_7m58.pdf`, SHA-256 `12f5ea07…`) the default conversion emitted 75 `<pre>`
blocks; 74 were wrapped lines and one is the `* * *` section separator.

## What changed

`LayoutReconstructor.blocks` gains a local `continuesParagraph(_:)` check that the list branch
consults (`else if isList(line.text), !continuesParagraph(line)`). A marker-leading line
continues the open paragraph only when all of the following hold:

- the marker is a number or a single letter followed by `.` or `)`; bullets, minus and hyphen
  markers never continue prose;
- the previous line joined the current paragraph, is not an OCR line Vision marked as unwrapped,
  and does not end (after closing quotes/brackets) in `.`, `!`, `?`, `:` or `;`;
- the previous line reads as prose: at least three alphabetic words of two or more letters;
- the vertical gap is ordinary paragraph spacing (the same `-0.4…0.9` body-size window the
  prose branch uses);
- the line sits on the majority left edge of its column (same-size lines within 1.5 body
  sizes) and the previous line is on that edge or indented by less than 1.5 body sizes
  (an indented opening line);
- the column is justified: at least three same-size lines share the right edge within a
  quarter body size, and the previous line reaches it.

Everything else keeps the existing preformatted representation. No public API or default
changed; `isList` itself, tag-group validation, numbered-note detection and code handling are
untouched.

## Source evidence

Four layout fixtures were captured from the checksum-pinned slip opinion with
`tools/capture-layout-fixture.swift` (the documented compile commands now list
`Sources/PDFReflowLib/NativeSpacingReader.swift`, which they had omitted). Each page was read against the rendered
source before the expected text was written:

- Page 60 (`loper-60`): `…Brand X Internet Services, 545` / `U. S. 967, 982–983 (2005). And
  those officials may even dis-` / `agree with…`; body 10.98 pt, left edge 156.2, every wrapped
  line 299.4–299.7 pt wide, zero vertical gap.
- Page 7 (`loper-7`): `…under Chevron since` / `2016. But because Chevron remains on the books,
  litigants must con-`; 9 pt syllabus text.
- Page 13 (`loper-13`): indented opening line `A divided panel of the D. C. Circuit affirmed.
  See 45` (x 167.2) followed by `F. 4th 359 (2022). The majority addressed various provi-` at
  the column edge (x 156.2); exercises the opening-line outdent path.
- Page 2 (`loper-2`): `United States` / `v. Moore, 95 U. S. 760, 763. “Respect,” though…`,
  `…Morton Salt Co., 338` / `U. S. 632, 644, the Court often…` and the short last line
  `U. S. 134, 140.`; the page's four syllabus paragraphs must stay in order.

## Verification

`Tests/PDFReflowLibTests/CitationContinuationTests.swift`, ten tests:

- the four source pages: no preformatted block, the joined phrases inside one paragraph, and
  every source character retained; page 2 keeps four paragraphs with their openings and endings;
- synthetic justified prose with author initials, a year and a `v.` line stays one paragraph;
- lists stay separate after a short non-terminal introduction; after full lines ending in
  `:`, `.`, `.”`, `.)`, `?`, `!`; across a paragraph gap; with a marker indented 8 pt; after an
  unwrapped OCR line; when only two lines establish the right edge; for `•`, `−` and `-`;
- an indented numbered note after a dedented continuation stays a list, while the page-13
  opening-line geometry joins;
- algebra page 26: every spaced numbered exercise remains its own block; Warren page 50 keeps
  points 10 and 11 preformatted under the synthetic text style.

`before-tests.log.gz`: against the committed reconstructor the same suite fails with 23 issues
across all four source pages, the synthetic joins, the outdent and right-edge cases, while the
list-preserving controls pass.

Commands and results on the final tree:

- `swift test`: 201 tests pass (3 suites).
- `scripts/check-all.sh --fast`: 201 Swift tests, 114 Python tests, 8/8 concurrency smoke
  trials, 6 fixture conversions and 13 policy conversions with 15 rejection cases pass (1:43).
- `python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow --epubcheck
  /opt/homebrew/bin/epubcheck --output <new dir>`: all 13 gated cases pass EPUBCheck, progress,
  memory and content gates (`corpus-summary.json`); Warren and NOAA remain the explicit
  exclusions. The Loper Bright contract grows from 15 to 25 checks (pages 2, 7, 13 and 60 add
  `paragraphs` and `orderedText`); the lane now has 367 checks on 88 pages.
- `tools/compare_conversion_runs.py` refuses both runs because the corpus lane records no
  capability probe; `page-comparison.json` instead compares every parsed page, paragraph list,
  image byte and `<pre>` count through `tools/check_corpus_content.read_pages`.

## Before and after

Loper Bright: 75 `<pre>` blocks before, 7 after (68 wrapped lines rejoined). Nineteen pages
change text only through the existing hyphen policy now that the halves meet (`dis-`/`agree`
→ `disagree`; `even-`/`handed` keeps its compound). The seven remaining blocks are: `* * *`
(page 43, a separator, not a wrap); pages 64 and 107, where the token line is the first body
line after the running header (cross-page continuation, #45 territory); pages 26, 49, 51 and
73, where the previous line ends in a period (`…Service, Inc.`, `…Relentless Tr.`, or a real
sentence end) and the terminal-punctuation guard refuses the join.

All 3,000+ image files in every book are byte-identical. Text or paragraph lists change on 37
pages outside Loper Bright, all reviewed in `joined-fragments.txt` and `text-diffs.txt`. Every
join except the Blue Book one is a wrapped continuation:

| Book | `<pre>` before → after | Pages | Joins |
| --- | --- | --- | --- |
| arxiv-replay-clocks-2023 | 5 → 2 | 3 | `Section` / `5.`, `as large as` / `106.`, `December 16-19,` / `2014.` |
| cia-blue-book-14-1955 | 651 → 650 | 1 | **False join.** Page 19 is an inherited-OCR scan page (`unverifiedTextLayer`); `1132.01 representing an additional observer` and `1132. 02 representing an additional observer` are two separate serial-number entries of a code list that happens to look justified, and the second is now appended to the first. Neither representation was right before (the entry was a lone `<pre>` line), but this is not a wrapped continuation |
| faa-phak-8083-25c | 504 → 501 | 3 | `December 31,` / `1913.`, `Eugene` / `L. Vidal`, `January` / `1982.` |
| gpo-911-2004 | 939 → 917 | 19 | `Emma` / `E. Booker`, `John` / `F. Kennedy`, `Jack` / `S. to FAA`, dates and `p.` citations in the notes; three hyphen repairs (`civilian`, `Terrorism`, `California`) and six paragraph merges that follow from a rejoined block at a page boundary |
| gpo-our-flag-2003 | 19 → 7 | 9 | `modified in` / `1953.` and eleven similar state-flag dates, `adopted in` / `1777.` |
| wallace-algebra-2010 | 2826 → 2824 | 2 | `50 + 30 + 100=` / `180.`, `multiplied by` / `2.` |

Fed, DGA, CDC, IRS, USCIS, USGS, NBS and Census are identical page for page. The 9/11
numbered-note pages handled by `NumberedNoteDetector` are unaffected.

## Remaining gaps

- Blue Book page 19 shows the rule's exposure on unverified text layers: an inherited-OCR code
  list whose serial-number entries fill equal-width lines satisfies the justified-column and
  prose tests, so `1132. 02 …` is wrongly appended to the `1132.01 …` entry. The rule does not
  consult `unverifiedTextLayer` or recognize enumerated code lists; that page still carries its
  source image and warning.
- Ragged-right columns and hanging-indent continuations (bibliographies whose continuation
  lines are indented under `[12]`) keep the preformatted representation; the rule needs a
  justified right edge and the majority left edge.
- A wrapped token line after a line ending in an abbreviation (`Inc.`, `Tr.`) or a genuine
  sentence end stays split; distinguishing those needs more than punctuation.
- Token lines that open a page after a running header depend on cross-page continuation (#45).
- The rule joins lines; it does not create semantic lists, and `* * *` separators remain
  preformatted.
