# Maths italic, nested styles and runs split by a joining space (#142)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Work started on `70fc9b4` (the coordination branch's tip: `73cbdfe` page rasters without their
constant alpha plane, `88803ac` native text under a self-painted backdrop, `1a7b008` bulleted line
sizes and rejoined stretched word spaces, `70fc9b4` broken words across head and foot matter).
Every figure below compares release CLIs built from `70fc9b4` and from this tree on it, with one
capability probe for both.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `70fc9b4` | `563c816d2da831b306b4bdf1669a1ff337efee1b9a0bee25d10564940eb5eb05` |
| candidate | this tree on `70fc9b4` | `4623d3c3257a2a10a2431386f4431d2cdcceee5538a79085d88a842071dd864c` |
| probe | `tools/probe-raster-environment.swift` | `9595d7e232cb4e024df053ca3048b83e696dd4c41fe57ee153191310ea5c4159` |

No source PDF or EPUB is committed. Each lane's EPUBs were deleted after review;
`lane-summaries/` keeps both run summaries and the comparison per case.

The issue carries no owner comment; the decision recorded here (`<i>`, not `<em>` and not `<var>`)
is the one the task stated, and the reasoning is set out under **Rule** below.

## Diagnosis

#133 read a font's slope from its own resources and decided that **maths italic is never
italic**, because `<em>` states spoken stress and the encoder had no other italic. It left three
defects.

1. **Maths italic has no markup.** Wallace's Computer Modern variables (`5x− 2y`, page 23) reach
   the EPUB upright. The survey in #133 found 19,482 maths italic shows in Wallace, 1,140 in
   arXiv and 393 in Census, and a lane built with maths italic read as italic reached 14,193
   italic runs on 385 Wallace pages.
2. **Nested styles are not merged.** `EPUBTextEncoder.styled` wrapped each `InlineText` element
   on its own, so adjacent runs sharing a style repeated it: `<strong><em>Demand</em></strong>`
   `<strong> Shocks</strong>`.
3. **An unstyled joining space splits runs.** `LayoutReconstructor` joins two source lines with a
   space of its own (`InlineText(" ")`), which carries no style, so a style that spans the join
   is written twice: arXiv page 4's `<strong>=15, and the</strong> <strong>shift is issued…`.

The issue's own reproducer for (2), Fed page 30, no longer reproduces on `70fc9b4`: that
sidebar subtitle is now one line, and both binaries write `<strong><em>Demand Shocks</em></strong>`.
The class it names is real and shows elsewhere — CDC page 22's comic lettering is
`<strong>yes, th is is </strong><strong><em>Dr. KHAN.</em></strong><strong> no, TELL </strong>…`
in the baseline and one `<strong>` in the candidate. (3) reproduces exactly as filed.

## Rule

**Maths italic is a style of its own** (`TextStyle.mathItalic`), read by `FontWeightReader` and
written `<i>` by `EPUBTextEncoder`.

*Why `<i>`.* The evidence a page gives is that a glyph came from a maths italic font. `<em>`
states spoken stress, which assistive reading can voice and which a variable is not. `<var>`
states that the text names a variable of a program or an expression; the font does not establish
that, and the same font sets constants, function names, relations and punctuation. `<i>` states
that the text is set apart typographically, which is exactly and only what the resource shows.

**Which characters.** Only a name states maths italic (`cmmi`/`cmmib`, `mathmi`, a `newtx`/`ntx`/
`tx`/`zx` prefix with `mi`/`bmi`; #133's `nameSlope`): the descriptor cannot tell a variable face
from a text italic, since Wallace's `CMMI12` reports `ItalicAngle` 0 and Flags 34, like its text
italic `ItalicRegular12pt`. A show of such a font needs an element only where its decoded text
holds a letter that does not already slope. Unicode's Mathematical Alphanumeric Symbols
(U+1D400–U+1D7FF) and the Letterlike Symbols that fill that block's holes (U+2100–U+214F: the
italic `h` is U+210E) state the slope in the character, so newtx's `RepCl` (𝑅𝑒𝑝𝐶𝑙) and `hlc`
(ℎ𝑙𝑐) gain nothing. A show without a letter is a relation or the punctuation inside a compound
name (`t.j.k`, `=`, `,`, `<`), which is upright notation. A maths italic line whose shows do not
spell it is left unmarked for the same reason. What remains is a maths italic that draws a
variable as a plain letter: TeX's Computer Modern.

**Measuring the run.** A maths font marks part of what PDFKit reports as one run — Wallace's `8x`
is `8` in CMR and `x` in CMMI — and `enumerateAttributes` returns a new run wherever any attribute
changes. Every baseline and script rule reads a run's neighbours, so `inlineText` rejoins two
attributed runs whose attributes are equal but for the maths italic mark, measures the line as
PDFKit read it, and writes the pieces apart only once the line's styles are known. `StyledRun`
keeps the pieces in `parts`. The marker and display-initial exemptions #133 defined for bold and
italic apply to the whole run.

**Nesting.** `EPUBTextEncoder` writes runs as nested elements: at each style, in the order
`sup`/`sub`, `strong`, `em`, `i`, every adjacent run that carries it becomes one element holding
the rest. One run's markup is unchanged, so `<sup>` still encloses `<strong>`, which encloses
`<em>`. A run raised and lowered at once is raised, as before.

**Joining spaces.** In `coalesced`, a run of whitespace between two text runs takes the bold,
italic and maths italic both of them carry. A space is invisible in each, so adopting them only
removes an element boundary. It takes nothing that an element outside it would still divide
(`<sup>a</sup> <sup>b</sup>` stays two elements: raising the space would move it), and nothing at
all where the runs share none. A note's text after its printed number is now written with the
rest of the note, so a style it shares with what follows is one element.

`InlineText` gains one style bit. There is no public API or default change.

### Narrowed during measurement

- **Already-sloped characters** (above). The first lane marked every maths italic show, which
  gave arXiv 11 changed pages of `<i>` around characters that already slope and around relations:
  `<i>𝑚𝑥 </i>`, `<i>.</i>`, `<i>= </i>`, `<i>ℎ𝑙𝑐.𝑒 </i>`. With the narrowing arXiv gains no `<i>`
  at all and its 5 changed pages are joins.
- **Rejoining a split run** (above). The second lane left 14 Wallace pages structural, each
  gaining a subscript the baseline did not write: page 23's `<p>8x<sup>2</sup></p>` became
  `<p><sub>8<i>x</i></sub><sup>2</sup></p>`, and pages 184, 193, 197–199, 202–203, 209, 224,
  227, 229, 395 and 397 the same way on display lines. Rejoining the run removes all 14.
- **Maths italic on an undecoded line** (above). Marking a whole line whose shows do not spell it
  cannot tell its variables from the relations the same font sets, so it is not marked.

## Lanes

`tools/case.py <case>` (with `MATH_ITALIC_WORK=<scratch>`) runs `tools/run_corpus_regressions.py`
for base and cand with the probe, then `tools/compare_conversion_runs.py
--allow-different-converters`. `tools/classify.py` reads each changed page's markup as a stream of
characters, each carrying the set of inline elements enclosing it, and sorts the page into
**bracket-only** (the same characters carry the same styles, written with different elements),
**math-italic** (the same as the baseline once `<i>` is dropped) and **structural**. Emphasis on a
space is not counted a difference: it is invisible, and a joining space now takes the style around
it. Every lane passed its gates (EPUBCheck, content contract, memory, progress, source identity)
in both binaries. No image, report field, page marker, OCR page or navigation entry changed in any
case.

| Case | Changed pages | Bracket-only | Maths italic | Structural |
| --- | --- | --- | --- | --- |
| noaa-nca5-2023 | 719 | 719 | 0 | 0 |
| wallace-algebra-2010 | 257 | 22 | 235 | 0 |
| faa-phak-8083-25c | 129 | 129 | 0 | 0 |
| gpo-911-2004 | 84 | 84 | 0 | 0 |
| fed-explained-2021 | 45 | 45 | 0 | 0 |
| scotus-loper-bright-2024 | 40 | 40 | 0 | 0 |
| gpo-our-flag-2003 | 15 | 15 | 0 | 0 |
| ntrs-20180003024-earthdata-slides-2018 | 10 | 10 | 0 | 0 |
| ntrs-20200002975-gwl-2020 | 7 | 7 | 0 | 0 |
| arxiv-replay-clocks-2023 | 5 | 5 | 0 | 0 |
| cdc-zombie-pandemic-2011 | 5 | 5 | 0 | 0 |
| usda-ars-agresearch-2012-11 | 5 | 5 | 0 | 0 |
| uscourts-pro-se-1-2016 | 3 | 3 | 0 | 0 |
| census-rrs2002-01 | 2 | 2 | 0 | 0 |
| dga-2025-2030 | 2 | 2 | 0 | 0 |
| ntrs-20210020887-techport-thm-2021 | 1 | 1 | 0 | 0 |
| cia-blue-book-14-1955, nbs-jres-geltman-1977, ntrs-20190030725-dasc-2019, usgs-mcs2025-copper | 0 | 0 | 0 | 0 |

Every English case with a reviewed contract was converted in both binaries. The CIA Blue Book
changes nothing although #133's survey counts 86,465 italic runs in it: no page of it holds two
adjacent elements to nest or a styled join to close. Not converted: `gpo-warren-1964`, whose
only fonts are OCR `Courier` and hidden text with no style (#133's survey: 0 styled runs), and
which the contract excludes from full conversions at the default image-output ceiling (#5). No run
of that book carries a style, and with every style empty both the nesting and the joining rules
write the bytes the baseline wrote. The Arabic and Chinese cases are outside this work.

### Review

Every changed page's class was taken from the classifier, and pages of each class were read.

- **Joins (every case).** Headings and paragraphs split at a source line break become one element:
  the Fed's chapter titles (`<strong>Overview of the Federal</strong> <strong>Reserve System</strong>`
  on page 8, and 12, 14, 20, 66, 90, 116), its chapter summaries (24) and the Bagehot sidebar
  (58); 9/11's contents entries (5), run-in heads (362), recommendations (395) and the notes'
  book titles (`<em>Washington</em> <em>Post</em>` on 480); the Supreme Court's case names
  (`<em>Natural Resources Defense Council,</em> <em>Inc.</em>` on page 1, and 17); FAA contents
  entries (15) and figure captions (164); Our Flag's resolution (7), attributions (4) and
  bibliography (53); the DGA's headings (5) and its Secretary's letter (2); NOAA's poem credit
  (5) and its cover-art credits (1700); the USDA magazine's cover lines (1); Census's title (1);
  the Pro Se form's italic instructions (1, 3); the NASA paper's title and its references' venues
  (1, 19); the Earthdata deck's stacked labels (12); and Wallace's exercise instructions (105,
  380).
- **Nesting.** CDC page 22's comic lettering (`<strong>yes, th is is <em>Dr. KHAN.</em> no, TELL
  <em>CNN</em>…</strong>`), and the same on 1, 4, 35 and 39. The Supreme Court's pages 86 and 87,
  which #133 left structural because an empty `<sup></sup>` sat beside the next one, are
  bracket-only here.
- **Wallace's variables.** 4,092 `<i>` spans over 235 pages, in 127 distinct forms: `x` (1,470),
  `y` (389), `n` (331), `a` (326), `b` (269), `m`, `i`, `v`, `r`, `p`, `k`, `xy`, `ab`, `mn`,
  `uv`, and a few carrying the comma between two variables (`x,`, `, y`, `a, b, c`). Page 23
  reads `5<i>x</i>− 2<i>y</i>− 8<i>x </i>+7<i>y</i>`, page 255 `12<i>a</i><sup>2</sup><i>b</i>`
  `<sup>3</sup><i>c</i>`. No variable gained `<em>`, and no text italic (`The Elements`, `Check:`)
  gained `<i>`. The 22 bracket-only Wallace pages are joins in the exercise instructions.
- **Source artefacts seen, not introduced.** Page 380 reads `Make <i>a </i>table of values`: the
  source draws that `a` in CMMI, so it is sloped on the page and the element is faithful to it.
  One span on a Wallace inequality line reads `<i>&lt; x &lt;</i>`, where the relations fall
  inside the marked run under #133's rule that whitespace and punctuation follow PDFKit's run.

### Cost

No separate cost run was made. Each lane's own wall time (one conversion plus EPUBCheck and the
content checks, on a machine shared with other agents) is the only figure available, and the
candidate is within run-to-run variation of the baseline on every case: NOAA 132 s → 127 s,
CIA Blue Book 51 s → 50 s, FAA 53 s → 55 s, Wallace 34 s → 31 s, 9/11 16 s → 16 s, CDC 41 s →
42 s. The added work is one extra style bit, a rejoin of attributed runs that differ only in it,
and a grouping pass over each block's runs in the writer.

## Tests

`swift test`: 858 tests, 8 more than `70fc9b4`'s 850, no known-issue wrappers.

`Tests/PDFReflowLibTests/NestedStyleEncodingTests.swift` (4 new tests) covers the encoder:
nesting to three levels with controls (styles sharing nothing, a run raised and lowered at once,
a page boundary, a note reference, XML escaping); a joining space with controls (runs sharing
nothing, a space carrying text, an edge space, a raised pair, a space beside a page boundary);
`<i>` for maths italic with `<em>` beside it as the control; and a note's backlink, a table cell
and a block payload nesting the same way.

`Tests/PDFReflowLibTests/FontWeightDetectionTests.swift` (4 new tests, 4 changed):

- **Classification.** Eight maths italic names are named apart from ten controls (text italic,
  upright, symbolic, script, an unstated name, no name). `slopeNeedsMarkup` accepts `x`, `xy` and
  a plain Greek letter and refuses `RepCl`, `hlc`, `.𝑗.𝑘`, `= `, `,`, an undecoded show and an
  upright font.
- **Synthetic reproducers.** A `CMMI12` show reads maths italic and a text italic beside it reads
  `<em>`, with PDFKit's substituted names asserted not italic; the equation writes
  `5<i>x</i>- 2<i>y</i>` and the label `<em>Check:</em>`. A line whose maths shows do not decode
  is unmarked. A run the mark splits is measured whole (`8<i>x</i>2` on a lowered display line,
  no `<sub>`), with a genuine raised `2` as the control.
- **Page gate.** `readerFindsNoEvidenceOnPagesWithoutAStyledFont` (renamed) now uses `CMSY10` as
  the negative control and adds maths italic as a positive one, since a page whose only styled
  font sets variables is now scanned.
- **Source fixtures.** `algebra-23-styles` (recaptured; runs now record `"mathItalic"`) carries
  the slope on `5x− 2y− 8x +7y` and no `<em>` anywhere, with a `fontWeights: false` negative
  control; `arxiv-1-styles` carries none, and its variables are asserted to be Mathematical
  Alphanumeric Symbols.

`PreformattedStyleTests`' spine-budget test now alternates two styles that share nothing, since a
run nested inside the style beside it joins that element.

**Mutation checks** (`swift test` with one part disabled). Each part fails at least one test:

| Part disabled | Failing tests |
| --- | --- |
| maths italic written `<i>` | 6 |
| maths italic in `inlineText` | 3 |
| nesting in the encoder | 5 |
| joining space rule | 1 |
| already-sloped narrowing | 1 |
| run rejoin before measuring | 1 |

**Contract.** `corpus/regressions.json` gains one Wallace page (23, which had no entry): its two
equation lines, the exponent `<sup>2</sup>` of `8x2`, and `absentScripts` refusing a lowered `8x`
or `5x` — the subscripts the second lane wrote before the run rejoin. Both binaries satisfy it.

**Also changed:** `SourceLayoutFixture` replays `mathItalic` and `tools/capture-layout-fixture.swift`
records it; `doc/architecture.md` and `doc/regression-testing.md` describe the rule and the tests.

## Commands

```sh
swift build && swift build -c release
swift test                               # 858 tests passed (850 at 70fc9b4 + 8)
scripts/check-all.sh --fast              # passed: 858 Swift, 242 Python, 8/8 concurrency processes
python3 tools/update_doc_counts.py
measurements/font-style-detection/tools/capture.sh <capture-layout-fixture binary>
MATH_ITALIC_WORK=<scratch> python3 measurements/math-italic-and-nesting/tools/case.py <case>
python3 measurements/math-italic-and-nesting/tools/classify.py <scratch>/review/base-<case>.epub \
  <scratch>/review/cand-<case>.epub [--spans]
```

## Limitations and defects to file

1. **arXiv's variables carry no element.** They already slope as Mathematical Alphanumeric
   Symbols, which is the right answer for a reading system, but it means the corpus exercises the
   `<i>` path in one book only (Wallace). Census's `cmmi10084` (393 shows) would be the second,
   and its `dc` fonts still do not decode (#133's defect 3), so its lines never resolve.
2. **No contract field states inline emphasis.** `corpus/regressions.json` can assert text,
   headings, scripts and tables, but not that a phrase is one `<strong>` or that a variable is
   `<i>`. The nesting and joining changes are therefore pinned by Swift tests and by the lane
   comparison, not by a contract; only the subscript they nearly caused is contracted.
3. **The classifier treats emphasis on a space as no difference.** A change that moved bold or
   italic on and off a space alone would be classed bracket-only. That is the class this work
   creates, and a `<sup>`/`<sub>` move is still a difference, but the tool is not a general
   styling comparison.
4. **The already-sloped narrowing is pinned only by unit tests.** A source fixture replays the
   recorded `mathItalic` field rather than the rule, so recapturing is what would carry a change
   in the rule into `arxiv-1-styles`.
5. **The descriptor is never consulted for maths italic.** A maths italic font whose name states
   nothing would be read as a text italic by #133's descriptor rule. No corpus font is in that
   position.
6. **Pre-existing:** Wallace page 255 still lowers `6a2b` as a subscript in its LCD line (#133's
   defect 6), which its contract's `absentScripts` already records; this work does not touch it.
