# Figure/caption pairing, conversion-policy assertions and the remaining unprotected pages

Part of [#27](https://github.com/vocaro/PDFReflowLib/issues/27). The contracts already protected
text, order, images, source regions, glyph structure, appearance and table cells. Three classes of
correct output were still unprotected everywhere: **a caption's place beside the figure it names**,
**what a conversion must not do to a page** (recognize it, declare its text layer damaged or
implausible, fall back to a whole-page image, or attach a source-page reference nothing needs), and
**cross-page paragraph continuity outside the five documents that already had it**. This record
covers the `captionedImages` contract type, the additions across eleven documents and their negative
controls.

macOS 27.0, arm64; Python 3.14.6, numpy 2.4.6, Pillow 12.2.0, Poppler 26.04.0 (reference rendering
only). Converter built from `3a65be6`, SHA-256
`ba2c0bc927dcac205ba88f7c528c763122b89644ae66014e080a876228f8d415`.

## The new check type: `captionedImages`

A caption that a reading-order defect moves away from its figure still satisfies `text`,
`orderedText` and `paragraphs`: those ask only that the page holds the phrase. `captionedImages`
adds the positional assertion:

```json
{"captionedImages": [{"caption": "Figure 11-5. Drag versus speed."},
                     {"caption": "TABLE I: A 6-flight example.", "position": "before"}]}
```

`tools/check_corpus_content.py` records, per page, the sequence of the page's own outermost blocks
(`p`, `pre`, `li`, `table`, `h1`–`h6`) and its images, in document order. The converter's generic
`<figcaption>` never enters that sequence, so a preserved region's own caption does not stand
between a figure and the caption the source printed. The expectation passes when some block holding
the phrase is the immediate neighbour of an image — the block after it (`position` `after`, the
default, the placement of figure captions in the FAA handbook, the NASA papers and IEEEtran) or the
block before it (`position` `before`, the placement of IEEE table captions).

A block that a page marker interrupts keeps only the text it holds on the page it opened, so a
caption is judged on its own page. What the check does **not** claim: which figure a caption sits
beside. It proves the pairing survived, not that the pairing is right.

`tools/test_corpus_content.py` holds the checker's own controls (a stray block between figure and
caption, a missing figure, a missing caption, the caption on the wrong side, the caption on another
page, and the malformed expectations), plus two reader tests that the block sequence skips generic
figcaptions and table cells and splits at an inline page marker.

## Coverage before and after

Checks and reviewed pages per document, counted as `tools/check_corpus_content.py` counts them.
Documents with no change are omitted.

| Document | Pages before | Pages after | Checks before | Checks after |
| --- | ---: | ---: | ---: | ---: |
| `faa-phak-8083-25c` | 134 | 134 | 524 | 547 |
| `gpo-our-flag-2003` | 20 | 22 | 110 | 114 |
| `cdc-zombie-pandemic-2011` | 10 | 10 | 59 | 60 |
| `usgs-mcs2025-copper` | 2 | 2 | 50 | 51 |
| `nbs-jres-geltman-1977` | 7 | 7 | 52 | 63 |
| `uscourts-pro-se-1-2016` | 5 | 5 | 157 | 162 |
| `ntrs-20200002975-gwl-2020` | 20 | 20 | 235 | 285 |
| `ntrs-20190030725-dasc-2019` | 10 | 10 | 185 | 208 |
| `usda-ars-agresearch-2012-11` | 21 | 24 | 131 | 164 |
| `ntrs-20180003024-earthdata-slides-2018` | 21 | 21 | 192 | 213 |
| `ntrs-20210020887-techport-thm-2021` | 5 | 5 | 48 | 64 |
| **all 21 documents** | **508** | **513** | **2,791** | **2,979** |

New checks by type (188 in all): 35 captioned-image, 86 absent-warning, 44 page-reference,
13 warning, 4 paragraph-continuation, 3 image-presence, 2 glyph-structure, 1 image-appearance.

## What the additions protect

**Figure and caption pairing (35 checks).** Twenty-three FAA `Figure N-M.` captions on sixteen pages
(81, 108, 165, 199, 226, 262, 286, 288, 302, 317, 341, 348, 391, 397, 401, 439), each already a
reviewed phrase in the contract and each set directly beneath its artwork in the source; GWL's
Figure 3 (page 4) and the five appendix captions A1–A5 (pages 14–18); DASC's Fig. 1 (page 4, below)
and the TABLE I and TABLE III captions (pages 7 and 10, above); TechPort's Figure 1 (page 4); and
NBS Figures 1 and 2 (pages 2 and 3), whose crops end above their captions.

USDA page 6's two photo captions were **not** added: the magazine sets one caption above its photo
and one beside another, and the column interleaving of #153 leaves which caption belongs to which
crop ambiguous in the output.

**Page policy (143 checks).** Every reviewed page of the six documents added on 2026-09-17, plus NBS,
now says what the conversion must not do. The six sources are born-digital with usable text layers
(Chromium/Skia with Open Sans and Verdana; Word 2013; pdfTeX; Google Slides with Arial and Verdana;
InDesign; a distilled WordPerfect form), so no page may report `ocrUsed`, `damagedTextEncoding`,
`implausibleTextLayer` or `pageImageFallback`, and — except where a defect already does it — no page
may report `unverifiedTextLayer`. `pageReference` is pinned false on all five TechPort pages, all ten
DASC pages, GWL pages 2–20 and eight more USDA pages: their annotations draw nothing beyond the
printed page (#151). NBS is the opposite case: all seven pages must keep their `Original page N`
image beside the inherited Paper Capture OCR.

Three exemptions are deliberate, because the behaviour is wrong rather than reviewed: the slides keep
`unverifiedTextLayer` and a page image on all 21 slides (#164); USDA pages 20–21 keep
`pageImageFallback` (#158); and slide 5, whose source text layer holds only its folio, is exempt from
the `ocrUsed` assertion (see Defects).

**Pages that had no checks at all.** USDA 14, 22 and 23 are new review pages. #158 holds all of their
body text inside crops, so nothing reflowed can be pinned; they assert their preserved regions, the
disclosure of those regions, the absent source-page image and the absent recognition/fallback
warnings. TechPort page 5 went from one check to five and its image minimum from 1 to 3, the three
gallery pictures. Our Flag pages 22 and 23 are new review pages for their cross-page paragraphs.

**Cross-page paragraphs (4 checks).** Our Flag 10→11 (the 50-star paragraph), 22→23 (flag code
paragraph (h)) and 23→24 (paragraph (m)), each read on the renders; NBS 6→7, the conclusion sentence
ending `the magnitude of the applied electric field` that continues `equals the mean atomic field
strength`. Before this, cross-page continuity was checked only in the FAA handbook, the 9/11 report,
the Fed, Loper Bright, Wallace, Replay Clocks, GWL and DASC.

**Strokes and colour (3 checks).** Two new glyph references and one new colour reference, below.

## New references

| Reference | Region (points) | Pixels | Correct crop |
| --- | --- | --- | --- |
| `usgs-mcs2025-copper/page-2-world-production-glyphs` (glyph) | 40,272–565,512 | 1247×585 L | coverage 0.730, extra ink 0.000, sharpness 1.00 |
| `gpo-our-flag-2003/page-27-flag-size-table-glyphs` (glyph) | 80,438–246,575 | 411×331 L | coverage 0.974, extra ink 0.000, sharpness 1.00 |
| `cdc-zombie-pandemic-2011/page-13-page-color` (colour) | 0,0–612,792 | 306×396 RGB | scale 1.00, contrast 0.988, colour agreement 1.00 (1,247 coloured samples) |

Both glyph references re-use a region a previous reviewer chose for the 36 DPI region check, so the
regions are the same reviewed content at full resolution. The USGS reference covers every figure of
nineteen country rows, the spanning `Mine production` / `Refinery production` headers, the raised
estimate markers and the underlined totals (932 components' sibling table on page 1 already had one;
this is the second page). The Our Flag reference covers both small-caps headers and all ten
dot-leader rows of a table that #36 keeps as an image, so every digit of a table nothing could read
as text is now checked. The CDC reference is the first colour check on artwork rather than a chart or
a flag: page 13 is image-only, and its lamp glow over blue-grey night panels is the page's content.

**Rejected:** a glyph reference for NBS display equation (11). The crop scores coverage 0.84 but
0.441 extra ink, because the Paper Capture scan's background is grey rather than white and
`glyph_structure` counts every background pixel's darkness as ink outside the reference. The
contract cap is 0.5, which leaves no headroom, so the reference was not committed. Glyph structure
remains a born-digital check; a scanned equation needs a background-relative ink measure.

## Controls

`controls.py <evaluation-root> --json controls.json` re-runs every control against corpus
evaluations. Each mutates one passing evaluation and requires the named failure; all 23 fail as
required (`controls.json`).

| Control | Required failure |
| --- | --- |
| GWL 14: stray line between Figure A1 and its caption | caption does not stand after an image |
| GWL 14: figure removed, caption kept | caption does not stand after an image |
| GWL 14: caption removed, figure kept | no block holds the caption |
| DASC 7: TABLE I caption pushed below its table | caption does not stand before an image |
| FAA 262: Figure 11-5 caption pushed away from its figure | caption does not stand after an image |
| NBS 2: FIGURE 1 crop removed, caption kept | caption does not stand after an image |
| TechPort 3 / USDA 22: a source-page image appears | unexpected source-page reference image |
| DASC 5: `ocrUsed`; GWL 9: `pageImageFallback`; slides 12: `implausibleTextLayer`; Pro Se 2: `damagedTextEncoding` | unexpected quality warning |
| TechPort 2: `annotationsNotConverted` dropped; USDA 23: `imageRegion` dropped | missing quality warning |
| TechPort 5: one gallery image dropped | missing preserved images |
| USGS 2: Chile's figures erased; the spanning headers erased | no image shows every stroke |
| Our Flag 27: the 125 ft row's flag size erased | no image shows every stroke |
| CDC 13: grayscale; channels swapped; half scale | no image keeps the appearance |
| Our Flag 10 / NBS 6: the paragraph split at the page marker | paragraph does not continue |

## Defects found

- **An image-only slide is neither recognized nor recovered.** Earthdata slide 5 draws its only
  content — `How do we support user analysis of very large data volumes?` — as artwork; `pdftotext`
  returns the folio `5` and nothing else. The conversion reflows no text for that slide, reports
  `recognizedPageCount` 0 for the deck, and warns `unverifiedTextLayer` (a warning about text over a
  page-sized image) rather than saying the page's content is image-only. The slide's question is
  absent from the EPUB's reading text. Filed as
  [#176](https://github.com/vocaro/PDFReflowLib/issues/176); slide 5 is exempt from the deck's
  `ocrUsed` assertion so the contract does not bless it.

## Limits

`captionedImages` proves adjacency, not identity: a caption next to the wrong figure passes. It
reads one page at a time, so a caption separated from its figure by a page boundary is not
expressible. `absentWarningCodes` asserts what a report does not say; it cannot see a page whose
text is wrong without a warning. `pageReference` counts the `Original page N` image only, not a
whole-page fallback image under another alt text. None of these is a whole-book fidelity
qualification.
