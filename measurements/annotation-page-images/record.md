# Annotations and source-page images (#151)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, release CLIs.
Baseline: an unmodified release build of `1a18b7a` (converter `d67659ef…`); candidate: that tree
with this change (`58f58ab5…`). Every corpus figure is `tools/run_corpus_regressions.py`, one case
per call, with one compiled raster/Vision probe shared by both runs and `--execution-context
host-terminal`, then `tools/compare_conversion_runs.py --allow-different-converters` (receipts in
`lane/`). No PDF or EPUB is committed.

## Diagnosis

`PDFReflowLibPipeline.extractPage` asked one question about annotations:

```swift
if !page.annotations.isEmpty {
    content.preservePageReference = true
    warnings.append(.init(code: .annotationsNotConverted, …))
}
```

Any annotation, of any kind, therefore appended a full `Original page N` raster to a page that
otherwise reflowed. A link is an annotation; so is an empty form field.

## Survey of the English corpus

`tools/annotation-dictionaries.swift` reads every annotation's raw dictionary; `tools/annotation-rendering.swift`
renders each page twice at one pixel per point, with and without PDFKit's annotation drawing (the
drawing `PageRasterizer` puts into a page image), and also draws each annotation alone over
transparency. Neither uses the library.

| Document | Annotations | Pages with annotations | Pages PDFKit's annotation drawing changes |
| --- | --- | --- | --- |
| FAA handbook | 1,857 Link, 1 Highlight, 1 Popup | 21 of 522 | 0 |
| NOAA NCA5 (excluded from the lane) | 15,098 Link | 803 of 1,834 | 0 |
| The Fed Explained | 257 Link | 92 of 135 | 0 |
| 9/11 Report | 161 Link | 28 of 585 | 3 (pages 570, 571, 575) |
| Replay Clocks | 75 Link | 11 of 12 | 0 |
| US Courts Pro Se 1 | 68 Tx, 1 Ch, 8 Btn widgets | 5 of 5 | 3 (pages 1, 3, 5) |
| USDA *Agricultural Research* | 55 Link | 21 of 24 | 0 |
| NASA ground wind loads | 10 Link | 1 of 20 | 0 |
| NASA TechPort (not in the lane) | 27 Link | 5 of 5 | 0 |
| CDC comic | 1 Link | 1 of 42 | 0 |
| Our Flag, Warren Report | 1 Sig widget each | 1 of 56, 1 of 920 | 1 each (the GPO authentication seal) |
| Wallace, DGA, Blue Book, NBS, USGS, SCOTUS, Census, NASA DASC | none | — | — |

What the exceptions draw:

- **9/11 pages 570, 571 and 575.** Four of the 161 links carry `/BS <</W 1>>` and no `/C`; PDFKit
  draws a one-point black rectangle around the web address, which the page render confirms.
  The other 157 links have `/BS <</W 0>>` or `/Border [0 0 0]` and no appearance stream.
- **US Courts Pro Se 1.** The eight buttons are two Jury Trial checkboxes (page 1), two
  jurisdiction checkboxes (page 3), all `/AS /Off`, and four page-5 push buttons (Print, Save
  As…, Add Attachment, Reset) that draw red rectangles. Of the 69 text/choice fields, 67 are
  empty and draw nothing; the two on page 1 hold `__________ District of __________` and
  `__________ Division`, which the page content prints under them (the page text layer holds both
  strings), so their appearance repeats the printed caption.
- **FAA page 362.** A reviewer's `/Subtype /Highlight` with `/C [1 1 1]` and `/CA 0.4` over
  *Clearing Procedures*, with an attached Popup. Drawn alone it inks pixels; drawn over the page it
  changes nothing, in PDFKit and in Poppler alike — white multiplied over the page is invisible.
- **Our Flag page 1 and Warren page 1.** A signature widget whose appearance draws the GPO
  "AUTHENTICATED U.S. GOVERNMENT INFORMATION" seal over the cover; visible, so the reference stays.

## Policy

`AnnotationEvidence.judge` decides per annotation, and only annotations that show earn a reference:

1. Hidden annotations (`shouldDisplay` false, or the Hidden/NoView flags, which PDFKit's own
   drawing ignores) are not judged at all: a reader never sees them.
2. **Form widgets** are read for what they hold. Push buttons are viewer controls. An unchecked
   box or radio, and a text or choice field that is empty or whose value the page already prints
   under it, show nothing beyond the printed page. A checked box, and a field whose value is not
   printed under it, show content the reflow does not carry. Other widgets (signatures) fall
   through to the drawing test.
3. **Every other annotation** is judged by its drawing: drawn alone over transparency within its
   bounds, an annotation that inks no pixel draws nothing; one that inks is drawn again over the
   page's own rendering of that area and shows only if some channel of some pixel moves by more
   than two levels.

A page with annotations always warns `annotationsNotConverted`. Where something shows, the message
is unchanged and a page image accompanies the text. Where nothing shows, the message names what is
lost — "Links on this page are not interactive in the EPUB. They show nothing beyond the printed
page, so no source-page image is added." — and no image is added. `referenceImages = .never`
reports `referenceImageOmitted` only for pages that show something.

Checkbox widgets also identify the box glyphs printed under them. The Pro Se 1 form draws its boxes
in `EGFJCI+WP-IconicSymbolsA`, whose ToUnicode CMap maps the only code it uses, `<0075>`, to
`<2019>`, so PDFKit reads each box as `’`. Where a line's every occurrence of that glyph lies under
a checkbox widget, the occurrences are rewritten `☐` (or `☒` when the box is on); a line that also
holds the glyph outside a box — `the Clerk’s Office` — is left exactly as extracted. This is
widget evidence, not a font table: nothing is assumed about WordPerfect's glyph set.

## Corpus results

One `run_corpus_regressions.py` call per case; every case passes its contract, EPUBCheck, progress
and memory gates in both runs. `imageCount` is the report's; the reference column counts
`Original page N` assets.

| Case | Images (before → after) | Source-page references | EPUB MiB | Pages changed |
| --- | --- | --- | --- | --- |
| US Courts Pro Se 1 | 26 → 21 | 5 → 0 | 1.1 → 0.02 | 1–5 |
| The Fed Explained | 141 → 57 | 93 → 9 | 61.2 → 30.1 | 92 |
| 9/11 Report | 75 → 50 | 28 → 3 | 15.2 → 6.4 | 25 |
| FAA handbook | 588 → 567 | 39 → 18 | 245.0 → 235.6 | 21 |
| USDA *Agricultural Research* | 70 → 52 | 20 → 2 | 78.1 → 42.1 | 21 |
| Replay Clocks | 45 → 34 | 11 → 0 | 7.5 → 1.0 | 11 |
| NASA ground wind loads | 32 → 31 | 1 → 0 | 7.2 → 6.6 | 1 |
| CDC comic | 42 → 42 | 38 → 38 | 142.8 | page 39's warning only |
| Our Flag | 123 → 123 | 3 → 3 | 12.7 | none |
| DGA | 37 → 37 | 1 → 1 | 5.3 | none |

The references that remain are the ones other policies ask for: OCR pages (CDC, Our Flag), pages
under an unverified text layer (USDA 1 and 13, Fed 4, 8, 14, 24, 50, 66, 88 and 116, 18 FAA pages),
required fallbacks, and the three 9/11 pages
whose links draw a border. `compare_conversion_runs.py` reports no changed field on any page beyond
`images`, `markup`, `pageReferences` and `warnings` — except the Pro Se 1 pages 1 and 3, whose text
changes are the rewritten box glyphs (`Jury Trial: (check one) ☐ Yes ☐ No`, `☐ Federal question`,
`☐ Diversity of citizenship`). Navigation, page markers and OCR text are unchanged everywhere.

Reviewed after the change: Fed pages 5, 6, 11, 109 and 123 (the contents page, Figure 6.11's
reconstructed table, Box 7.1's reflowed prose), USDA pages 2–19 and 24, 9/11 pages 570, 571 and
581–583, FAA pages 6–15 and 362, and all five Pro Se 1 pages, against 40–70 DPI Poppler renders.
Nothing a page image showed is lost that the reflowed text and region crops do not hold; where a
page's text is trapped inside a crop (USDA pages 2–7, 14, 16; #158), the crop still holds it.

Two contracts had required an image that only the link-forced reference supplied: Fed 109/123 and
9/11 581–583. Their `minimumImages` are replaced by `pageReference: false`, since Figure 6.11 is a
`tableCells`-checked table, Box 7.1 is reflowed prose and the note pages are text.

## Tests

`AnnotationPageImageTests.swift`, synthetic PDFs (page prose plus annotations):

- a borderless link, an empty text field with a push button and a white stamp, unchecked boxes over
  printed glyphs, and a Hidden stamp get no reference, no `imageRegion` and no
  `referenceImageOmitted`; their `annotationsNotConverted` messages name links, form fields or
  annotations that draw nothing, and the hidden page warns nothing;
- controls keep the reference with the unchanged message: a bordered link, a filled field whose
  value the page does not print, a checked box, a stamp. Under `.never` exactly those pages report
  `referenceImageOmitted` and no asset is written;
- `AnnotationEvidence.judge` counts links, fields, invisible annotations and boxes on those pages,
  including a filled field whose value *is* printed under it (no reference);
- box glyphs become `☐`/`☒` on the checkbox rows while `The Clerk’s Office` keeps its apostrophe,
  and `markBoxes` leaves a line where the glyph also occurs outside a box.

Negative controls: with the old `!page.annotations.isEmpty` rule and `markBoxes` disabled, the
pipeline tests fail 11 expectations; with the page comparison removed (inked bitmap alone counts),
widgets judged only by drawing and the flags ignored, all three tests fail 13 expectations.
`tools/test_corpus_content.py` gains `test_page_reference_expectation_distinguishes_references_from_other_images`
for the new `pageReference` contract key. The corpus contracts themselves are a control both ways:
run against the baseline evaluations they fail 40 page-reference
checks (and the five Pro Se 1 glyph text checks); against the candidate they pass.

## Limits and follow-ups

- The comparison is PDFKit's drawing, the same drawing the page image would carry. Another viewer
  may render a borderless link's focus ring or a white highlight differently; nothing is claimed
  about that.
- `PageRasterizer` still draws Hidden/NoView annotations into a page image it makes for some other
  reason: PDFKit's `shouldDisplay` does not read those flags. No corpus document has one.
- NOAA (excluded from the lane for the image-output ceiling) would lose 803 page images; the
  excluded-case budget has not been re-measured.
- A form's unchecked boxes that are drawn by the widget alone, with no printed glyph under them,
  are not represented in the EPUB at all; only the label remains.
