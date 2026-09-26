# DASC pages 5, 6 and 9: nested scripts, display crops, painted accents and a stray 3 (#302)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Subject: DASC (Sadovsky and Windhorst, DASC 2019), `corpus/cache/20190030725.pdf`, SHA-256
`7c2137098ffb75153e0049b970272db97bc91e13168028dc7b53fbe2deb92caa`. It is cached but is not a
corpus case, so this record is what pins it.
Build: `main` at `2bff36c6` with this change, Xcode 27.0 (27A266a), macOS 27.0 (Darwin 27.0.0).
Baseline: `2bff36c6` alone.
Command: `swift build -c release --product pdf-reflow`, then
`.build/release/pdf-reflow corpus/cache/20190030725.pdf out.epub --no-ocr` with each binary.
Source pages were rendered with `pdftoppm -r 100` and `-r 200` (the page 6 corner at 400 DPI);
glyph positions come from `mutool draw -F stext` and from `GlyphPlacementReader`; the lines,
graphics and crops of a page come from a Swift Testing probe calling `PageReader.read`,
`GraphicsReader.read` and `LayoutReconstructor.graphicsWithLabels` (not committed).

Items 2–4 were measured at `2bff36c6` with the change that became `e792a282`; item 1 was measured
last, on the tree that holds every change it needed (below).

## Item 1: nested script levels

54213607 taught `NativeTextReader` to set the nested flags, but DASC's `STA^{n^i_h}_h` still read
flat. Two things stood in the way. PDFKit split the row into three lines (#303), and it measured
`STA` and `n` from a line reference that was not their baseline, which left the outer `n` past the
own-size limit (#304). a0e8aeac measures scripts from the text they are set against and admits a
TeX superscript raised over its own stack. f49e2206 rejoins the row's pieces before the line is
read.

On `f49e2206` (which also holds a0e8aeac, 5de69c27 and e792a282), with the command above, DASC
reads:

- page 5, Step 2: `For each STA<sup>n<sup>i</sup><sub>h</sub></sup><sub>h </sub>occurring in the
  computed schedules`, both levels nested as printed (the space inside the last `<sub>` is
  PDFKit's own run);
- page 5, the time windows: `A<sup>n<sup>i</sup><sub>f </sub>,j</sup> <sub>f </sub>satisfy all the
  constraints`;
- page 9: `(a̱<sub>k</sub>,ā<sub>k</sub>) the time window available to flight f`, and `problem (12)
  has the form` followed by the display's crop (items 2 and 3, unchanged by the later commits).

The issue's other open question, whether Wallace page 178's `(a²)³` still read `a<sup>2 </sup>3`,
is settled by 5de69c27. It restores the tall parentheses and reads `(a<sup>2</sup>)<sup>3</sup>`,
pinned in the `wallace-algebra-2010` contract.

## Item 2: the display `½xᵀPx + qᵀx ⟶ₓ min, Gᵀx ≤ h`

Page 9 ends a sentence `Letting x = [s₁ s₂ … s_N]ᵀ, we see that problem (12) has the form` and
sets the display to the right of `the form`. Two things kept the crop from holding the display and
nothing else:

- The ½'s numerator shares the row of `the form`, and PDFKit returns them as one line,
  `the form 1` (x 311.98–384.33): `the form` ends at 347.01 and the `1`, at 6.97 points on the
  baseline 461.33 against the words' 465.94, starts at 380.36, 3.35 ems on. The ½'s bar and the
  `≤` of `Gᵀx ≤ h` seed the crop; no cut clears that line, and it does not read as a sentence
  (two words), so the crop admitted it and `the form` went into the picture. 840ec235's rule
  (a crop never admits the book's own prose) does not reach a two-word line.
- The display sets `⟶ₓ min,` a quad (12.73 points) right of `½xᵀPx + qᵀx`. PDFKit reads it as a
  separate line, and a crop admits another piece of a row only where its rectangle reaches it.

| | before | after |
| --- | --- | --- |
| text | `…we see that problem (12) has` / `−→<sub>x </sub>min,` | `…we see that problem (12) has the form` |
| crop | `the form ½xᵀPx + qᵀx` over `Gᵀx ≤ h` | `½xᵀPx + qᵀx ⟶ₓ min,` over `Gᵀx ≤ h` |

`DisplayTermSplit` now splits `the form 1` into `the form` and `1` from the glyphs'
placement, and a piece of an admitted row that opens with an arrow within two body sizes joins
the crop. The split is made on this one line in the cached corpus: across the 24 corpus books, DASC
and two other cached papers (`20200002975`, `complaint_for_a_civil_case`), 5,875 pages,
`GlyphPlacementReader` places 1,632 and no other line breaks that way.

**A broader join was measured and rejected.** Admitting a piece that opens with any relation,
`=` included, left the arXiv paper byte-identical but moved Wallace: the book sets `=` as a line
of its own between two fractions, each its own crop read as MathML, and joining it carried one
crop into the next. Sixteen expressions then read as eight whole equations (page 12's
`(36 ÷ 4)/(84 ÷ 4) = 9/21`, page 365's `1/3 + 1/x = 5/12`), but where the two together were no
longer one proven row twenty more went into pictures (page 256's exercises 1–10 among them), and
five worked steps' annotations with them (`Same problem, with common denominator 6` on page 43,
`Multiply each term by LCD, 12` on 274, two on 277, `Using reciprocals to make equation,` on
367). Only an arrow with a term after it joins.

## Item 3: overbars and underbars

The time window's two ends are `(a̱ₖ, āₖ)`: 0.4-point rules exactly the italic `a`'s advance wide
(5.27 points), 1.39 points below and 5.69 points above the baseline 255.37. At 9.27 by 4 points
once `GraphicsReader` pads them, they are not thin rules, so each seeded a crop. In the sentence
neither crop could take a line (840ec235 keeps the sentence out), so each was preserved alone, a
23-by-10-pixel sliver, set between the sentence's lines.

| | before | after |
| --- | --- | --- |
| sentence | `[sliver]` `node nto the next node on route, and (a<sub>k</sub>,a<sub>k</sub>) the time window` `[sliver]` `available to flight f at node n; these are the time windows (11),` | `node nto the next node on route, and (a̱<sub>k</sub>,ā<sub>k</sub>) the time window available to flight f at node n; these are the time windows (11),` |
| crops on the page | 12 | 10 |

`PaintedAccents` reads a bar as an accent where exactly one placed glyph spans it and nothing
stands on its other side within a numerator's or a denominator's reach. On page 9 it reads twelve
bars and marks ten lines' characters: both in the sentence, both in the display
`(a̱ₖ, āₖ) = A^{n^k_f, j_k}_f` and all six in `hᵀ = [ā₁ ā₂ … ā_N −a̱₁ −a̱₂ … −a̱_N]`. The two in display
(12)'s constraints stand where PDFKit's lines overlap (the glyph's middle lies in two lines), so
they stay graphics inside that display's crop, as before. The overline is written as U+0304
COMBINING MACRON after the letter and the underline as U+0331 COMBINING MACRON BELOW; the writer
passes both through and `EnglishText` counts `ā` as a letter. A crop whose text holds a mark is
not read as MathML: `MathRecognizer.explains` requires the crop's characters to be exactly its
glyphs', and `ā` is not `a`.

Negative controls, measured on the same stack: on the pages `GlyphPlacementReader` places, no
bar of Wallace (469 of its 489 pages), the arXiv paper (11 of 12), the Census paper (10 of 20) or
any other cached book is read as an accent; the NBS paper's seven pages are not placed at all, so
it reads none. On Wallace page 12 (36/84) each fraction bar has a term on each side, and on page
300 each vinculum over one digit has the radical sign at its left end, its baseline within 0.02 em
of the bar.

Still open on page 9, filed from this measurement: the display's crop takes `with` and the
sentence `Let N = N_f be the length of the route.` (#312), and the matrices `P` and `q` have no
crop and read as scattered text (#313).

## Item 4: the `3` that opens page 6

Page 6 prints it. Its content stream sets the column's first line as
`/F72 9.9626 Tf 82.618 731.679 Td [(3some)-478(time)-478(within)-478(windo)25(w)]TJ`: the `3` is
the first glyph of the same string as `some`, in the body font (NimbusRomNo9L-Regu) at the body
size, on the body baseline. A 400 DPI render shows `3some time within window`. Page 5 ends
`and reach n^{i+1}_f`, and its foot carries no footnote, page number or script that could have
been carried over. The stray digit is the source's own, an authoring slip; the library reads what
the page prints, so there is nothing to fix. The reading of page 5's last line, `f` and `i+1`
split apart around the page boundary, is #303's.

## Everything else

- DASC: pages 1–8 and 10 convert as before; every difference is on page 9, as above.
- `wallace-algebra-2010` and `arxiv-replay-clocks-2023`, converted whole with both binaries
  (`--package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`): byte
  identical by `tools/epub_identity.py`, Wallace's conversion report included.
- Corpus lane on `wallace-algebra-2010`, `arxiv-replay-clocks-2023`, `nbs-jres-geltman-1977` and
  `census-rrs2002-01`: `runPassed` true and no content-assessment errors on each.
- `GlyphPlacementReader` walks each page it reads once more; over the survey above the walk took
  about a millisecond a page (0.55 seconds over the 9/11 report's 585 pages).

## Page 9's time-window display takes `with` and the sentence after it (#312)

Build: `main` at `af18cfb9` with this change; baseline `af18cfb9` alone. Same host, Xcode 27.0
(27A266a), macOS 27.0 (26A428). Each binary converted DASC, Wallace
(`Beginning_and_Intermediate_Algebra.pdf`, SHA-256 `856bd81e…`), the arXiv paper
(`2311.07842v1.pdf`, `1e8172e4…`), Geltman (`jresv82n3p173_A1b.pdf`, `44653967…`) and Census
(`rrs2002-01.pdf`, `0f97380a…`) with
`--no-ocr --package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`; the
pairs were compared with `tools/epub_identity.py` (conversion reports included), then page by
page with each image named by its content's SHA-256, and every changed page was checked against
`pdftoppm -r 150`. The rule's alternatives were measured with a Swift Testing probe (not
committed) that reads every page with `PageReader.read` and lists each line whose `takes` changes
when `LayoutReconstructor.graphicsWithLabels` runs with a variant, over the same 27 cached PDFs
(5,875 pages) as item 2's survey, all read as English.

### How `main` read the page

The page prints `…these are the time windows (11),` / `with` / the display
`(a̱ₖ, āₖ) = A^{n^k_f, j_k}_f.` / `Let N = N_f be the length of the route.` / an indented
`The problem of scheduling flight f can then be written as`. The sentence states an equation in
eight words (#57's rule allows twelve), so it seeds a crop, x 44.96–216.12, y 188.94–214.70; the
display seeds x 132.51–216.48, y 206.11–239.32. The issue read the two seeds as clustered. They are
not: `with` belongs to the four-line paragraph above it, which `TextBackdrop.paragraphs` protects,
so `clustersKeepingText` keeps them apart. The sentence's crop took the rest by itself. Its
margin reaches 0.59 point into the display's line (y 214.11–231.32), so no cut clears the display
while keeping the seed, and the display is admitted; the display's line reaches 2.01 points into
that of `with` (y 229.31–238.22), so no cut clears `with`, and a one-word line is not the book's
prose (#255), so it is admitted too. The two regions then overlap and merge into one crop,
x 44.96–216.48, y 188.94–240.22.

### Should a sentence that states a relation seed a crop?

Not a whole sentence. Each variant stops a formula line from seeding when it matches:

| variant | DASC | Wallace | arXiv | Geltman, Census | the other 22 PDFs |
| --- | --- | --- | --- | --- | --- |
| reads as prose by #255's test (`releasesProse`) | p. 9 fixed; p. 2's three prose lines released; p. 6's display released | 79 pages, 175 lines released | 7 pages, 32 lines released, among them the numbered lines of the algorithm listings on pages 4 and 5 | none | not run |
| the above, opening with a capital and ending in `.` | p. 9 fixed | p. 112 | two captions released, p. 12's two crops become four | none | not run |
| four words of two letters, nothing else | p. 9's display released as well | 84 pages | 7 pages | none | not run |
| **a whole sentence (the rule)** | **p. 9 fixed** | **p. 112** | **none** | **none** | **none** |
| the rule, with words on both sides of the relation | p. 9 fixed | none | none | none | none |
| the rule, ending in `.`, `?` or `!` | p. 9 fixed | p. 112, and a crop on p. 280 moves | none | not run | FAA handbook: none; the rest not run |

The rule reads a whole sentence of the book's prose: a line that opens with a capitalised English
word of two letters or more, ends with a full stop, has #255's shape (four words of two letters)
and reads as English words (`EnglishText.readsAsWords`), in a book that declares English. It
applies to both formula tests, the relation and the symbols `∫∑∏√∂∇≈≠≤≥∞`; over the 27 PDFs the
two readings change the same lines. The opening word is what keeps Wallace's worked steps, which
set an equation and its annotation as one line (`5x = 25 Divide both sides by 5`). English words,
not #255's shape alone, keep the arXiv paper's lines of mathematical italic, which `releasesProse`
judges on shape because `EnglishText.foreignLetters` counts `𝑡` as another script's letter.

The narrower reading, words on both sides of the relation, changes DASC alone; it was not taken
because it leaves Wallace page 112's `Find the slope of a line parallel to 5y − 2x = 7.`, as much a
whole sentence as DASC's, seeding a crop that pictures the example's first two rows twice.

### May the union of two seeds take a line neither takes?

Yes, unless the line belongs to a paragraph of the book's prose, as `clustersKeepingText` already
provides. On `af18cfb9`, 407 of Wallace's lines on 137 pages are taken by a union of seeds and
reached by none of its seeds; 168 of them hold four words of two letters, the annotations of
worked steps (`Our solution for x` beside the row `x = 13` on page 74). DASC has 44, on page 2 (the
scripts of `STA^n_f`) and page 8 (Table II, whose ruled cells are one crop only through the union
of its rules). The arXiv paper, Geltman and Census have none. Keeping every line no seed reaches
out of the union, in `clustersKeepingText` and in the merge after each expansion, changed 98 of
Wallace's pages (207 lines released, one newly taken), broke DASC's Table II into eleven crops with
its 47 lines released as text, and left DASC page 9 as it was, since its crop reaches `with`
through the display's line, not through a union.

### Before and after

DASC page 9:

| | before | after |
| --- | --- | --- |
| text | `…these are the time windows (11),` / `The problem of scheduling flight f can then be written as the Quadratic Program` | `…these are the time windows (11), with` / `Let N= N<sub>f </sub>be the length of the route. The problem of scheduling flight f can then be written as the Quadratic Program` |
| crop | x 44.96–216.48, y 188.94–240.22: `with`, the display and the sentence | x 132.51–216.48, y 206.11–239.32: the display |

Wallace page 112, Example 146:

| before | after |
| --- | --- |
| crop: `Find the slope of a line parallel to 5y − 2x = 7.` with rows `5y − 2x = 7` and `+2x + 2x` and their annotations | `Find the slope of a line parallel to 5y− 2x = 7.` |
| | `To find the slope we will put equation in slope− intercept form` |
| crop: rows `5y − 2x = 7`, `+2x + 2x`, `5y = 2x + 7` | the same crop |
| `Put x term first` | `Add 2x to both sides Put x term first` |

The first crop is gone, so the two rows it repeated are pictured once; the example's prompt and
two annotations read as text, the last two run together in one paragraph as the page's other
annotations already did. Wallace's images go from 3,278 to 3,277, and its conversion report
differs in `imageCount` alone. Every other page of both books, and the arXiv paper, Geltman and
Census whole, convert byte-identically. The corpus lane on `wallace-algebra-2010`,
`arxiv-replay-clocks-2023`, `nbs-jres-geltman-1977` and `census-rrs2002-01` gives `runPassed`
true and no content-assessment errors on each.

Left as they are:

- The crop's foot is the display seed's eight-point margin, 0.59 point inside the sentence's line,
  so the tops of the sentence's ascenders show as two pixel rows (18 inked pixels at 180 DPI)
  along its lower edge. A crop keeps its own extent against prose it cannot cut (#255); stopping a
  formula's margin at the prose beside it is the other half of #51's fix, which lives only in
  `eb0197c89`. Formula margins reach into a whole sentence on 18 of Wallace's pages, 2 of the
  arXiv paper's and one of the FAA handbook's, so that change is not this one.
- `The problem of scheduling flight f…` opens a new paragraph with an indent, but runs on after
  the released sentence, which ends at 0.68 of its width: over the 0.65 at which a line above an
  indented line closes its paragraph. That is #310's mechanism, reported there on Loper Bright.
- Lines inside a running paragraph that state a relation still seed crops and are read only in
  pictures: DASC page 2 (`are given a set of flights, indexed by f: f = 1,2,...,F,` with the lines
  above and below it) and the arXiv paper's pages 5, 6, 7 and 10 (`…to ensure that if E= 1ms then
  the worst-case`, `We presented RepCl to solve the replay problem with E1 = E+I`). They open in
  lowercase or run on past the line, and the rule does not read them; #51's paragraph-measure
  test in `eb0197c89` does.
- Wallace page 112's two crops that pictured the same rows were one case of a shape nine other
  Wallace pages keep: two crops of one worked example overlap, the rows they share are pictured
  twice, and the upper crop cuts the next row in half (17 lines on pages 48, 49, 103, 104, 147,
  170, 239, 275 and 408; checked in the EPUB on pages 104 and 239). Filed as #318.
