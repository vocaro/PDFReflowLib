# A page's own leading ends its paragraphs, and a ligature is letters to the vocabulary

Measured under [#123](https://github.com/vocaro/PDFReflowLib/issues/123), baseline `7d6b0cd`,
2026-09-20, macOS 27 / Xcode 27, arm64, release CLI at library defaults, sources from the pinned
corpus cache.

The issue names three defects in `wallace-algebra-2010`. Two were live on `7d6b0cd` and are fixed
here; the third had already been fixed by [#255](https://github.com/vocaro/PDFReflowLib/issues/255)
three commits earlier, and is recorded below with the measurement that shows it.

## 1. The hyphen vocabulary holds ligature words as ligatures

Wallace's text font prints `ff` and `ffi` as the single glyphs U+FB00 and U+FB03: 140 and 45
occurrences over 185 words and 24 distinct spellings, `diﬀerent` 56 times and `diﬀerence` 46.
`LayoutReconstructor.words` took the line as extraction read it, so the book's own words held
`diﬀerent` and never `different`, and the vocabulary had nothing to say about `dif-` + `ferent` on
pages 50 and 218 — the break the issue names.

The vocabulary now holds each word lowercased and with compatibility glyphs resolved to the
letters they stand for (`precomposedStringWithCompatibilityMapping`), and both halves of a break
are looked up the same way. Only the evidence folds: the ligature the page printed stays in the
text the reader gets, on both sides of a join.

Over every line-end break in all twenty pinned sources — 11,418 of them — the folding changes the
route of exactly two and the outcome of none:

| | breaks | decided differently | text changed |
| --- | ---: | ---: | ---: |
| all twenty sources | 11,418 | 2 | 0 |

The two are Wallace pages 50 and 218, which the book's own words now decide instead of the system
lexicon. **The symptom the issue reports is no longer visible on `main`**: the English lexicon
[#186](https://github.com/vocaro/PDFReflowLib/issues/186) added vouches for `dif` + `ferent`, so
the hyphen already came out and no `uncertainHyphen` warning was raised. What the fix restores is
the book's own evidence deciding its own word. That matters where the lexicon cannot speak: it is
consulted only in a document declared English, and `EnglishText.lexiconContains` answers nil where
the system provides no `NLEmbedding`. On such a host, `7d6b0cd` keeps the hyphen and warns.

Three books' vocabularies shrink, where two spellings fold together: the arXiv paper 1,306 → 1,274
words (its LaTeX ligatures and maths italics), the Census paper 1,212 → 1,208, NOAA 39,744 →
39,741. Wallace's stays at 3,451, of which 25 words fold (`coeﬃcient`, `diﬀer-`, `staﬀ`, `ℓh`).
Nothing collides into a word that decides a break differently, which is what the table measures.

The whole book still keeps exactly two `uncertainHyphen` warnings, on pages 3 (`Hamp-` + `shire`)
and 224 (`fol-` + `lowing`, `Fran-` + `cois`) — neither a ligature word.

## 2. A line the page set a further half-line down is its own block

Wallace page 64 sets the second line of a bulleted item and then that item's example:

```
 12 [ 101.16 471.26 408.97 20.46] • More than often represents addition and is usually built backwards,
 13 [ 120.96 465.34 189.48 11.98] writing the second part plus the first
 14 [ 120.96 443.62 215.62 11.98] Three more than a number becomes x + 3
```

Every wrapped line of prose on that page is 14.40 points below the one above it, top to top; the
example is 21.72, one and a half times as far. Measured the way `continuesParagraph` measured it —
the white between PDFKit's rectangles — that is 9.74 points, inside the 10.76 the rule allowed, so
the example was appended to the item's own sentence:

```
main   <p> writing the second part plus the first Three more than a number becomes x + 3
fix    <p> writing the second part plus the first
       <p> Three more than a number becomes x + 3
```

The white between the rectangles cannot see this, because PDFKit's line rectangle grows downwards
by whatever descenders the line carries: the bulleted item's box is 20.46 points tall where the
line beneath it has 11.98, and the white between *those* two is negative although the page set
them one line apart. The tops of two lines of one size sit one ascent above their baselines, so
their distance is the leading, and that is what is read.

`LayoutReconstructor.statedLeading` reads a page's own leading: the commonest top-to-top distance
between vertically adjacent lines of one size in one column, to the nearest half point, over the
lines the crops leave in the prose, with at least four pairs agreeing. Two lines more than 1.4
times that leading apart are not one paragraph. The bound is the page's own measure because the
same ten points of white is nothing under display type and a paragraph break under footnotes; a
page that states no leading, and a pair of lines set at different sizes, are judged by the gap
alone, exactly as before.

Page 64 gains three block boundaries the page prints and the conversion had lost: this example,
the same example under the item below it, and the break between the section's two opening
paragraphs.

## What it moves across the corpus

Both changes together, every covered case converted with `7d6b0cd`'s binary and with this one:

| Book | non-whitespace characters | blocks | pages reblocked |
| --- | ---: | ---: | ---: |
| cia-blue-book-14-1955 | 617,716 → 617,716 | 22,985 → 25,462 | 179 |
| wallace-algebra-2010 | 369,084 → 369,084 | 9,869 → 9,899 | 23 |
| uscis-m618-arabic-2015 | 94,511 → 94,511 | 1,390 → 1,408 | 15 |
| gpo-911-2004 | 1,587,370 → 1,587,370 | 4,670 → 4,675 | 4 |
| census-rrs2002-01 | 34,382 → 34,382 | 409 → 413 | 3 |
| irs-p596-zhs-2025 | 39,770 → 39,770 | 1,091 → 1,168 | 2 |
| faa-phak-8083-25c | 1,429,886 → 1,429,886 | 9,158 → 9,162 | 2 |
| usgs-mcs2025-copper | 5,332 → 5,332 | 20 → 24 | 2 |
| the other ten books | unchanged | unchanged | 0 |

**Not one character of any book changed.** Every difference is a block boundary, and on every page
reviewed it is a boundary the source prints:

- Wallace's `Objective: …` lines, its `World View Note: …` asides and 23 pages of paragraph breaks
  the book sets with a further half-line.
- The 9/11 report's run-in section headings — `Requirements for a Successful Attack`,
  `The New York Police Department.`, `The Fire Department of New York.` — which used to be buried
  in the paragraph above them.
- IRS Publication 596's bold run-in headings, in Chinese: `无 SSN。`, `获得 SSN。`,
  `报税截止日期临近时仍无 SSN。`, ten pages of them, each of which used to run into its neighbour.
- The Census paper's numbered section titles (`2.1 Domingo-Ferrer and Mateo-Sanz`).
- USGS copper's own entries: `Import Sources (2020–23):`, `Depletion Allowance:` and
  `Government Stockpile:` were three entries in one block and are now three.
- The USCIS guide's Arabic list items, on 15 pages.
- The CIA Blue Book's list-of-illustrations entries and `(1)`/`(2)` enumerations, on 179 pages of
  a scan whose inherited text layer the page sets with wide, irregular leading. This is the
  largest count by far and the least interesting: that book's blocks are already one printed line
  each in most places, so the change splits noise into more noise. Its content contract passes
  either way.

## What it costs

On two FAA pages a stray bullet the page leaves on its own baseline is no longer glued to the
sentence that introduces its list, and stands as a block of its own instead. Across that book the
change moves four markers from one shape of the defect to the other: sentences ending in a stray
marker fall from 15 to 11, and bare `<p>•</p>` blocks rise from 52 to 56. The defect is not this
rule's — PDFKit reports the marker and its item as two lines 18 points apart and nothing rejoins
them, on `7d6b0cd` as here — and it is now
[#261](https://github.com/vocaro/PDFReflowLib/issues/261).

## 3. The bullet inside Wallace's formula crop was already released

The issue's third item is that the `• Is (or other forms of is…)` bullet and its example sit inside
a preserved crop on page 64, so the bullet's text is lost. On `a55a85e`, the commit before #255,
that is exactly what happens:

| | crop | lines the crop takes |
| --- | --- | --- |
| `a55a85e` | `[99.16 498.86 400.96 43.70]` | `• Is (or other forms of is: was, will be, are, etc) often represents equals (=)`, `x is 5 becomes x =5` |
| `7d6b0cd` | `[116.96 498.86 112.50 27.98]` | `x is 5 becomes x =5` |

`x is 5 becomes x =5` seeds the crop through `statesAnEquation`, padded by 4 × 8 points; that is
the whole crop on `7d6b0cd`, which is the issue's "only the formula is preserved". The bullet
above it reads as the book's own prose, so #255's rule keeps the crop at its own extent rather
than growing over the line, and the bullet reflows:

```
<pre> • Is (or other forms of is: was, will be, are, etc) often represents equals (=)
<figure> [preserved region from page 64]
```

No change was made for this item. `theBulletBesideWallacesFormulaReflowsAndOnlyTheFormulaIsPreserved`
pins the behaviour so a change in that area cannot take it back silently.

## Gates

- `scripts/check-all.sh --fast`: PASS, every gate, 135 s wall clock. 501 Swift tests (nine new),
  227 Python tests.
- Corpus lane, `--jobs 4`, this binary: all 18 covered cases `runPassed: true`, with
  `structuralCheck: passed`, `epubcheckExitCode: 0`, the memory gate `passed` and the progress
  check true, read from each case's own `result.json`. The same lane on `7d6b0cd`'s binary passes
  the same 18. Warren and NOAA remain the two documented exclusions.
- Every layout fixture under `Tests/PDFReflowLibTests/fixtures` reconstructed with both binaries:
  four of the 114 change their blocks (`algebra-64`, `census-3`, `usgs-1`, `usgs-2`), all by
  splitting a block the source prints as two.

## After the merge

`main` moved to `97df92a` while this was measured, bringing
[#258](https://github.com/vocaro/PDFReflowLib/issues/258)'s native-spacing change. Merged at
`af4565e`, the fast lane passes every gate again and the corpus lane passes the same 18 covered
cases, each `result.json` read individually. The one number that moves is Wallace's text, 454,819
→ 454,823 characters, which is that merge's four word spaces and not this change; the tables above
are measured against `7d6b0cd` as they say.
