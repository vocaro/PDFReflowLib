# A cross-page join reaches only a block the page's text begins at

Measured under [#267](https://github.com/vocaro/PDFReflowLib/issues/267), baseline `d4ce045`
("A lone letter is a word only in the company of words"), 2026-09-22, macOS 27.0 (26A428) /
Xcode 27.0 (27A266a), arm64, release CLI at library defaults, `--package-identifier
urn:uuid:test --modification-date 2026-01-01T00:00:00Z`. The host was shared with other agents'
conversions throughout (load average 11–17).

| Binary | SHA-256 |
| --- | --- |
| baseline, `swift build -c release` at `d4ce045` | `c467bef8055f2d7074d49b19760db4dfbd2b337193798e14cb54339931396733` |
| candidate, this change | `f7dc3e9be858ba3a85644c9a3b12a9bed247f7f8afcdc38293ea5e652bec0b9e` |

Sources are the pinned corpus cache: `Beginning_and_Intermediate_Algebra.pdf`
`856bd81edc61c50496982ddc849138f4e0e56fd0ddf0edb53fee9bb0830d0678`, `the-fed-explained.pdf`
`8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60`, `GPO-911REPORT.pdf`
`657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b`.

## The defect

[#203](https://github.com/vocaro/PDFReflowLib/issues/203) let a cross-page join step over the
pictures between its two halves ([decision
0011](../../doc/decisions/0011-a-picture-keeps-its-side-of-the-page-marker.md)) and recorded four
of Wallace's joins as a known cost: a display crop had already taken the lines that continue the
sentence, so the halves brought together were never consecutive. Read against `pdftotext -layout`
on the cited pages, all four are the same shape, and it is the *later* page that has it — the
block the page opens with is not where the page's text begins.

| Boundary | What the page prints first | What reflows | What the crop took in between |
| --- | --- | --- | --- |
| 120→121 | `−5 −5` | `x ⩽ −3 Graph, starting at −3, …` | `− 2x ⩾ 6 Divide both sides by − 2`, `−2 −2 Divide by a negative − flip symbol!` |
| 288→289 | `√. There are sev-` | `fastest method, is to find perfect squares …` | `eral ways this can be done. The most common and, with a bit of practice`, `process is being able to translate a problem like √180 into √(36·5)` |
| 343→344 | `values into x =` | `and we will get our two solutions. …` | the quadratic formula, set beside `values into x =` on the same printed row |
| 429→430 | `b are the other two sides (legs), …, a² + b² = c²` | `to find a missing side.` | that whole row |

On 288 the crop had also taken the foot of the earlier page (`…and simplifying the first root,
6√5. The trick in this`), so that boundary is broken on both sides; the other three are broken
only on the later page's.

## The rule

A cross-page join reaches only a block the page's own text begins at. Where a crop took what the
page printed before the first line it reflows, the join is not made: the boundary keeps a
standalone marker and the two fragments stay two blocks.

`LayoutReconstructor.blocks` already computes the lines its crops took, so it marks the page's
first reflowed block (`ReflowBlock.followsCroppedText`) and `appendPage` reads that flag beside
its other conditions. Reading order decides what "before" means: a cropped line is before the
first reflowed one when it stands **above** it, or on the **same printed row and earlier along
it** — which is the only way page 344's `values into x =` is before `and we will get our two
solutions.` at all.

Above the line, what the crop took must be the page's own flow, on two tests:

- it **reads as the page's prose** — `readsAsSentence`, four or more words of two letters or
  more, the test the crop rules (#255) and a block reached past a picture (#203) already use;
- it **begins the measure the first reflowed line begins**, within a quarter of a body.

Along the row neither test applies: a printed row the page began inside a crop is that row
wherever its pieces read, and `values into x =` is two words.

## Why the measure, and why only the later page

**The measure is what keeps the 9/11 report's joins.** The report runs its boxed list of
*Operational Opportunities* over the foot of page 373 and the head of page 374. Twenty-one lines
of that list are prose, a crop takes all of them, and every one stands above the first line page
374 reflows — so without the measure test the join `…the deputy director argued that all
involved were` / `responsible for making it work.` is refused, and so is 163→164. The list is
set 24.5 points in from the body measure (64.18 against 39.66) and the four Wallace lines stand
at the measure or left of it (+0.00, +0.00, −5.88, +0.00), so a quarter of a body separates them
cleanly; the corpus holds no case between.

**Only the later page is read this way.** The Fed sets a box or a figure over the foot of pages
40, 47, 55, 93, 97, 98, 100 and 103, its prose standing *below* the paragraph that continues
overleaf, indented 12.50 points into the box. Asking of the earlier page what this asks of the
later one — without the measure — refuses those eight joins, which is the variant #203 already
measured and rejected. A paragraph whose own last line a crop took is still
[#45](https://github.com/vocaro/PDFReflowLib/issues/45)'s reading-order anchor, which is not
ported and is not measured here.

## What moves, by book

Every corpus source was converted twice, with the two binaries above, and the joins counted the
same way in both: a page marker the writer set *inside* a block that holds other text is a join;
a boundary with no join has a marker standing on its own.

| Book | Joins before | Joins after | Block stream |
| --- | ---: | ---: | --- |
| `wallace-algebra-2010` | 23 | **19** | four paragraphs become eight blocks: pages 121, 289, 344 and 430 each keep a standalone marker, and 9,770 blocks become 9,778 |
| `gpo-warren-1964` | 295 | 295 | identical, 17,874 blocks |
| `gpo-911-2004` | 272 | 272 | identical, 5,360 blocks |
| `noaa-nca5-2023` | 210 | 210 | identical, 30,173 blocks |
| `faa-phak-8083-25c` | 16 | 16 | identical, 9,522 blocks |
| `fed-explained-2021` | 12 | 12 | identical, 1,203 blocks |
| `census-rrs2002-01` | 5 | 5 | 432 → 435 blocks, all of it this scan's recognition layer re-read (`Kim &#124; 8` against `Kim 8`, `€` against `e`), which is Vision's own variation (#173); no join moves |
| `cia-blue-book-14-1955` | 4 | 4 | identical, 32,424 blocks |
| `usda-ars-agresearch-2012-11` | 2 | 2 | identical, 1,048 blocks |
| `arxiv-replay-clocks-2023` | 2 | 2 | identical, 271 blocks |
| the other ten | 0 | 0 | identical |

The ten with no join at all are `scotus-loper-bright-2024`, `gpo-our-flag-2003`, `dga-2025-2030`,
`uscis-m618-arabic-2015`, `cdc-zombie-pandemic-2011`, `nbs-jres-geltman-1977`,
`usgs-mcs2025-copper`, `irs-p596-zhs-2025`, `ntrs-20180003024-earthdata-slides-2018` and
`gpo-warren-1964-suspect-text-excerpt`. A join can only be refused by this change, never made, so
a book with none cannot move; each was converted twice all the same and each is identical.

Wallace's four are the whole of the corpus cost, and they are the four the issue names. Each one
becomes the two blocks it was before #203, with the page's marker standing between them and each
page's pictures still on their own side of it:

```
<p>…the Pythagorean Theorem states that if c is the hypotenuse of the triangle, and a and</p>
<span epub:type="pagebreak" id="page-430" …/>
<figure>…page 430's display…</figure>
<p>to find a missing side.</p>
```

## A fifth, in a source outside the corpus manifest

`corpus/cache` holds four PDFs the manifest does not list. Three of them are unchanged
(`complaint_for_a_civil_case` and `20200002975` hold no join, `20190030725` holds three and keeps
them). The fourth, NASA's *Tank Health Monitoring* close-out report, holds one join and it is the
same defect: page 5 is a grid of image captions, a crop takes `Accurate measurement of cryogenic
liquid propellant quantity in space`, and the baseline joins page 4's `Figure 1: essential signal
chain of the MPG technology …(https://techport.nasa.gov/image/41317)` to the fragment
`without propulsive settling maneuvers` left behind. The rule refuses it, and the report's 73
blocks become 75.

## Reproducing

```sh
swift build -c release
BIN="$(swift build -c release --show-bin-path)/pdf-reflow"
for pdf in corpus/cache/*.pdf; do
  "$BIN" "$pdf" "/tmp/after/$(basename "${pdf%.pdf}").epub" \
    --package-identifier urn:uuid:test --modification-date 2026-01-01T00:00:00Z
done
```

A join is counted by reading each spine document in order and taking every
`<span epub:type="pagebreak" …/>` that stands inside a `<p>`, `<pre>`, `<h1>`…`<h6>`, `<li>`,
`<td>` or `<th>` holding other text; a boundary with no join has its marker as a block of its
own. Counted that way the two lanes give 845 joins and 840.
