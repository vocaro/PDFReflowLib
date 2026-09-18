# Census follow-ups to index-glyph decoding (#149)

Corpus `census-rrs2002-01` (`corpus/cache/rrs2002-01.pdf`, SHA-256
`0f97380ae4308581bd70013b7317faafd7c217654236bd31d1448f26eae56905`). Tier: deterministic Apple PDF
stack, macOS 27.0 arm64, release CLIs, library defaults unless stated. Work on `f3840f4`. Date
2026-09-17. English only.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `f3840f4` | `6b0bf43a6d951325763339e54030eec92d518dc95d0b85d5e874103e0d4aee99` |
| candidate | this tree on `f3840f4` | `6b5d17518263be85d0b495e23978017f25c9754f2a905e483c58cdd618a92d68` |
| probe | `tools/probe-raster-environment.swift` | `ba7f59525cdecf1e5e7749bfd41ff5d3233d703fb4fc51dce5065d56e06b0a4c` |

Both converters were launched as `pdf-reflow` from separate directories, so every lane shares one
Vision model cache name and compiled-program fingerprint (`22614cb0…`, #94). No PDF or EPUB is
committed; `lane-summaries/` keeps each run summary and comparison.

## State at `f3840f4`

Defaults (automatic OCR) reproduce #143's split: pages 3 and 17 reflow natively; pages 2, 4–16 and
18–20 report `damagedTextEncoding` and are recognized. Against the issue's list:

| Item | At `f3840f4` |
| --- | --- |
| Page 3: `The ﬁle also has … data from the` split from `public-use CPS ﬁle.` | **fixed** since #143's review (one paragraph at `f3840f4`) |
| Page 3: `2.1 Domingo-Ferrer and Mateo-Sanz` opens its paragraph (also `2.2 Kim-Winkler`) | open (layout, below) |
| Page 3: `[ 5]` | faithful: the source sets `[ 5]` with a visible gap (render) |
| Page 17: reference number as its own paragraph | **partly fixed** by #162: `[1]`, `[ 9]`, `[ 10]`, `[11]`, `[ 13]`, `[ 14]` are whole; `[2]`–`[ 8]` and `[ 12]` still split; fixed here |
| Page 17: entry 12 `JournalofOﬃcialStatistics` | open; fixed here |
| Page 17: `7 References References` | open (layout, below) |
| Page 17: `Univer-sity` | open (hyphen vocabulary, below) |
| Page 16: one line read as four | open (PDFKit; page held by its table anyway, below) |
| Page 2: e-mail line and title mark | open (undecodable fonts, below) |
| Math pages 4–11, 13, 14, 18–20 | open (undecodable fonts, below) |

## What the font programs say

`page-fonts.py` lists the fonts each page's content stream draws (shows per font) and each embedded
CFF program's names; `glyph-chart.py` draws every glyph of one program labelled with its `G<n>` name.
Every CFF program names its glyphs `G<n>` alone; its Top DICT gives only `FullName`
`FontMonger:<family>` and `FamilyName` `<family>` (`cmmi10`, `dctt10`, …). Read off the charts:

| Font | Glyphs | Layout of `G<n>` (TeX code c) |
| --- | --- | --- |
| `dcr`, `dcbx`, `dcti` (decoded by #143) | 80, 52, 52 | n = c + 3, T1 |
| `dctt10075` | 24 | n = c + 3, T1: `{`, `}`, `@`, `,`, `.` and letters spell `{william.e.yancey,william.e.winkler,robert.h.creecy}@census.gov` |
| `cmr10084` | 24 | n = c + 3, OT1: macron, `%`, `(`, `)`, `+`, `0`–`5`, `=`, `C`, `P`, lowercase |
| `cmsy10084` | 10 | n = c + 3, OMS, for nine: `−`, `×`, `±`, `≤`, `∼`, `⊂`, `∈`, `/`, `|`; `G115` (a small stroke at chart size) not identified |
| `cmmib10084` | 1 | n = c + 3, OML: `G66` is the title's `⋆` (63) |
| `cmmi10084` | 50 | letters, `ω`, `ε`, `.`, `,`, `<`, `>` at n = c (`G100` is `d`, confirmed on page 20's render: `parameters d`, `Z = X + dY.`); Greek below 32 elsewhere: `Γ` 134, `Σ` 140 (c + 134), `γ` 149, `θ` 154, `μ` 158, `σ` 163, `ψ` 168 (c + 136) |
| `cmex10084` | 25 | not charted |
| Type3 `T2`–`T6` | 1–196 per font | bitmap glyph procedures named `c<n>`; no program names |

So no offset belongs to an encoding family: `cmmi` and `cmmib` share OML and differ, and `cmmi` has no
single offset at all. A rule that gave an undecodable font the offset its decoded siblings share
would decode `dctt`, `cmr`, `cmsy` and `cmmib` correctly and `cmmi` wrongly (`d` as `a`), and nothing
in mathematics could tell. Decoding them needs glyph identity (outlines); the family name only says
which TeX font it was, not FontMonger's numbering.

Fonts drawn per page (shows): page 2 draws `dctt` (1), `cmmib` (1) and `T2` (1) beside the text
fonts; pages 4–9 and 18–20 draw Type3 bitmap fonts (2–56 shows) with `cmmi`, `cmr`, `cmsy`,
`cmex`; page 10 draws `cmmi`, `cmr` and `cmex`; pages 11, 13 and 14 draw `cmmi` and `cmr` in
numeric-table pages; pages 12, 15 and 16 draw only `dcbx`, `dcr` (and `dcti`) but hold numeric
tables.

## Why each page stays or changes

- **Math pages (4–11, 13, 14, 18–20).** Unreachable by decoding `cmmi` alone: every math-prose page
  but page 10 also draws Type3 bitmap fonts, page 10 draws `cmex`, and pages 11, 13 and 14 are
  numeric-table pages that #143's grid guard keeps on OCR (#150's scope). No change.
- **Page 2.** Three undecodable fonts: `dctt` (8 words, below #143's 20-word minimum), `cmmib` (one
  glyph) and `T2` (one bitmap glyph, the footnote's `⋆`). The e-mail line and both stars keep the page
  on OCR. No change.
- **Page 16.** Only decoded fonts, but PDFKit returns four selections with identical bounds spanning
  two rows (`…Wkh whvw`, `w`, `w`, `w\nohv…`): the `ﬁ` that opens `ﬁles` (`G31`, which PDFKit reports as
  nothing) follows `test` at a line end. Every show's origin lies in four identical rectangles, so
  ownership is ambiguous and repair refuses. Table 9's rows would also hold the page by the numeric-grid
  guard, so repairing that line alone changes no output. No change.
- **Page 17, split references (fixed).** One TJ sets each reference number with its entry's first
  line (`[{-345.8}4{0.2}]{-959.2}D{-19.5}e…`); PDFKit reads eight of those rows as two lines. #143's
  repair already carries the show's remaining glyphs from the number's line to the entry's, but the
  two stayed separate lines, so the number became a paragraph of its own.
- **Page 17, entry 12 (fixed).** Its italic title (`J{-13.5}o…l{-283.5}o{-8.5}f{-280.2}O…`, Tc ≈ 0,
  0.28 em word gaps) is on the entry's first line. `NativeSpacingReader.apply` gives a line the shows
  whose origin it holds, and the row's first show begins at the number, so the entry's line held only
  the italic show and did not spell its own text; no gap was read. Entries 4 and 7 carry the title on
  their second lines and were already spaced.
- **Page 17, `7 References References`.** PDFKit gives two lines 26.2 pt apart at a 12 pt heading
  size (its attributes). `LayoutReconstructor.stacksUnderHeading` admits a next heading line up to 2.2 em lower
  (26.4 pt) whose top reaches within one em (0.4 pt spare), and `continuesHeading` sees no section
  number on `References`: two headings read as one wrapped heading. Layout; not changed here.
- **Page 17, `Univer-sity`.** The hyphen is Cork 45, not the 127 hyphen character, so the font
  gives no break evidence; `University` appears nowhere else in the book, and #131's joiner keeps the
  hyphen without vocabulary evidence (`uncertainHyphen`). Not changed. Two ranges broken after an en
  dash also gain a space in the join (`456– 461`, `114– 119`).
- **Page 3, `2.1` and `2.2`.** The subsection titles are bold at the body's own size (10.08 pt,
  PDFKit's attributes; `LayoutReconstructor.isList` is false for both). By the code,
  `LayoutReconstructor.sectionLabels` takes such a title as a label only in a style the book repeats
  as narrow labels on at least three pages (`labelStyles(from:)`), and recognized pages give no
  evidence: with pages 4–20 on OCR, the style appears on page 3 alone, so each title joins the
  paragraph beneath it. Layout; not changed here.

## Rule

`NativeTextReader` (#149, `joinsSplitShow`): where repair carries a show's glyphs from one PDFKit line
to the next line of its row, and that next line repairs completely with nothing carried on, and its
repaired text continues in words (`continuesInWords`: at least three words of three or more letters,
letters at least half its visible characters), the two lines are one typeset line. They are read as
one: PDFKit's characters joined (a space added only where neither side has one), over the union of
their rectangles, repaired again with no carry, then spaced and styled. The union holds every show of
the row, so the italic title's gaps are read. A row whose continuation is figures (page 12's
`rnkswp05` and its rates, one show split the same way) keeps its pieces for the table path. Only
index-glyph pages can carry, so no other book is reachable.

## Census before and after (defaults)

`compare_conversion_runs.py` (`lane-summaries/compare-census-rrs2002-01.json`): page 17 alone changes
(text, paragraphs, markup); the 17 recognized pages have identical OCR text (5,247 words), no image
changes, the report is unchanged. Under `--ocr never` also only page 17 changes: pages 11–16 keep
their row pieces. Review of page 17 against a 130-dpi render: each of `[2]`–`[ 8]` and `[ 12]` now
opens the paragraph of its entry as printed, and entry 12 reads `[ 12] Lambert, D.: Measures of
Disclosure Risk and Harm, Journal of Oﬃcial Statistics, 9, (1993) 313–331.` The numbers keep the
gap the source prints in `[ 3]`–`[ 10]`, `[ 12]`–`[ 14]` and not in `[2]`, `[11]`.

## Lanes

`tools/run_corpus_regressions.py --case <id>` for each binary (one case per call, EPUBCheck, probe,
`--execution-context host-terminal`), then `tools/compare_conversion_runs.py
--allow-different-converters`. Census's contract was updated first, so the baseline fails it.

| Case | Baseline | Candidate | Changed pages |
| --- | --- | --- | --- |
| census-rrs2002-01 | fails the new contract (6 errors, page 17) | pass (80 checks) | 17 |
| wallace-algebra-2010 | pass (288) | pass (288) | none |
| gpo-911-2004 | pass (306) | pass (306) | none |
| nbs-jres-geltman-1977 | pass (64) | pass (64) | none |

## Content contract

`corpus/regressions.json`, `census-rrs2002-01` page 17: `paragraphs` adds `[2] Dalenius, T. and
Reiss, S. P. Data-swapping: A Technique for Disclosure Control`, `[ 5] Domingo-Ferrer, …`, `[ 8] Kim,
J. J.: …` and `[ 12] Lambert, D.: Measures of Disclosure Risk and Harm,`; `orderedText` adds entry 12
whole with its spaced title; `absentText` adds `JournalofOﬃcialStatistics`. The baseline fails exactly
these six checks.

## Tests

`Tests/PDFReflowLibTests/GlyphIndexDecodingTests.swift`, three tests on #143's fixture
(`fixtures/census-text-operators.json`):

- `censusReferenceRowsThatOneShowSetsAreReadAsOneLine`: on the captured page 17 lines exactly eight
  rows join (`[2]`–`[ 8]`, `[ 12]`), `[2]`'s joined line and entry 12's spaced title are exact, and the
  entry's line alone keeps `JournalofOﬃcialStatistics`; page 12's split rows do not join (figures);
  without decodings nothing joins.
- `continuationsInWordsAreProseAndFiguresAreNot`: entries, figure rows, two words, words among
  figures, empty.
- `censusReferencePageReadsEachEntryAsOneParagraph`: the rebuilt fixture through
  `PDFReflowLibPipeline` under `.never`: `[2] Dalenius, …` opens a block and no number stands alone.
  PDFKit reads row `[ 12]` whole in the rebuilt page, so that expectation is not the discriminating one.

Mutation checks (sources restored):

| Part disabled | Failing tests |
| --- | --- |
| the join (`joinsSplitShow` returns nil) | 2 (both Census tests) |
| words-versus-figures (`continuesInWords` always true) | 2 (page 12 control, unit test) |

A third mutation, repairing the joined line against rectangles where the union replaced its two
pieces, failed nothing (each show's origin already lies in one piece alone), so the code keeps the
page's own rectangles.

## Commands

```sh
git merge f3840f4
swift build -c release && swift test          # 906 tests
scripts/check-all.sh --fast                   # passed
python3 measurements/index-glyph-follow-ups/page-fonts.py corpus/cache/rrs2002-01.pdf
python3 measurements/index-glyph-follow-ups/glyph-chart.py corpus/cache/rrs2002-01.pdf cmmi10084 <out.pdf>
mutool draw -r 110 -o <out.png> <out.pdf> 1
python3 tools/run_corpus_regressions.py --converter <dir>/pdf-reflow --epubcheck /opt/homebrew/bin/epubcheck \
  --output <lane> --case <id> --environment-probe <probe> --execution-context host-terminal
python3 tools/compare_conversion_runs.py --baseline <base-lane>/<id> --candidate <cand-lane>/<id> \
  --output <cmp> --allow-different-converters
```

## Limits and follow-up defects

1. **Math fonts** need glyph identity from outlines: `cmmi`'s numbering has no single offset, and
   pages 4–9 and 18–20 also draw Type3 bitmap fonts. Page 10 (`cmmi`, `cmr`, `cmex`) is the only math
   page without Type3 fonts.
2. **Page 2** needs `dctt`, `cmmib` and the bitmap `T2` decoded; their offsets are right at +3 on the
   charts, but no evidence in the file separates them from `cmmi`'s case.
3. **Page 16:** PDFKit's four identical selections over two rows; and the page holds Table 9.
4. **Page 17:** `stacksUnderHeading` merges `7 References` and `References` (2.2 em reach); `Univer-sity`
   lacks vocabulary; en-dash ranges broken across lines gain a space (`456– 461`).
5. **Page 3:** bold subsection titles at body size need a label style seen on three native pages,
   and Census has one.
