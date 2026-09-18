# MathML for evidenced equation crops (#190)

A mathematical crop whose glyphs and bars prove its structure is written as EPUB 3 MathML instead
of a picture; anything unproven stays the crop it was. Design and rules are in
[architecture](../../doc/architecture.md) (`MathRecognizer`); the contract check is
[`mathExpressions`](../../doc/regression-testing.md#math-expression-checks).

## Evidence the recognizer reads

PDFKit's lines cannot carry the structure: on Wallace page 17 it reads exercise 59
(`59) 3/5 + 5/4`) as the lines `59) 3`, `5 + 5` and `4`, and its per-character bounds do not line
up with its string offsets (a one-character selection returns the line's box, some characters
twice). The content stream does: every show has an origin on its baseline, a size, a font and
widths, so `NativeSpacingReader.read(recordingGlyphs:)` now records each glyph's character and
advance. For exercise 59 that is the label `59)` at 11.96 pt on baseline 417.10, numerators at
7.97 pt on 423.34, denominators on 412.30, `+` at 11.96 pt on 417.10, and two bars painted at
y = 419.86 (GraphicsReader's rect padded two points), each 5.4 pt wide over 4.23-pt terms centred
on it to 0.01 pt. The bar sits 0.23 em above the row's baseline, on the maths axis.

Wallace's `CMSY10` has a ToUnicode map that omits `periodcentered` and `divide` (the `4 · 4⁴`
and `−2 ÷ 7/4` exercises did not decode); recorded glyphs read such codes through the font's
`Differences` glyph name (`mathGlyphNames`: minus, periodcentered, multiply, divide, plusminus,
lessequal, greaterequal, notequal). Only recorded glyphs use these names, so no line matching or
spacing decision changes. Maths italic comes from the font name (`CMMI12`, #142); bold fonts are
opaque (page 15 sets the factor it multiplies in bold, which MathML from the glyphs would drop).

Refusals found while reviewing, and the rule each became:

- Wallace page 16 prints exercise 33 as `33 (2)(3/2)`, without its bracket. Read as a row it was
  `33 × (2) × (3/2)`. Operands side by side now multiply only when set close (≤ 0.2 em; the `33`
  stands 0.33 em off), so the crop stays an image.
- Page 252's exercise 42 sets `3ab` in upright type (a source slip); upright letters are words,
  so it stays an image while 41, 43 and 44 are MathML.
- Page 15's bold factors (above).

## Fallback decision

Options were MathML only, MathML plus the crop as a figure, or MathML with an image fallback.
Chosen: each printed row is `<p class="math">label <math alttext="…" altimg="…">…</math></p>`.

- `altimg` names the row's own crop (the expression without its label), MathML's fallback for a
  reading system that does not render it. The picture is not also shown, so a reader that
  renders MathML reads each expression once and a screen reader does not announce it twice.
- `alttext` is a linear form (`(−1)/9 ÷ (−1)/2`, `x^(−2)`), for readers that speak neither.
- The label stays text (`52)`), so exercise numbers search and read as before.
- The spine documents holding MathML carry `properties="mathml"`.

What a reading system without MathML and without `altimg` shows is the token text run together
(`27 3`), which misreads a fraction; this is the cost of not duplicating every expression as an
image, and is recorded here rather than hidden. `epub:switch` was not used: it is deprecated in
EPUB 3.3.

## Coverage per book (equation crops before → after)

Measured with the coordination tip (07c1bbd) and this change, default options:

| Case | Equation crops before | After | Crops now MathML | MathML expressions |
| --- | ---: | ---: | ---: | ---: |
| `wallace-algebra-2010` | 1,605 | 1,067 | 538 | 1,488 |
| `arxiv-replay-clocks-2023` | 10 | 10 | 0 | 0 |
| `ntrs-20190030725-dasc-2019` (IEEE) | 19 | 19 | 0 | 0 |
| `nbs-jres-geltman-1977` | 24 | 24 | 0 | 0 |
| `ntrs-20200002975-gwl-2020` | 1 | 1 | 0 | 0 |
| `census-rrs2002-01` | 27 | 27 | 0 | 0 |

Wallace's 538 crops hold 1,488 expressions because a crop is often a column of exercises. The other
books' crops were reviewed as rendered: Replay Clocks' are prose-bound formulas with floors, sets,
logic and multi-letter names; the DASC paper's carry subscripts, sums, matrices and delimiters;
NBS is a scan (recognized pages are never read); Census is recognized or index-glyph text. None is
in scope, and none was read. Wallace's remaining crops are worked examples annotated in words,
radicals, complex (stacked) fractions, systems with aligned rows, sets and intervals, subscripts
and bold rule statements.

## Validation

- EPUBCheck 5 on the full Wallace EPUB: 0 fatals, 0 errors, 0 warnings. A first version put
  `displaystyle` on `mfrac`, which MathML 3's schema refuses (383 errors); it is now an `mstyle`.
- Rendering: about 400 of the 1,488 expressions were rendered in WebKit (`WKWebView`, the engine
  Apple Books uses) beside their fallback crops, which are rasters of the source: sheets of 60–70
  consecutive expressions from pages 9–17, 42–106, 241–247, 439–448 and 480–487, and samples from
  pages 12, 252, 261–265, 347, 356–372 and 438. Each was read against its crop: every fraction,
  exponent, sign, bracket and label matched. About 700 linear alternative texts were also scanned as a list
  for implausible forms, which found the `33 (2)` case above. Two rendering
  defects were fixed from this review: a sign after `=` was spaced as a binary operator (`= − 12`;
  now an `mrow` makes it a prefix) and displayed fractions rendered at inline size (now
  `displaystyle`). WebKit stretches brackets around fractions, which the source sets at text size;
  that is a rendering choice, not structure.
- Apple Books itself was not opened: importing a test book changes the owner's library.

## Contracts

`corpus/regressions.json` pins MathML on Wallace pages 12 (Example 15's two displayed fractions),
16 (exercises 1, 22, 27, 32; exercise 33 remains the page's one image), 252 (41 and 44; 42 remains
its one image), 347 (1, 33 and 35, the last replacing its region and stroke checks) and 438
(answers 1 and 4). The checker's negative controls reject a wrong digit, terms swapped across the
bar, a flattened fraction, a lost exponent, a changed alternative text, another label and a
missing fallback image.

## Not done (follow-ups)

- Square roots: Wallace's `√` is a glyph with a painted vinculum, and its label often shares the
  radicand's show (`1)245`); the glyph positions recorded here make that readable, but no root is
  emitted yet.
- Subscripts, stacked (complex) fractions, systems, and worked examples whose rows are annotated in
  prose (the annotation could stay text beside each row's MathML).
