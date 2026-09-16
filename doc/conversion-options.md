# Client-controlled conversion policy

Every conversion receives an independent `ConversionOptions` value. The library supplies
backward-compatible defaults; clients choose storage and fidelity tradeoffs for their product.
No policy changes dynamically to squeeze a book under a limit, and no network service is used.

| Control | Default | Choices / meaning |
| --- | --- | --- |
| `ocr` | `.automatic` | `.automatic`, `.automaticIncludingImageBackedText`, `.always`, `.never` |
| `referenceImages` | `.automatic` | `.automatic`, `.always`, `.never` |
| `removeRepeatedHeadersAndFooters` | `true` | `true` omits detected running headers, footers and folios (`furnitureRemoved`); `false` keeps them in the text |
| `fullPageImageEncoding` | `.png` | `.png`, `.jpeg(quality:)`, `.smallest(jpegQuality:)` |
| `regionImageEncoding` | `.png` | Same encodings, independently applied to cropped figures/tables/equations |
| `maximumOutputBytes` | 512 MiB | Positive entry-byte budget; `.max` effectively disables it |
| `maximumEPUBBytes` | `nil` | Optional positive cap on the actual final EPUB file, including ZIP overhead |
| `rasterDPI` | 180 | 72–600, subject to the pixel ceiling |
| `maximumRasterPixels` | 12 million | 1–48 million pixels per raster |
| `packageIdentifier` | `nil` | Non-blank `dc:identifier`, written verbatim (XML-escaped); nil writes a random `urn:uuid:` |
| `modificationDate` | `nil` | `dcterms:modified` and every ZIP entry date, 1980–2099; nil uses the conversion time |

MiB means 1,048,576 bytes. Input-byte, page-count and character budgets remain separate.
Neither output-size control is a RAM limit, device qualification or estimate of elapsed time.

## Existing text and selective OCR

`.automatic` recognizes absent or visibly damaged text. Plausible inherited OCR errors can
pass that test. `.automaticIncludingImageBackedText` additionally retries existing text when
a detected graphic covers more than 75% of page area, using the same conservative signal as
`unverifiedTextLayer`. This opt-in policy replaces the entire selected page's native text with
fresh Vision transcription; it does not compare spellings or choose the more accurate version.
Pages with ordinary native text and smaller illustrations keep their native text and styles.
`.always` retries every eligible page; `.never` disables recognition. Rotated or unsupported
pages still use required image fallback under every policy.

The image-area signal can also select valid text over full-page artwork. It can miss cropped
scans and pages assembled from smaller images. Fresh OCR may improve some errors and introduce
others, lose native formatting, or change reading order. Successful attempts report `ocrUsed`
and include source references by default; empty or failed recognition retains a required page
image. Compare with the source before relying on transcription. Reference and resource options
apply independently, and cancellation remains cooperative during platform recognition.

A born-digital page can also lose its text without any scan: fonts with a custom `Differences`
encoding of index-style glyph names (`G108`, `c63`) and no `ToUnicode` map render correctly
but extract as the wrong characters (the Census report's LaTeX pages come out shifted by three
letters). When the page has such a font and its extracted words fail the embedded English
statistics (at least 20 words, under 5% function words, at least 30% uncommon letter pairs),
the page reports `damagedTextEncoding`. `.automatic`, `.automaticIncludingImageBackedText`
and `.always` recognize the page image instead and report `ocrUsed` as usual; `.never` keeps
the unreadable native text and recommends a source-page reference, which `referenceImages`
controls like any other supplementary image. Only English (`en`, `en-*`) is judged; other
declared languages, short pages, composite fonts and incorrect-but-present `ToUnicode` maps
are outside this signal. See the [damaged-encoding measurements](../measurements/damaged-text-encoding/record.md).

The developer client exposes these policies as `--ocr automatic|image-backed|always|never`.
`--no-ocr` remains an alias for `--ocr never`; when repeated, the last OCR option takes effect.
See [selective OCR measurements](../measurements/selective-ocr/record.md) for the pinned Warren
excerpt, native controls, timings and limitations. These measurements do not qualify whole-book
accuracy or physical-device budgets.

## Recommended starting settings

Client control and useful defaults work together. Recommendations follow measured document
classes; the API's permitted range is not a claim that every setting produces good output.
The current recommendations are provisional where evidence covers only selected sources.

| Dial | Recommended starting point | Evidence and qualification |
| --- | --- | --- |
| Full-page scans | `.jpeg(quality: 0.90)` for tinted/noisy scans when lossy encoding is acceptable; compare PNG for clean black-and-white scans | 0.90 and 0.95 have whole-Warren size measurements; the [17-page qualification](../measurements/raster-qualification/record.md) measures 0.60–0.95 on six scans and six figure pages. Use 0.75–0.90 as the measured range: at 180 DPI the six scans are −52% (0.75) to −41% (0.90) of PNG with no measured change in Vision phrase recovery, glyph coverage, contrast or color; 0.60 saves more (−62%) but shows faint halos on colored labels, and the typewritten Blue Book table saves only 5–15%. |
| Equations, tables, cropped diagrams | `.png` | The clean table and colored fraction controls are smaller as PNG, with no encoding loss. Start lossless for these regions; other figure types may benefit from separate measurements. |
| Mixed full-page artwork | `.png` until reviewed, or explicitly trial `.smallest(jpegQuality: 0.90)` | Smallest avoids choosing a larger encoded file, but chooses by bytes, not legibility. Its clean/noisy controls pass; broad real-book visual qualification remains outstanding. |
| Supplementary references | `.automatic` for a publication intended to carry its own source-page references | `.never` is a compact-reading choice when the client retains the PDF for review and accepts omitted visual context. Whole-book Warren runs quantify both choices; neither validates inherited OCR. Reserve `.always` for deliberate page-by-page reference use. |
| Resolution | Start at 180 DPI; compare 240 DPI for dense small print or fine diagram labels; do not go below 150 DPI for scans with small type | Seventeen pages at 96–300 DPI and four complete books at 120/180/240: full-page bytes are −63/−47/−28% at 96/120/150 and +49/+94% at 240/300 relative to 180. Vision finds none of the tiny Warren notes at 96 or 120, 3 of 9 at 150, 5 at 180, 6 at 240 and 8 at 300; body-size scan text is recovered from 150 up and born-digital labels at every setting. Changing DPI changed only image bytes, elapsed time and the OCR wording of 1–3 already-OCR'd pages per book; no gate, warning or text contract changed. This is not a device budget, and the pixel ceiling can still reduce actual resolution. |
| Raster pixel ceiling | Keep the 12-million-pixel starting bound while profiling the target device | There is no qualified physical iPhone/iPad memory range. The supported 1–48 million range is not a safe-device recommendation. |
| Output budgets | Choose separate entry and final-file caps from the client's storage allowance and measured workload, with headroom | The 512 MiB entry default is a configurable guard, not a measured universal recommendation. A file can pass its final ZIP cap while exceeding the entry cap. Disabling the entry budget in an experiment is not a general shipping recommendation. |

The [encoding experiment](../measurements/warren-image-encoding/record.md) records the JPEG
endpoint comparisons and clean-region controls. The
[production policy measurements](../measurements/client-options/record.md) record full-book
reference inclusion/omission, runtime, memory, image retention and warning checks. Their
source checksums, implementation identities and OS/hardware details bound these conclusions.
The 64 MiB and 512 MiB final-file caps in those runs demonstrate successful configurations
for that book; they do not establish recommended caps for all books.

The [raster-DPI comparison](../measurements/raster-dpi/record.md) separates resolution from
encoding on tinted scans, handwritten and clean numeric tables, colored diagram labels,
photographs beside text, and equations. Each PNG/JPEG pair comes from the same production
raster. The clean table and equation crops stay smaller as PNG; the FAA colored-label crop
gets smaller as JPEG but acquires visible edge artifacts. Review labels at the intended reading
size before choosing a lossy region policy. These are sampled raster results, not whole-book
conversion, OCR-accuracy or EPUB-size measurements.

`rasterDPI` is a requested resolution. The pixel ceiling applies to each full page or cropped
region independently. A 12-million-pixel ceiling does not bind these pages at 240 DPI; a
separate 1-million-pixel control reduces the FAA full page to about 106 DPI while its small
crop still reaches about 239 DPI after pixel rounding. Raising DPI alone cannot overcome a
binding pixel ceiling. That control explains the behavior; it does not recommend lowering the
ceiling or increasing it without profiling the target device.

The [complete NOAA comparison](../measurements/noaa-output-policies/record.md) illustrates why
the scan recommendation does not predict every large report. With automatic references and
PNG regions, PNG and JPEG 0.90 full pages both complete all 1,834 pages under explicit 4 GiB
entry/final caps. JPEG reduces the final EPUB by only 4.20 MiB (1,398.34 to 1,394.14 MiB),
while increasing uncompressed entries by 6.00 MiB. All 10,389 cropped PNGs remain identical.
The default 512 MiB entry budget still fails. The larger caps are experimental configurations,
not new defaults or recommended device budgets; selected image review does not qualify the book.

Two useful client configurations follow from that evidence. These are documented starting
configurations, not additional preset APIs or automatic document classifiers:

| Use | References | Full-page encoding | Region encoding |
| --- | --- | --- | --- |
| Scanned reading copy with embedded references | `.automatic` | `.jpeg(quality: 0.90)` | `.png` |
| Compact reading copy with the source PDF retained separately | `.never` | `.jpeg(quality: 0.90)` | `.png` |

For either configuration, start at 180 DPI, review a 240-DPI trial when small detail matters,
and select storage caps separately. Keep PNG for
full pages when avoiding encoding loss matters more than their measured size. Omitting
references still retains required fallback pages, region images and quality warnings.

The library's runtime defaults remain unchanged while the recommendations are evaluated more
broadly. Revising defaults or widening recommended ranges requires cross-document size and
readability comparisons, the corpus regression gate, and target-device measurements for
resource claims. Include scan text, fine colored labels, equations, tables and image-heavy
pages; archive the measured settings and results alongside each recommendation. The
[raster qualification](../measurements/raster-qualification/record.md) covers JPEG 0.60–0.95
and 96–300 DPI on 17 pages and 120/180/240 DPI on four complete books on one Mac;
`tools/raster_sweep.py` reruns that page sweep on any reviewed target list. Physical-device
raster and memory budgets, whole-book behaviour at 96/150/300 DPI, the two books that still
fail the default output budget, and reader-facing legibility beyond the Vision proxy remain
unqualified. The corpus reference-image checks assume 180 DPI, so a changed default also needs
regenerated references.

## Supplementary references versus required images

Automatic references accompany fresh OCR, inherited text over a page-sized graphic, or visible
annotations. Always includes a reference on every reconstructed page. Never omits these
supplementary images without suppressing OCR, unverified-layer or annotation warnings. When
analysis recommends a reference that the client omits, `referenceImageOmitted` identifies the
source page and directs review to the PDF; warnings do not claim an absent image exists.

Reference policy does not remove figure crops or the only readable representation of a page.
Rotated, unsupported or unrecoverable pages retain one required full-page fallback, even under
`.never`; `.always` does not duplicate it. These pages report `pageImageFallback`. Opting out of
supplementary references may lose visual context or unrecognized artwork around OCR text.

## Encoding

Full-page encoding applies to both supplementary references and required fallbacks. Region
encoding applies to preserved crops, including equations and tables. Both are represented as
file-backed assets in the output-independent document model; EPUB serialization emits the
matching file extension and media type.

JPEG quality must be finite and in 0...1. This is an ImageIO encoder setting, not a percentage
of fidelity. Even quality 1 is lossy. Changing encoding does not resize the source raster or
validate OCR. Raster DPI and pixel bounds control resolution separately.

Smallest encodes both PNG and JPEG at the requested quality and retains whichever file has
fewer bytes (PNG on ties). It costs another encoding pass and temporarily stores both encodings
of one raster. It does not compare visual quality or guarantee the smallest final ZIP size.
Only the chosen asset contributes to the entry budget. The rejected candidate is removed;
cancellation or failure cleans the conversion workspace.

The [Warren experiment](../measurements/warren-image-encoding/record.md) demonstrates why these
are independent choices: JPEG reduces scanned-page storage, while the clean numeric table and
fraction controls encode more compactly as PNG. No source-specific preference is hardcoded.

## Size limits and publication

`maximumOutputBytes` checks cumulative image bytes during reconstruction and all entry bytes
before ZIP compression during packaging. Its 512 MiB default is an initial engineering budget,
not a format limit. Set a larger positive value or `.max` when the client permits more storage.

`maximumEPUBBytes` checks the completed ZIP before its atomic move to the requested destination.
It includes archive overhead. A failed cap check throws `ConversionError.resourceLimit`, removes
staging, leaves no new destination and emits no completed/100% progress event. This cap does not
bound temporary disk usage: the archive must be built before its final length is known. Keep an
entry-byte budget when a client also needs a bound on intermediate output content.

Both limits apply when set. A ZIP smaller than the final-file cap can still exceed the entry
budget. The library never silently drops images, reduces quality, or changes the client's policy
after a size failure.

## Reproducible packages

By default each conversion writes a random package identifier, the current time as
`dcterms:modified`, and the current time in every ZIP header, so identical content still yields
different EPUB bytes. Setting both `packageIdentifier` and `modificationDate` removes that
writer-introduced variation: converting the same PDF twice with the same binary and environment
produces the same SHA-256. Entry order and names come from the writer, not directory enumeration.
ZIP headers store the date in UTC at two-second resolution, independent of the local time zone.

This covers packaging only. Rendering, OCR and image encoding can still differ across OS builds
or device capabilities (#26). A client pinning output bytes should record the converter revision
and OS build alongside the digest and treat a mismatch as a reason to re-convert.

## Developer client

The same options are available through `pdf-reflow --help`. For example:

```sh
swift run pdf-reflow input.pdf output.epub \
  --reference-images never \
  --full-page-image-encoding jpeg:0.9 \
  --region-image-encoding png \
  --maximum-output-bytes unlimited \
  --maximum-epub-bytes 536870912
```

Byte limits accept a positive integer or `unlimited`. Image encodings accept `png`,
`jpeg:QUALITY` or `smallest:QUALITY`. `--repeated-headers-and-footers remove|keep` sets
`removeRepeatedHeadersAndFooters`; without it, repeated headers and footers are removed.
`--package-identifier ID` and `--modification-date ISO8601`
(for example `2026-01-01T00:00:00Z`) set the reproducible-package options. `--raster-dpi DPI`
(72–600) and `--maximum-raster-pixels PIXELS` (1–48,000,000) set `rasterDPI` and
`maximumRasterPixels`; the library defaults of 180 DPI and 12 million pixels apply when they are
omitted. The internal reader
accepts PNG/JPEG publications; its independent admission budget can be set with
`tools/view_epub.py --maximum-bytes BYTES`.
