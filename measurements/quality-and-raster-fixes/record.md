# Quality signaling, attachment filtering and raster scaling

This measurement covers issues [19](https://github.com/vocaro/PDFReflowLib/issues/19),
[8](https://github.com/vocaro/PDFReflowLib/issues/8) and
[3](https://github.com/vocaro/PDFReflowLib/issues/3).
Runtime: macOS 27.0 arm64, Xcode 27, release CLI, library defaults. The executable SHA-256 is
`5275579f7a238cf38ebc591b74315f37b1cf9256a1ff7fed826a2951aba3dc96`.
[Implementation identities](implementation-sha256.json) identify the source changes atop
`896e283`; each evaluation embeds its source PDF identity and measured manifest case.

## Results

| Workload | Seconds | Peak converter RSS | EPUB bytes | Result |
| --- | ---: | ---: | ---: | --- |
| Full FAA, 522 pages | 38.67 | 801,128,448 (764.0 MiB) | 271,200,756 | EPUBCheck, progress, 1,280 MiB memory gate pass |
| Full Blue Book, 312 pages | 33.80 | 316,686,336 (302.0 MiB) | 213,824,597 | EPUBCheck, progress, 512 MiB memory gate and quality signal gate pass |
| Warren nine-page excerpt | 4.76 | 774,897,664 (739.0 MiB) | 14,825,317 | EPUBCheck passes; seven pages contain reflowed text |

These are single runs, not timing distributions or physical iPhone/iPad memory measurements.
RSS excludes separate Apple services. The Warren excerpt retains source resources from its
large original and is not a full-book completion or memory qualification. Resource ceilings
are unchanged. More detailed fallback images can increase output size.

### Unverified text layers

`unverifiedTextLayer` accompanies existing text over a graphic covering more than 75% of a
page, with an original-page reference image. The warning asks clients to review transcription,
tables, numbers and reading order. This is conservative provenance/uncertainty signaling,
not confidence estimation or a claim that each warned page contains an error.

The full Blue Book run reports the warning on all 312 pages, including reviewed pages 74 and
150. The [quality assessment](blue-book/quality-assessment.json) passes; the historical baseline
still fails this contract. The actual EPUB reference images for [page 74](blue-book-page-74.png)
and [page 150](blue-book-page-150.png) preserve the complete printed tables and are visually
reviewed. Their reflowed text remains unreliable; table reconstruction is not fixed.
The report has 312 pages with some reflowed text, zero fresh OCR pages and 422 images.
Those counts are coverage, not accuracy: removing large object-only selections changes layout
region grouping and exposes more text than the historical baseline's 227 reflowed pages.

### Attachment placeholders

U+FFFC becomes a word boundary at native extraction, in both plain and styled runs. Empty
selections are discarded before requesting attributed text, OCR policy selection, layout and
counting. Images remain independently preserved. A placeholder-only page can therefore use
fresh OCR, or image-only fallback if OCR is disabled or finds no text.

The checksum-verified Warren excerpt maps pages 1 and 9 to original pages 1 and 920. Both have
one image and no prose, headings or preformatted text. The report counts seven reflowed pages
and two OCR attempts; the blank images do not acquire invented transcription. No XHTML in the
full FAA, full Blue Book or Warren excerpt contains U+FFFC. [Selected page output](selected-pages.json)
and [assertions](fidelity-checks.json) retain the checks. This does not repair other OCR errors.

### Page-image scaling and annotation coordinates

On this host the old call to `getDrawingTransform` returns scale 1 with translation
(445.5, 580.5) for FAA page 121, despite a requested 1485 × 1935 destination for its 594 × 774
point box. Computing crop/rotation in page units and explicitly scaling to pixels removes the
extra margins. The [before raster](faa-page-121-before.png),
[corrected raster](faa-page-121-after.png), and [independent Poppler source render](faa-page-121-poppler.png)
retain real source margins, captions and figure labels.

At the recorded ink threshold, the source and corrected image occupy 81.89% of image width;
the old image occupies 32.79%. Source/corrected vertical ink bounds differ by one pixel.
This checks proportions, not pixel-perfect equivalence between renderers. Current FAA page 121
reflows with region images after earlier graphics improvements; this explicit whole-page probe
exercises its historically affected fallback transform separately from the current EPUB layout.

Annotations apply their own PDFKit crop/rotation. Undoing that extra mapping before drawing
keeps them aligned with Core Graphics content. Deterministic tests cover both rotated whole-page
annotations and unrotated region crops, in addition to the existing pixel ceiling.
Apple documents the respective [drawing transform](https://developer.apple.com/documentation/coregraphics/cgpdfpage/getdrawingtransform(_:rect:rotate:preserveaspectratio:))
and [annotation drawing coordinates](https://developer.apple.com/documentation/pdfkit/pdfannotation/draw(with:in:)).

## Reproduction and regression coverage

- `scripts/check-all.sh`: 41 Swift tests, 31 Python tests, six fixture conversions with EPUBCheck,
  and the full FAA conversion/memory gate. [Log](mac-gates.log.gz).
- `xcodebuild test -scheme PDFReflowLib-Package -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO`:
  all 41 Swift tests pass on the installed iOS 27 simulator. [Log](ios-tests.log.gz). This is not
  physical-device qualification.
- Six new regressions cover mixed/empty attachments, styles, OCR policy, warning reporting,
  image preservation, all four rotations, zero/nonzero crop origins, 36/180 DPI, a small raster
  budget and annotation alignment. All six fail against the three pre-fix implementation files
  from `896e283` in an isolated temporary package (30 assertions); the new warning enum remains
  available solely to compile the tests. [Negative control](before-tests.log.gz).

Full Blue Book reproduction uses the existing corpus fetcher and evaluator, followed by
`tools/check_corpus_quality.py --case cia-blue-book-14-1955 --evaluation <evaluation-directory>`.
The Warren excerpt identity and map are in [warren/excerpt-identity.json](warren/excerpt-identity.json);
its existing producer is `measurements/gpo-warren-1964/prepare-excerpt.py`.
All PDFs and complete EPUBs remain outside committed fixtures.

`verify-output.py` reproduces `fidelity-checks.json` and selected-page extraction. Pass
`--faa-evaluation`, `--blue-book-evaluation`, `--warren-evaluation`, the three PNGs as
`--before-raster`, `--after-raster`, `--source-raster`, and a new `--output` directory. It requires
Pillow only for development image comparison. It asserts no U+FFFC in XHTML, source images on
review pages, no prose on the two textless Warren pages, seven excerpt reflowed pages, and
corrected/source ink extents within 1% (with the old output failing the width expectation).

The source raster probe is [raster-probe.swift](raster-probe.swift). Compile it alongside
`PageRasterizer.swift`, `ConversionTypes.swift`, `DocumentModel.swift` and `ReflowDocument.swift`,
then pass the pinned FAA PDF. It writes `/tmp/faa-raster-{false,true}.png`.
The independent comparison command is:

```sh
pdftoppm -f 121 -l 121 -singlefile -scale-to 1935 -png \
  corpus/cache/faa-h-8083-25c.pdf /tmp/faa-raster-poppler
```

The PDFKit attributed-text leak investigation, stronger OCR assessment, table semantics and
reading-order defects remain open. No broad document-fidelity claim follows from these fixes.
