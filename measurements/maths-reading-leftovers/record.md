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
