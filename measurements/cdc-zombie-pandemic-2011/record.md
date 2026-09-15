# CDC comic baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated macOS arm64 release CLI.
Corpus: Preparedness 101: Zombie Pandemic, CDC, 2011; 42 pages, 8,448,697 bytes,
SHA-256 `d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3`.
Build: repository `156c7ac`, Xcode 27, macOS 27.0 (26A428),
`swift build -c release --scratch-path .build/corpus-cli`; executable SHA-256
`9fed7af9cb6872ef13a596f1df9512fb9236e66a67e43db96e3637a9eeb4a0e8`.

## Source and scope

The [CDC Stacks record](https://stacks.cdc.gov/view/cdc/6023) declares Public Domain and links
the PDF. Its published SHA-512 matches the supplied original. Automated fresh download returns
HTTP 403; the corpus fetcher verifies the manually seeded, ignored cache by bytes and SHA-256.
No source PDF or full EPUB is committed. Source and download receipts retain exact identities.

pypdf 6.10.0 extracts 3,341 whitespace-delimited tokens, including heavily damaged text, across
42 pages. This differs from the owner's approximate 2,000-word estimate; neither is a reliable
count of dialogue in the artwork. Nine pages have no extracted text. The source has no
structure tree. Pages 13 and 16 have image-only page streams; page 5 has text plus a page image.
`source-inspection.json` retains per-page token counts, selected operation counts and page text.
The extraction strings are evidence, not a reference transcription.

## Conversion and resource gate

The configured run completes in 6.91 seconds. Kernel peak RSS is 381,796,352 bytes (364.1 MiB),
below the 512 MiB regression ceiling. Sampled physical footprint is 216,237,040 bytes (206.2 MiB).
Only converter RSS is gated; separate Apple services and physical iOS devices are not measured.
The initial ungated run measures 383,844,352 bytes RSS and 7.41 seconds.

The EPUB is 149,719,138 bytes (about 17.7 times the compressed source size). It passes
EPUBCheck 5.3.0 with no errors or warnings. All 144 progress events pass monotonicity, bounds
and completion checks. The report counts 38 pages with reflowed text, nine OCR pages and
42 images. It reports 38 imageRegion, nine ocrUsed, four pageImageFallback and one
annotationsNotConverted warnings. These numbers do not establish dialogue recovery or fidelity.

Generated result, conversion, memory and EPUBCheck receipts are unchanged; the full progress
log is losslessly compressed with its original identity. A separate complete conversion prepares
seven review pages with Poppler 26.04.0. Exact XHTML comes from the measured baseline EPUB.

## Visual and textual evidence

Source rasters and three-pane rendered comparisons are checked on physical pages 5 and 13.
Other selected pages have exact XHTML and prepared comparison views, not full visual adjudication.

- Page 5 emits severely damaged inherited text as bold italic prose. The small upper-right
  reaction balloon is missing from extracted prose, though present in the original-page image.
  The only warning is imageRegion; no fresh OCR or suspect-text warning occurs. This extends
  [issue #7](https://github.com/vocaro/PDFReflowLib/issues/7).
- Page 13 has no native text. Fresh OCR places the lower-left response before the upper-right
  awakening exchange and promotes two dialogue fragments to h2 headings. One fragment includes
  Cyrillic-looking substitutions. The source page image survives, and ocrUsed is reported, but
  neither establishes narrative or speaker order. [Issue #18](https://github.com/vocaro/PDFReflowLib/issues/18)
  tracks panel/balloon grouping or readable image fallback with limited-reflow signaling.
- Page 16's XHTML contains noisy sign/logo fragments. Its presence in the reflow count must not
  be interpreted as successful understanding of artwork or complete dialogue recovery.
- Poppler positioned output keeps page geometry. On page 5 it overlays damaged extracted text
  onto the artwork; on image-only page 13 it displays the image. The original source raster is
  the visual authority, not the comparator's extracted text.

The baseline passes resource, progress and package checks, but fails the page 5 text-quality and
page 13 panel-order targets. The corpus review JSON contains manual acceptance targets for future
regressions, not passing automated dialogue assertions. Comic panels and meaning-bearing artwork
must remain readable; sparse text alone must not be interpreted as a mostly empty document.
