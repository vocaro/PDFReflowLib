# Drop-cap initials joined to their words (#135)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, release CLIs.
Baseline: `96667ce` with the #132 blank-page commit (converter `43e0ea8e…`, see
[the blank-page record](../blank-pages/record.md)); candidate: that tree with this change
(`b9a0d638…`). 9/11, Fed, Our Flag, FAA and Wallace were run on that base; the change was first
measured on `ce2cf5b` against every English lane case with the same result, and the other eight
cases' summaries in `lane/` are from that run. Corpus figures are `tools/run_corpus_regressions.py`,
one case per call, with the compiled raster/Vision probe and `--execution-context host-terminal`,
then `tools/compare_conversion_runs.py --allow-different-converters --detail` (summaries in `lane/`). No PDF or EPUB is committed.

## Diagnosis

Our Flag sets each section's first letter as a 43.5-point `SnellRoundhand-BoldScript` initial
lowered 24 points beside 9-point StoneSerif prose. The content stream draws the initial and then a
space glyph in the script font (`mutool draw -F stext` page 31: `A` at x 65–102.8, space to 114.5;
`ny honorably…` starts at 112.1). PDFKit returns one line, `A ` (43.5 pt, offset −24) followed by
`ny honorably discharged…` (9 pt), and `NativeTextReader.dropCapBodySize` already recognizes the
pattern: it gives the line the body size and a body-height `readingRect` (the drop-cap order fix).
The space glyph stayed in the text, so every such opening read `T he`, `D uring`, `A ny`. #125 only
stopped the initial gaining `<strong>`.

## Survey

`tools/dropcapscan.py` lists every single capital at least twice the size of the lowercase text
that follows it in `mutool`'s structured text, across the English corpus.

| Book | Candidates | What they are |
| --- | --- | --- |
| Our Flag | 19 | 18 drop caps with a space glyph (pages 5, 7, 8, 9, 10, 13, 16, 26, 27 ×2, 28, 29, 30, 31, 46, 49, 50, 53) and page 47's `O` + `n July 4`, drawn without one and already read `On` |
| Blue Book | 365 | the OCR layer's `I` for scan-margin marks; invisible text over a scan carries no native style, so no line has drop-cap evidence |
| Warren (excluded) | 4 | OCR layer `A fictitious`, `A critical`, `A final` (real one-letter words), `H i.i-`; same, no native style |
| Fed Explained, 9/11, FAA, Wallace, DGA, NOAA, CDC, NBS, Replay Clocks, USGS, SCOTUS, Census | 0 | — |

The Fed's chapter openers set a 70-point numeral lowered 31.6 points before a 24-point title
(`1` `Overview of the Federal…`). A digit is no letter and the title opens in a capital, so it never
gains a `readingRect`; its `1 Overview` space is #55's, and remains.

## Change

`LayoutReconstructor.joinDropCapInitials` runs on each page at the start of reconstruction, beside
`restoreEqualsHyphens`, and removes the whitespace between a drop cap's initial and its word. A line
qualifies only with `NativeTextReader`'s drop-cap evidence (`readingRect` set: one uppercase initial
at 2–8× the size of consistent, normal-baseline, lowercase-opening body prose, lowered by at least
the body size) and text that opens with one capital letter, whitespace and a lowercase letter.

`A`, `I` and `O` are words, so they join unless the book's vocabulary holds the fragment and not the
joined word (`A new` would stay; `A ny` → `Any`, `A rcheological` → `Archeological`; `A gain` joins
because `again` is a word). Every other letter always joins. `addVocabulary` no longer records a
drop-cap line's initial and fragment: it adds the joined word for other letters (`the`) and neither
for `A`, `I`, `O`, so `ny` never becomes evidence for its own split. The line keeps its geometry,
body size, reading rectangle, structure and styles; the initial carries no emphasis (#125). The join
edits the line in place through `TextLine.replaceContent`, which replaces the text and its cached
plain string and nothing else, so every other stored property, including any added later, survives.

## Tests

`DropCapJoinTests.swift`, on the captured Our Flag layouts replayed through `NativeTextReader`:

- pages 7, 9, 27 (two), 29, 30 and 31 read `The …`, `Constituents`, `Any honorably …`, with no
  `X yy` opening left, and the joined line keeps `readingRect` and size 9; unjoined reconstruction
  still reads `T he Stars` (the defect);
- controls unchanged: the Fed's numeral openers (fixtures `fed-8`, `fed-14`, `fed-24`), the Blue
  Book's large `I` beside capitals (`blue-5`), and `T he plain line` without a reading rectangle;
- the one-letter-word rule (`T`/`he`, `A`/`ny`, `A`/`rcheological`, `A`/`new`, `A`/`gain`, `I`/`n`),
  and Our Flag page 31 keeping `A ny` when a vocabulary holds `ny`;
- vocabulary: page 31 adds neither `ny` nor the initial, page 7 adds `the` and not `t`.
- a joined line keeps every stored property but its text: all `Mirror` children other than `content`
  and `text` compare equal, and the line equals the original with only its content replaced.

Mutations, each run against the suite: ignoring the reading-rectangle evidence fails the unevidenced
control; never keeping a space fails 3 expectations of the one-letter rule; recording drop-cap
fragments fails both vocabulary expectations; skipping the join fails the Our Flag test (3
expectations); rebuilding the line from its initializer without copying `readingDirection` fails the
property test. The existing `DropCapTests` (order, headings, ink bounds, fractions) pass unchanged.

## Contracts

`corpus/regressions.json`, Our Flag: pages 5, 7, 13, 27 and 31 require the joined opening in one
paragraph (`During the night…`, `The Stars and Stripes originated…`, `Archeological digs…`, `The life…`
and `The size…`, `Any honorably discharged veteran…`) and forbid the split text; page 47's `On July 4,
1776…` is the control. The #132 build fails the 12 new checks on pages 5–31 and passes page 47; the
candidate passes all 86 Our Flag checks. The Fed's existing contracts keep `1 Overview of the Federal
Reserve System` and `2 The Three Key System Entities` as headings and forbid `1Overview`.

## Corpus lane

| Case | Baseline | Candidate | Changed pages |
| --- | --- | --- | --- |
| gpo-our-flag-2003 | fail (new contracts only) | pass | 5, 7, 8, 9, 10, 13, 16, 26, 27, 28, 29, 30, 31, 46, 49, 50, 53: one replacement per drop cap (`D uring`→`During` ×2, `T he`→`The` ×8 including page 27's two, `W hen`, `A rcheological`, `P resentation`, `N o`, `C onstituents`, `A ny`, `E ach`, `F ort`); paragraph counts and headings equal; no image, warning or navigation change |
| fed-explained-2021, gpo-911-2004, faa-phak-8083-25c, wallace-algebra-2010 | pass | pass | none |
| cdc-zombie-pandemic-2011, dga-2025-2030, cia-blue-book-14-1955, nbs-jres-geltman-1977, usgs-mcs2025-copper, scotus-loper-bright-2024, census-rrs2002-01, arxiv-replay-clocks-2023 (on `ce2cf5b`) | pass | pass | none |

## Limits

A drop cap PDFKit does not report with the drop-cap attributes (a separate selection, missing
baseline offsets, an initial beside uppercase or short text) is untouched, as it was. The `A`/`I`/`O`
rule depends on the book's own vocabulary and would keep a space where the fragment alone is a word
the book uses and the joined word never appears.
