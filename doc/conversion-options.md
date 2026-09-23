# Client-controlled conversion policy

Every conversion receives an independent `ConversionOptions` value. The library supplies
backward-compatible defaults; clients choose storage and fidelity tradeoffs for their product.
No policy changes dynamically to squeeze a book under a limit, and no network service is used.

| Control | Default | Choices / meaning |
| --- | --- | --- |
| `ocr` | `.automatic` | `.automatic`, `.automaticIncludingImageBackedText`, `.automaticKeepingImageBackedText`, `.always`, `.never` |
| `ocrLanguageCorrection` | `false` | `true` lets the recognizer correct words against its language model ([below](#language-correction)); for scans of plain prose only |
| `referenceImages` | `.automatic` | `.automatic`, `.always`, `.never` |
| `removeRepeatedHeadersAndFooters` | `true` | `true` omits detected running headers, footers and folios (`furnitureRemoved`); `false` keeps them in the text |
| `fullPageImageEncoding` | `.automatic(jpegQuality: 0.90)` | `.automatic(jpegQuality:)` (per-image choice, [below](#automatic-encoding)), `.png`, `.jpeg(quality:)`, `.smallest(jpegQuality:)` |
| `regionImageEncoding` | `.automatic(jpegQuality: 0.90)` | Same encodings, independently applied to cropped figures/tables/equations |
| `maximumOutputBytes` | 512 MiB | Positive entry-byte budget; `.max` effectively disables it |
| `maximumEPUBBytes` | `nil` | Optional positive cap on the actual final EPUB file, including ZIP overhead |
| `rasterDPI` | 180 | 72–600, subject to the pixel ceiling |
| `maximumRasterPixels` | 12 million | 1–48 million pixels per raster |
| `packageIdentifier` | `nil` | Non-blank `dc:identifier`, written verbatim (XML-escaped); nil writes a random `urn:uuid:` |
| `modificationDate` | `nil` | `dcterms:modified` and every ZIP entry date, 1980–2099; nil uses the conversion time |

MiB means 1,048,576 bytes. Input-byte, page-count and character budgets remain separate.
Neither output-size control is a RAM limit, device qualification or estimate of elapsed time.

## Existing text and selective OCR

`.automatic` recognizes absent or visibly damaged text, and existing text over a page-sized
graphic that fails the plausibility test below. Plausible inherited OCR errors can pass that
test. `.automaticIncludingImageBackedText` additionally retries existing text when
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

Recognition can also return success with whole paragraphs or table columns missing (#116). Every
recognized page is measured against its own text-shaped ink; a page the reading left writing on is
recognized once more in two overlapping bands, and the better-covering reading is kept. This costs
about 2% of a page's recognition time to check, and one extra recognition on each page that needs
it — on a scanned book of statistical tables that is a little over half again as long. A page
whose final reading still leaves the page's writing unread reports `incompleteRecognition` with
the share it left out.

### Implausible inherited text

Text inherited over a page-sized graphic (the pages that would report `unverifiedTextLayer`) is
tested before any recognition (#93): too few English words, too many words misread in place (#7),
or too little text for the page's own text-shaped ink fails the layer, and every failing page
reports `implausibleTextLayer` under every policy, with a message that says what failed and what
was done. The word classes, thresholds and message texts are specified in
[behavior](behavior.md#inherited-text-over-a-page-sized-image-93-7). Pages that require a page
image and books not declared English are not judged; without a system lexicon only the ink test
runs.

| Policy | A failing layer |
| --- | --- |
| `.automatic` | Replaced by OCR of the page image (the page also reports `ocrUsed`); a layer that fails only by misreading words in place is recognized again and compared, and kept when recognition reads no better |
| `.automaticIncludingImageBackedText`, `.always` | Replaced outright |
| `.automaticKeepingImageBackedText`, `.never` | Kept, with `unverifiedTextLayer` and its reference |

A client that wants the pre-#93 automatic behavior, recognition only of absent or damaged text,
selects `.automaticKeepingImageBackedText`. When recognition fails or finds no text the page is
preserved as an image (`ocrFailed` or `pageImageFallback`). Because recognition replaces the whole
layer, native reading order, styles and headings on a replaced page come from the recognized text.

Fresh recognition is itself judged against the same English test under every policy (#7): a
reading that still does not read as English (handwriting, or print recognition cannot read) is
discarded as noise, reported `implausibleRecognition`, and the page is preserved as an image; a
recognized line that does not read as English words is also excluded from heading detection
([behavior](behavior.md#every-recognition-is-judged-7)).

### Pages whose writing is drawn

A page whose text layer holds no letter at all, but whose own drawing (not its photographs)
carries rows of text-shaped ink, is recognized under every automatic policy like a page with no
text layer (#176); ink is measured against the page's own background, so a slide printed white
on dark is not mistaken for a blank one. Decorative art, charts and answer keys of bare surds keep
their crops. Recognition attaches the source-page reference in place of the crops; when it reads
nothing the page is left as extracted and reports `ocrFailed`. English books only. The row count,
resolution and exclusions are in [behavior](behavior.md#pages-whose-writing-is-drawn-176).

### Damaged text encoding

A born-digital page whose fonts carry a custom `Differences` encoding of index-style glyph names
with no `ToUnicode` map extracts as the wrong characters although it renders correctly (#38).
When such a font is present and the extracted words also fail the embedded English statistics,
the page reports `damagedTextEncoding`: `.automatic`, `.automaticIncludingImageBackedText`,
`.automaticKeepingImageBackedText` and `.always` recognize the page image instead and report
`ocrUsed`; `.never` keeps the unreadable native text and recommends a source-page reference,
which `referenceImages` controls like any other supplementary image. Only English is judged;
other declared languages, short pages, composite fonts and incorrect-but-present `ToUnicode` maps
are outside this signal, and a page this check explains is excluded from the two checks above.
The font and statistics rules are in [behavior](behavior.md#textencodingcheck-damaged-born-digital-encodings-38).

### Language correction

Vision can correct each recognized word against its language model. The library asks for that
only when `ocrLanguageCorrection` is `true`; the default is off, and it stays off because of what
it was measured to cost on the corpus's own English scans (#108). Across three independently
compiled model sets on Census, CDC, all 312 Blue Book pages and the Warren excerpt, correction
reads prose slightly better and damages what is not prose: codes and variable names (Census code
accuracy 72.5% → 65.0%, Blue Book 48.4% → 35.5%; `IL1` → `ILL`, `add10` → `add 10`), dates and
numbers (`11/21/54` → `11121/54`, `1950` → `11950`, `15.4` → `15. 4`) and names (the witness
`Euins` → `Buins`; `ruller`, the page's `Fuller`, → `ruler`). In the owner's review of the
changed tokens, fixes and damage came out about equal outside running prose, and a corrected
mistake reads as a real word, which is harder to catch than recognition noise. Because Census
sets prose beside codes on one page,
enabling it by book or by page is not supported either; the option is for a caller who knows the
scan is prose throughout.

With it on, every `ocrUsed` warning of the conversion says so ("Text is OCR transcription read
with language correction on: a misread code, number or name may have been changed to a plausible
word."), so a reader of the report can tell how the text was read. Nothing else about the
recognition moves with it: the same pages are recognized, at the same language. The developer
client takes `--ocr-language-correction on|off`; any other value is rejected without output.

The developer client exposes these policies as `--ocr automatic|image-backed|keep-image-backed|always|never`.
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
| Image encoding in general | The default, `.automatic(jpegQuality: 0.90)` | Classifies every image and permits lossy only where the ported rule's survey found it invisible at reading size. Over the 18 gated cases it writes 36.1% fewer image bytes with every image count and pixel size unchanged, 3,956 of 3,956 images kept as PNG identical pixel for pixel, and 36 of 442 JPEGs at a worst 8×8 edge-block error of 30 levels or more ([evidence](../measurements/image-encoding-default/record.md)). The rows below are for clients that want a fixed encoding instead. |
| Full-page scans | `.jpeg(quality: 0.90)` for tinted/noisy scans when lossy encoding is acceptable; compare PNG for clean black-and-white scans | Both 0.90 and 0.95 have whole-Warren size measurements and sampled visual comparisons. Use 0.90–0.95 as an initial tuning range; only the endpoints are measured. At 180 DPI, JPEG saves about 57% on two Warren pages but less than 1% on the checked Blue Book table page. |
| Equations, tables, cropped diagrams | `.png` | The clean table and colored fraction controls are smaller as PNG, with no encoding loss. Start lossless for these regions; other figure types may benefit from separate measurements. |
| Mixed full-page artwork | The automatic default; `.png` when no encoding loss is acceptable | Bare `.smallest(jpegQuality: 0.90)` avoids choosing a larger encoded file, but chooses by bytes, not legibility: on NOAA it sends 490 images to JPEG where the classifier sends 126, landing 117 MiB smaller by giving up chart and line-art crops (and, when measured, still 1.29× over the default budget; the book fits at defaults since the page-reference and embedded-image changes that followed, so the trade is no longer about the budget). Broad real-book visual qualification beyond the strips in the record remains outstanding. |
| Supplementary references | `.automatic` for a publication intended to carry its own source-page references | `.never` is a compact-reading choice when the client retains the PDF for review and accepts omitted visual context. Whole-book Warren runs quantify both choices; neither validates inherited OCR. Reserve `.always` for deliberate page-by-page reference use. |
| Resolution | Start at 180 DPI; compare 240 DPI for dense small print or fine diagram labels | A seven-page, six-document raster sweep shows sharper fine detail at 240, with about 47–49% more full-page image bytes than 180 at fixed encoding. At 120 DPI, small notes and labels have visibly coarser edges. This supports a targeted 240-DPI trial, not a universal range or device budget. Actual resolution can be reduced by the pixel ceiling. |
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
pages; archive the measured settings and results alongside each recommendation. JPEG quality
below 0.90, DPI choices outside the sampled 120/180/240 settings, full-book/OCR effects of
changing DPI, and physical-device raster budgets remain unqualified.

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

Every raster is drawn over an opaque white fill, so its alpha channel is a constant 255 plane.
It is relabeled opaque at write time, over the raster's own pixel buffer, so a PNG records three
channels instead of four; the raster handed to recognition keeps the format Vision is measured
against. This changes only the written file, never a pixel: across the corpus, 6,240 of 6,240
images that stayed PNG decode identically before and after, while PNG-only books lose 13% of
their image bytes.

### Automatic encoding

`.automatic(jpegQuality:)` is the default for both full pages and regions, at 0.90
(`ImageEncoding.automaticJPEGQuality`). Each image is classified from its own pixels before it is
encoded. Where lossy is permitted the image is encoded as `.smallest` would be, so it may still be
written as PNG; everywhere else it is written as PNG. Naming `.png`, `.jpeg(quality:)` or
`.smallest(jpegQuality:)` bypasses the classifier entirely, for pages and for regions.

Below quality 1.00 ImageIO halves both chroma planes, identically at 0.95 and 0.90; that, not
quantisation, is the damage that shows, and it shows only where there are sharp edges *in color*.
So lossy is permitted for:

- any image whose pixels are under 2% colored, measured against the image's own ground (a
  yellowed scan is neutral, and so is a mostly white chart with small colored labels);
- photographs and continuous-tone art, except a crop that is at least 30% perfectly flat, which is
  drawn illustration — saturated fills meeting labels at hard colored edges — and stays PNG;
- tonal text scans: a full-page reference of a page whose text is absent or lies over a page-sized
  image, made of type on a ground with tones in between;
- a full-page reference that is none of those (`mixed`), because its text is reflowed beside it.

It is refused for colored line art and charts, `mixed` crops, required page fallbacks that are
neither neutral nor tonal (a fallback is its page's only copy, so it is judged as a crop), and
colored bilevel scans and born-digital text pages. The thresholds were fitted to this corpus.

The classifier reads the raster from the drawing buffer before the `CGImage` is made, because
reading a finished image's pixels copies them. It costs a few milliseconds per crop and about
20 ms per page-sized raster; measured wall-clock cost over the gated cases was +28% on one run
each ([record](../measurements/image-encoding-default/record.md)).

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

Byte limits accept a positive integer or `unlimited`. Image encodings accept `automatic`,
`automatic:QUALITY`, `png`, `jpeg:QUALITY` or `smallest:QUALITY`. `--repeated-headers-and-footers remove|keep` sets
`removeRepeatedHeadersAndFooters`; without it, repeated headers and footers are removed.
`--ocr-language-correction on|off` sets `ocrLanguageCorrection`; without it, correction is off.
`--package-identifier ID` and `--modification-date ISO8601`
(for example `2026-01-01T00:00:00Z`) set the reproducible-package options. The internal reader
accepts PNG/JPEG publications; its independent admission budget can be set with
`tools/view_epub.py --maximum-bytes BYTES`.

## Language

`--language TAG` sets the BCP 47 tag the conversion declares. It becomes the package's
`dc:language`, the recognizer's language where Vision supports it, and the gate on every rule
that only holds for a declared English: the line-end lexicon vote, the Cyrillic look-alike
repair on recognized text, the inherited-layer, drawn-text and recognition judgments, the
damaged-encoding check, the recognized-line heading test, and the word tests that keep a book's
own prose out of its crops. The East Asian spacing and heading joins read the text's own script
and run whatever the tag says. The default is `en`. Vision lists only region- or script-qualified
languages (`ru-RU`, `zh-Hans`), so a bare code such as `ru` declares the language without reaching
the recognizer, which then reads at its own default.

A tag whose script is Cyrillic — `ru`, `ru-RU`, `uk`, `bg`, `sr`, `mk`, `be`, `kk`, decided by
the script the tag names or implies, so `sr-Latn` is not one — switches on the mirror of that
look-alike repair: an all-capital word Vision returned as Latin because every letter of it is
drawn the same as a Latin one (`KOMAP TAPA` for `КОМАР ТАРА`) is returned to Cyrillic, and so is
a token that mixes the two scripts (`MOСKВА`). The rule, what it leaves alone and the Latin word
it can mistake are in [behavior](behavior.md#ocrreader) (#108).

A malformed tag is rejected rather than converted as something else: the value must be ASCII
letters, digits and single hyphens, start with a letter, not end with one and be at most 35
characters. `en_US`, `zh--Hans` and an empty value all fail without writing output (#108).

Until this option existed every book converted as English, so `uscis-m618-arabic-2015` and
`irs-p596-zhs-2025` declared `dc:language` `en`. Since 2026-09-23 the corpus lane passes each
case's manifest `language` — `ar` for the Arabic guide and `zh-Hans` for the Chinese
publication — so both declare their own language, and the Chinese publication's tag reaches the
recognizer, while the Arabic guide's does not on this host, which lists `ar-SA` and not `ar`;
what the tag changes in each book is measured in their baseline records
([Arabic](../measurements/uscis-m618-arabic-2015-language-tag/record.md),
[Chinese](../measurements/irs-p596-zhs-2025-language-tag/record.md)). Every other case has no
field and converts at library defaults.

## Locked documents

A document that opens with a password converts when the caller supplies that password.
`ConversionOptions.password` is tried once, at every point the conversion opens the file — the
page window, the outline read and the structure tree all reopen it — and a document that does not
unlock still throws `ConversionError.encryptedPDF` (#252). A document that is not locked ignores
the option. An owner-password-only document, readable but permission-restricted, opens as it
always has; the option passes along a password the caller already has and defeats nothing.

The password is a secret for the conversion's lifetime. It reaches no report, warning, progress
event, CLI output or staged file, and `ConversionOptions.Password` redacts itself in
`description`, `debugDescription` and its mirror, so a client that logs or dumps the options it
passes around prints `<redacted>`. Swift strings cannot be wiped, so the value does outlive its
use somewhere in the process's memory; that is a property of the platform.

`pdf-reflow` takes `--password-file PATH`, or `--password-file -` to read standard input. There
is deliberately no `--password` argument: an argument is visible in the shell history and in the
process list to every other user of the machine. One trailing newline belongs to the file and is
removed; everything else, spaces included, is the password. A file over 4,096 bytes, one that is
not UTF-8, and one that states no password are each rejected before any conversion starts.
