# An image's transparent margin, and what it would cost to stop believing it (#182)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs,
host terminal. Date 2026-09-21. The work was done on `8dcb9c2` (this worktree merged that tip of
main before starting and again before committing), and every measurement below is on that base.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `8dcb9c2` plus this record's tests and docs | `3efba1987295ea06489907b8356fec4cf7fde2c9d2557cfdda21a1c9cde77fa8` |
| candidate | the same tree plus the trim described under **The change that was measured and not kept** | `7474c220b269f17655d87733175cd8b1c92ec15dd699dd39bcfefb0998ed0581` |
| survey | [`tools/survey-image-alpha.swift`](tools/survey-image-alpha.swift), built as **Reproducing** prints | `5abe1e3cf6c4c95cd045cc2cfb7fd775f421d488540b1923fb1dcb6fbe2a8991` |

No source PDF or EPUB is committed, and no raster. The deck's every slide carries the NASA
insignia (14 CFR 1221; see the manifest's rights note), so nothing of it is reproduced here
beyond geometry and the words already quoted in the corpus contract.

[padding-survey.json](padding-survey.json) is the survey's summary: per document, the placed
images, how many carry a soft mask the reading admits, how far they are trimmed, and every line a
placement box takes that its drawing does not reach.

## What #182 asks

Three defects, all found while #164 was being measured **on the abandoned coordination branch**,
not on main:

1. Slides 2, 3, 4 and 11–21 keep a source-page image because a figure's bitmap overlaps its
   label's box; the fix named is for `LayoutReconstructor.captures` not to capture a line met only
   inside an image box's padding, which "affects every document".
2. A backdrop page's connectors are treated as decoration only inside a box; an arrow outside
   every text box would still become a region of its own.
3. `OCRTextCoverage` counts components darker than an ink threshold, so a white-on-dark-blue deck
   measures zero text rows and slide 5 cannot be judged at all.

Defect 3 is fixed on main and is measured below. Defects 1 and 2 both describe the behaviour of
code that main does not have, and the first one's mechanism, though real and measured here
exactly as the issue states it, costs a book its memory ceiling and earns no book a word. Nothing
in `Sources/` changed.

## Defect 3: already fixed, and the proof

`OCRTextCoverage.measure(_:lines:excluded:pixelsPerPoint:…)` already measures a page against its
own background: where a first reading finds no text row at all and the darker side of the ink
threshold covers more than `maximumBackgroundInk` (half) of the page, the page is measured again
inverted. `GrayRaster.inkIsBackground()` and `GrayRaster.inverted()` carry it, and
[behavior](../../doc/behavior.md#ocrtextcoverage-ink-measurement) states the rule. It arrived with
the #93/#7 port, commit `1b0308b` on 2026-09-19 — two days after #182 was filed — whose message
names "its OCRTextCoverage light-on-dark extension".

Measured on the deck itself, rendered at 180 DPI through `PageRasterizer`, with the rule in force
and with the inversion suppressed:

| Slide | Share of page darker than the threshold | `inkIsBackground` | Text rows, rule in force | Text rows, inversion suppressed |
| ---: | ---: | --- | ---: | ---: |
| 1 | 0.952 | yes | 4 | 0 |
| 5 | 0.976 | yes | 3 | 0 |
| 9 | 0.949 | yes | 6 | 0 |
| 12 | 0.513 | yes | 7 | 7 |

Slide 5 is the one #182 says "cannot be judged at all": with the inversion suppressed it measures
0 rows and 0 ink, so neither the drawn-text test nor the loss rule has anything to weigh. With
the rule in force it measures 3 rows, and the corpus contract already records the consequence —
slide 5 "reports `ocrUsed`, not `unverifiedTextLayer`", its recognized question checked word for
word against the rendered source. Slide 12, whose dark share is only 0.513 and whose dark ink
already forms rows, is untouched: a page the measurement can read is never inverted.

`aLightOnDarkPageIsJudgedForWritingAReadingLeftOut` in `TextLayerPlausibilityTests.swift` pins it
for #182: a light-on-dark page whose reading covered two of its ten rows reports eight uncovered
rows and `indicatesLoss`, identically to the same writing printed dark on white, and a reading
that covered every row reports no loss.

## Defect 1: the mechanism, measured

### The icon

`ntrs-20180003024-earthdata-slides-2018` slide 12 places six images. The one that matters is the
cloud, a 200 × 200 RGB JPEG with an eight-bit `/SMask` of the same size, placed at
`[57.4 168.7 66.3 66.3]`. Its mask is opaque only over rows 33–161 and columns 23–183, so the
drawing stands at `[64.7 181.3 54.0 42.8]` and **12.6 pt of the box's 66.3 pt height is
transparent margin**.

`Cumulus`, the first line of `Cumulus Data Archive`, has the rectangle `[62.1 163.8 59.8 13.1]`,
whose middle is y = 170.35. The drawing stops at y = 181.3, 4.4 pt above the *top* of that line.
The box reaches to y = 168.7, 1.65 pt below its middle. `LayoutReconstructor.takes` asks only
whether the crop holds the line's middle, so the box takes the word and the drawing would not.
This is exactly what #182 describes, and it is what the issue means by "a cloud icon's padding
ends where `Cumulus` begins".

### What main does with that page

It never gets there. Read on main, every one of the 21 slides reports **one** painted region, and
it is the whole slide:

```
SLIDE 12  bounds=(0,0,720,405)  graphics=1  pictures=6
  GFX[0] [0.0 0.0 720.0 405.0]
  CROP[0] [0.0 0.0 720.0 405.0]  takes= every one of the slide's 16 lines
```

The slide's full-bleed background is a filled non-rectangle path covering the page, and
`GraphicsReader` clusters every other paint into it. The deck has no per-figure crop for an
image's margin to grow out of; it has one page-sized crop, and that is why the slide keeps a
source-page image and reports `unverifiedTextLayer`. Main has no `layoutComesApart` and no
backdrop rule — [decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md) says so
in as many words ("What was not ported … `layoutComesApart` (#117), so an ordinary slide export
still reads as image-backed") — and #164's `paintsOnlyItsBackdrop` and `artBesideBackdrops` exist
only on the abandoned branch. #182's first defect was written against a tree where the backdrop
had already been dropped and the icons had become crops of their own.

Composing slide 12 as that tree would — its own paints minus the page-sized background — puts the
defect back, and is the reproducer:

| | Cloud icon's region | Crop grown from it | Lines it takes |
| --- | --- | --- | --- |
| placement box believed | `[57.4 168.7 66.3 66.3]` | `[57.4 161.8 66.5 73.2]` | `Cumulus` |
| drawing believed | `[64.7 181.3 54.0 42.8]` | `[64.7 181.3 54.0 42.8]` | none |

The crop *grows* 6.9 pt downward to swallow the whole of the line it met, which is #36's
whole-line expansion doing what it is for. Slides 13 and 14 are the same, twice each, because the
deck paints `Cumulus` over itself.

### Where else in the corpus an image's padding reaches a word

Over 5,302 pages of 24 cached documents, the survey finds **4,201 placed images**, 724 of them
carrying a soft mask and **204** carrying one in the plain form the reading admits (eight bits a
sample, no `/Decode`, no `/Matte`, decoded by Core Graphics to raw samples). Of those, 73 are
trimmed by more than a fiftieth and 51 by more than a tenth.

**22 lines in the whole corpus are taken by a crop although only an image's transparent margin
reaches them**, on two documents:

| Document | Lines |
| --- | --- |
| ntrs-20180003024-earthdata-slides-2018 | 19 — `Cumulus`, on slides 12–21 |
| dga-2025-2030 | 3 — `Vegetables`, `Whole`, `Grains`, on the cover |

Every other book has none: `cia-blue-book-14-1955`'s 312 scans,
`wallace-algebra-2010`'s plates, `gpo-our-flag-2003`, `gpo-911-2004`, `uscis-m618-arabic-2015`,
`irs-p596-zhs-2025` and all but one of `gpo-warren-1964`'s 1,839 images carry no soft mask at
all, and `faa-phak-8083-25c`'s 324 masks and `noaa-nca5-2023`'s 182 are JPEG-coded, which the
reading does not open — as are all 12 of `ntrs-20200002975`'s.

And on both of those two documents the crop that takes the word is **not** the image's. It is the
page-sized cluster: the deck's background fill, and the DGA cover's cream ground under 45 images.
Trimming the image changes neither.

## The change that was measured and not kept

The trim belongs in `GraphicsReader`, not in `LayoutReconstructor.captures`. By the time layout
sees the page, `page.graphics` holds *clustered* regions and an individual placement is no longer
separable; the only place an image's box exists on its own is the `Do` callback that records it.
The candidate added `GraphicsReader.paintedUnitBounds(_:)` — the reading described above — and
placed `unit.applying(s.matrix)` instead of the unit square, next to the clip rule that already
says an image's extent is not its ink (#52, #98). An image transparent everywhere was recorded
nowhere.

Eight tests exercised it against original one-page PDFs (a padded icon over a label, the same
icon drawn to its edges, no mask, a `/Decode` array, transparent everywhere, a clip over the
trim, the crop's take, and the label reaching the book). Four of the eight fail with the trim
removed and four pass — the four that pass are the controls, which is the split a real rule
should show.

### What it moved, per book

`tools/run_corpus_regressions.py --jobs 4`, baseline and candidate, both lanes read case by case
from `result.json` *and* `content-assessment.json`. EPUB bytes differ by a byte or two between
any two runs because the package carries a fresh identifier and date, so only a delta far outside
that counts.

| Case | EPUB bytes, baseline → candidate | Peak RSS, baseline → candidate | Lines moved |
| --- | --- | --- | ---: |
| arxiv-replay-clocks-2023 | 1,155,663 → 1,155,421 (−242) | 169 → 176 MiB | 0 |
| dga-2025-2030 | 4,775,721 → 4,775,718 | **112 → 216 MiB** | 0 |
| ntrs-20180003024-earthdata-slides-2018 | 3,223,679 → 3,223,683 | 105 → 103 MiB | 0 |
| every other case (15) | within two bytes | within host noise | 0 |

The page-by-page comparison of the two surveys — crops formed, crop area, and the lines each
crop takes, over all 5,302 pages — shows **one** page changed at all: `2311.07842v1` page 5, whose
crop area falls by 696 pt² and whose text does not move. **No page in any book takes or releases
a different line.** That is the whole benefit on today's main.

### What it cost

`dga-2025-2030` failed its contract's 192 MiB ceiling. Re-run serially, away from the lane's four
jobs, it still did: 229 MB peak RSS against the baseline's 118 MB, with every other gate passing
(`gatesPassedApartFromMemory: true`, EPUBCheck 0, structural check passed).

The cause is in the book, not in the lane. DGA's cover places 45 images whose soft masks are
1–13 megapixels each (3119 × 2572, 2901 × 3290, 3904 × 1367 …) and compress to about 30 KB
apiece, 0.6% of their samples, because the alpha is nearly uniform. Reading them decompresses
roughly 220 megabytes of alpha out of a 3.4 MB PDF. Wrapping the read in an `autoreleasepool`
changed nothing measurable (229.6 MB), so the buffers are held by Core Graphics for the
document's lifetime rather than leaked by the scope: the cost is structural in
`CGPDFStreamCopyData`, and there is no API that reports a mask's extent without decompressing it.

A per-page or per-image bound on mask samples would keep the ceiling — DGA's masks are large and
the deck's are 0.04 and 0.2 megapixels — but it would make which images are trimmed depend on the
order they are placed in, and it would buy a book nothing, because the benefit measured above is
zero lines.

### Why that is a refusal and not a deferral

The rule is right: a fully transparent margin paints nothing, and a crop grown from it removes a
word from a book for no reason. It is the same reading as the clip. But on main the only two
documents where an image's margin reaches a word are also documents whose crop is a page-sized
cluster, so the margin is never what takes the word; the change earns no book a word, moves one
crop by half a percent, and costs one book its memory ceiling. It becomes worth its cost the day
a backdrop rule drops a full-bleed background and the deck's icons become crops of their own —
which is the work #182's first defect was actually written against, and which main has not got.

## Defect 2: nothing to fix

"A backdrop page's connectors are decoration only inside a box" describes
`artBesideBackdrops(_:lines:bounds:)`, which classifies a backdrop page's non-image marks. Main
has no such function, no `paintsOnlyItsBackdrop`, and no backdrop page: `grep -rni backdrop
Sources/ Tests/ doc/` finds nothing. There is no arrow-outside-a-box case to widen, because no
arrow inside a box is dropped either. The defect is a gap in an unported change.

## Remaining

- Main still has no backdrop rule, so every slide of the deck keeps `unverifiedTextLayer` and a
  source-page image. That is [#175](https://github.com/vocaro/PDFReflowLib/issues/175)'s seventh
  item, which is open. #164, which the deck's slides and #182's first two defects all hang from,
  is closed as completed although its fix was never ported; decision 0005 records it as open.
- #182's first and second defects should be taken up with that port, where defect 1's fix has
  something to fix and its memory cost can be weighed against a measured gain.

## Gates

`scripts/check-all.sh --fast` on the committed tree: ten of ten gates pass (python-tool-tests,
measurements-policy, swift-tests, release-build, pdfkit-concurrency, documented-builds,
doc-counts, issue-citations, fixture-epubs, conversion-policies), exit status 0.

The corpus lane on the committed tree, `--jobs 4`: all 18 cases pass, exit status 0, and each
case's `result.json` and `content-assessment.json` were read — `runPassed` true, assessment
`passed` true and no assessment error on every one, EPUBCheck 0 on every one.

## Reproducing

```sh
swiftc -O Sources/PDFReflowLib/{AnchorMatcher,BlockAssembler,CGPDFObjects,CJKText,\
ChapterBoundaryReader,ContentStreamWalk,ConversionTypes,ConversionWarnings,DocumentEvidence,\
DocumentModel,EmbeddedImageReader,EnglishText,FractionRegionDetector,FurnitureDetector,\
GlyphIdentityReader,GlyphIndexDecoder,GraphicsReader,HyphenRepair,ImageContentClassifier,\
LayoutReconstructor,MarkedTextReader,NativeSpacingOwnership,NativeSpacingReader,NativeTextReader,\
NumberedNoteDetector,OCRReader,OCRTextCoverage,OutlineReader,PDFPageSource,PageDiagnosis,\
PageRasterizer,PageReader,PageTypography,RecognitionPolicy,ReflowDocument,SourceMetadata,\
StructureTreeReader,TableRegionDetector,TextEncodingCheck,TextLayerPlausibility,TextLineGeometry,\
XMLText}.swift measurements/image-alpha-padding/tools/survey-image-alpha.swift -o /tmp/survey-image-alpha
/tmp/survey-image-alpha /tmp/survey.json corpus/cache/*.pdf
```

`survey-image-alpha.swift` prints, per page, the crops `graphicsWithLabels` forms and the lines
they take, and, per placed image, the lines its placement box takes that its drawing does not
reach. It carries its own copy of the mask reading, so it builds against main with nothing added
to `Sources/`. It is diagnostic extraction only: no converter output, no rasters.
