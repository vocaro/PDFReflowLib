# Stacked indices, display crops and delimiter pieces in the IEEEtran paper (#163)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 (26A428) arm64, release CLIs,
shared host with other agents' work. Baseline `07c1bbd` (the coordination branch's head);
candidate is this tree on it.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `07c1bbd` | `53d64abd256ec2c6e1f0b2f39d7d005fd6a08448a4990590b4a65f5507e75d24` |
| candidate | this tree on `07c1bbd` | `a86d2f3cf509e32019bf7a6bd12cbef1637fe1d36f13f6928e1182a5fa9d3def` |

No source PDF, EPUB or raster is committed. One fixture, `dasc-3`, was captured with
`tools/capture-layout-fixture.swift` built from the **baseline** tree, so it records PDFKit's
lines before this change, as the existing `dasc-2`, `-5`, `-6` and `-9` fixtures do.

## What was wrong

Geometry is PDF points, bottom-left origin, read from the fixtures and `mutool draw -F stext`.

**1. A symbol with stacked indices cut its sentence into one-token paragraphs.** TeX draws
`STA^{n^i_h}_h` as base, superscript `n`, nested `i`, then moves back for the nested `h` and again
for the outer `h`. PDFKit ends a selection at each backward move. Page 5's `Step 2. For each STAni`
(x 312.0–407.6) is followed by a 4.98-point `h` alone (x 404.9) and `h occurring in the computed
schedules` (x 400.0, opening with a 6.97-point subscript), and every piece opened a paragraph: the
step and display (8) came out as 20 paragraphs. Two measurement defects made it worse:

- The superscript of a symbol that also has a subscript is raised further: page 5's `n` is 6.97
  points raised 5.42, past three quarters of its own size (5.23), so it was no script and the stack
  had no trailing script to find. A fraction's numerator is raised as far (Wallace page 95's 8-point
  `rise` 6.24 over 12-point text), which is why the limit was the script's own size.
- PDFKit can take a selection's baseline from the script: page 2's `f ni+1` measures its 9.96-point
  `n` 4.26 points down and `i+1` at zero, so `f` read as nothing and `n` as a subscript.

**2. Displays were partly crops, partly text.** Formula seeds are lines with a relation sign or an
equals sign. A cases brace, its conditions (`at the first node`, `if n has been schedule-frozen`),
its case labels `(a)`–`(c)` and the equation number `(4)` carry none, so display (4) was three
crops with 14 paragraphs between them. Display (2) (`tt … , TT … . (2)`) and (8) carry no sign at
all and had no crop; (8)'s interval brackets are `CMEX10` glyphs with no character (mutool reports
U+FFFD at x 388.2 and 511.3), so as text it lost them. PDFKit still counts such a glyph in the
rectangle of the prose line above the display: `occurs on the route of f, compute the time window`
is 22.5 points tall (597.8–620.3) at 9.96 points over a baseline of 613.36, so any crop of the
display takes that line. Displays (7) and (9), already crops on the baseline, took theirs.

**3. CMEX brace and bracket pieces reached the text.** #155 decodes them to U+23AA etc.; the 146
pieces of pages 3 and 9 were lines of their own (`⎫ ⎪⎪⎪⎪⎬ ⎪⎪⎪⎪⎭`, 57 points tall at 9.96 points)
that no crop held.

**4. The table crop.** On `07c1bbd` the page-6 separation-matrix crop is already the table alone
(303 × 159 px) and both prose lines are text; #158's crop capture fixed it. It is now pinned.

## Change

`NativeTextReader.swift` (extraction) and `LayoutReconstructor.swift` (crops).

- **`joiningStackedScripts`**, the last step of `NativeTextReader.lines`. A piece opening with a
  script smaller than the base's type, on the base's row, that starts under the base's trailing
  scripts (at most ¾ of the base size a character, plus 1.5 points) or at most ¼ of the base size
  past its end, continues the base; a subscript may open it after a base without scripts (page 2's
  `(ETA): ETA`, whose superscript PDFKit also split off). So does a one- or two-character closing
  punctuation piece after a script (page 5's `latter choice of Tk` / `.`), and a stack's last
  scripts alone at a line's end (`reach ni+1` / `f`). Short script-sized pieces over the stack join
  between them, raised or lowered by their middle against the band base and continuation share,
  flattened to one level. Each base takes its leftmost continuation, so a nested piece
  (`f ,j` at x 541.7) is not mistaken for the continuation (`f.` at x 536.7). A painted bar across
  the stack makes it a fraction (Wallace's `rise`/`run`, `a5`/`a2`, `4x2`/`4x2`), left alone.
- **Script reach** (`inlineText`). A script clearly smaller than the line's type, touching its base
  or continuing a script before it on that script's own baseline, is measured on the line's type
  (¾ of 9.96 = 7.47 ≥ 5.42); a script touching another script is measured from it (`i`: 8.43 − 5.42
  = 3.01); a carrier clearly smaller than the line's type is a script, not a #144 base (`(k),j` 5.46
  up with its nested `k`). Not on a line a painted bar crosses (`measuresScriptsOnLineType`), where
  the old reading stands.
- **Rebased selections** (`shiftedBaselines`). Where every run of the largest size stands on one
  shifted baseline (within ¾ of its size) and a run 0.4–0.9 of that size, of at most twelve
  characters in two words, follows a letter or digit of one of them with no space, on the
  selection's baseline, every run is measured from the larger runs' baseline. Controls kept: the
  Fed's regulation letter and name, `V`/`SO`, and the 9/11 note markers after a closing quote.
- **`delimitedDisplays`** seeds a crop for each delimiter column (three or more U+239B–U+23AD
  pieces and nothing but spaces, punctuation or an equation number, at least twice its type tall)
  with every line of its text column whose middle it spans (0.6 of its size of slack below, where
  PDFKit's substitute metrics fall short), except running text.
- **`isScriptDisplay`** seeds a formula for a non-prose row carrying scripts that ends with its
  equation number on the right edge of the column's full lines, or opens with an operator sign and
  carries a stacked index (sup directly beside sub). Wallace's worked steps (`− 3x + 7 − 2x² …`)
  carry no stacked index and stay text; `S(1), …, S(f−1) (6)` carries no script and stays text.
- **`isTextNeighbour`**: a words-only row over a formula is its label only when it carries no script
  and no piece within four body sizes shares its row. Page 9's `the Quadratic Program` shares its
  row only with `hT = …` 178 points across the gutter; page 6's `ETA^{next node}` is a display row.
  A row running on in lower case, four words or more, with no term, number or operator, is its
  sentence's wrapped line (`route of f, compute the time window` over display (7)).
- **`trimmingUndrawnExtents`** (extraction, before the join). A plain prose line more than 1.6 ems
  tall is brought back to its first show's baseline (−0.3 em, or +1 em above) where it reaches more
  than half an em below it over a characterless glyph of TeX's maths extension font
  (`FontWeightReader.isMathExtension`: `CMEX10`, `LMMathExtension10`) within its width, and into a
  piece of a numbered display. `FontWeightReader.relevant` keeps `read`'s own filter; extraction
  reads the unfiltered shows once and passes the relevant ones on as before.
- **Crop expansion** may cut away the sliver of a delimiter column that reaches less than a point
  into the height of a prose line no other kept line touches: display (5)'s brace ends 0.04 points
  into `each of the nodes in the same order.2`.

Tried and dropped, each for its Wallace page diff: trimming any prose line to its opening show's
baseline (21 pages; rows PDFKit joins through radical glyphs split, pages 20, 34 and 288), then any
line over a `CMEX10` glyph with another line beneath (23 more pages, and PDFKit's rectangles there
are what carries radical displays such as page 293's into a crop: those came out as broken text);
operator-led rows without a stacked index (42 pages of worked steps became crops); growing a formula
seed along its row (pages 160 and 393 lost their `Evaluate f at − 3` annotations); and cutting any
kept line's sub-point sliver from a prose line (the same radical displays of pages 293, 316 and 410
came out as text). Returning `FontWeightReader.read`'s shows on every page that uses `CMEX10`
changed the styling of 18 Wallace pages and was replaced by `relevant`.

## Results

IEEEtran paper, baseline → candidate: 292 → 132 paragraphs, 4 → 1 `<pre>`, 146 → 0 delimiter
pieces in text, 28 → 28 crops (displays (1)–(5) and (7)–(12) each one crop with their braces,
conditions, labels and numbers, and the sentence line over each of (7)–(10) left in its step; the
page-9 objective, P, q, G and h cropped whole). The 66 new contract checks (313 in all) fail 43
times on the baseline and pass on the candidate.

Page diffs against the baseline, full conversions (EPUBs deleted after diffing):

- Wallace, 18 pages: `x2` → `x<sup>2</sup>` where PDFKit measured the selection on the exponent
  (177, 192, 201, 222–224, 229–231, 397), paragraphs no longer split after an exponent (226, 240,
  406, 407), two adjacent display crops merged (43, 321), a row label kept as text (383), and page
  407's `axay = ax+y` sentence whole instead of half in a crop. No two superscripts merge: an
  earlier candidate read page 178's `(a²)³` as `a<sup>2 3</sup>`, taking the outer `3` (7.44 points
  up) as a continuation of `2` (4.32 up); a script continues only a script on its own baseline, so
  it reads `a<sup>2 </sup>3` as on the baseline, and the 18 pages were re-read for any other merge.
- IEEEtran paper page 8: `step V 3 .` → `step V 3.` (closing punctuation after a script).
- FAA page 298: the `Given:` over a formula is text again (its row shares a height only with the
  other column).
- NBS page 1: `subject to the initial condition` is text again beside its crop.
- Unchanged: Replay Clocks, the NASA Word paper, USGS, Loper Bright, Pro Se 1, the magazine,
  Earthdata slides, TechPort, DGA, Our Flag, The Fed, 9/11 and Census.

All 20 gated cases pass `run_corpus_regressions.py` on the listed binary (Warren is not covered).
`swift test` passes 1,011 tests; the Python tool tests pass.

## Not fixed

- A nested index reads as one level: `STA<sup>nih</sup><sub>h</sub>` for STA^{n^i_h}_h. A run
  carries one script style; nesting needs a style and encoder change.
- Page 9: `−→x min,` stands 12.6 points beside the crop of ½xᵀPx + qᵀx and stays text, and that
  crop takes `the form` (PDFKit reads it with the fraction's numerator); the line holding
  `(a_k, ā_k)` is still cropped as text because its overbars seed a crop.
- Page 6 opens with a stray `3` before `some time within window`.
