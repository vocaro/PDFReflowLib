# Client-controlled conversion policy

Every conversion receives an independent `ConversionOptions` value. The library supplies
backward-compatible defaults; clients choose storage and fidelity tradeoffs for their product.
No policy changes dynamically to squeeze a book under a limit, and no network service is used.

| Control | Default | Choices / meaning |
| --- | --- | --- |
| `referenceImages` | `.automatic` | `.automatic`, `.always`, `.never` |
| `fullPageImageEncoding` | `.png` | `.png`, `.jpeg(quality:)`, `.smallest(jpegQuality:)` |
| `regionImageEncoding` | `.png` | Same encodings, independently applied to cropped figures/tables/equations |
| `maximumOutputBytes` | 512 MiB | Positive entry-byte budget; `.max` effectively disables it |
| `maximumEPUBBytes` | `nil` | Optional positive cap on the actual final EPUB file, including ZIP overhead |
| `rasterDPI` | 180 | 72–600, subject to the pixel ceiling |
| `maximumRasterPixels` | 12 million | 1–48 million pixels per raster |

MiB means 1,048,576 bytes. Input-byte, page-count and character budgets remain separate.
Neither output-size control is a RAM limit, device qualification or estimate of elapsed time.

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
`jpeg:QUALITY` or `smallest:QUALITY`. The internal reader accepts PNG/JPEG publications; its
independent admission budget can be set with `tools/view_epub.py --maximum-bytes BYTES`.
