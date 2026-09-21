# A figure that is one embedded JPEG is written as that JPEG

Measured under [#251](https://github.com/vocaro/PDFReflowLib/issues/251), baseline `530024a`,
2026-09-20, macOS 27 / Xcode 27, arm64, release CLI at library defaults.

Every image in an output book was a re-render: `PageRasterizer` redrew the region from the page
at `rasterDPI` and re-compressed it, and nothing in `Sources/` ever called `CGPDFStreamCopyData`.
Where a figure *is* one embedded JPEG, that is paying an encode to produce a worse picture, and
no `rasterDPI` setting could reach the source's own quality, because the ceiling was the render.

## What the corpus embeds

Every placed image XObject in the twenty-one cached documents, by filter:

| Filter | Documents | Note |
| --- | --- | --- |
| `DCTDecode` | NCA5 (181), NASA slides (273), CDC (36), DGA (55), magazine (29), 9/11 (34), NBS (7) | extracted where the rest of the conditions hold |
| `JPXDecode` | Warren (1,198), FAA (378), USCIS (83), Fed (19) | JPEG 2000 is not a file a reader opens; rendered |
| `FlateDecode` | arXiv (34), FAA (117), Wallace (26), NCA5 (10) | raw samples, not a file; writing them would be a re-encode, not an extraction |
| `CCITTFaxDecode` | CIA Blue Book (312), 9/11 (10) | rendered |
| `JBIG2Decode` | CDC (6), FAA (1) | rendered |

The colour space decides as much as the filter. Almost every `DCTDecode` image in the corpus is
`[/ICCBased …]` — the magazine's 29, NCA5's 46 sampled, the CDC report's 36 — and only the NBS
paper's seven are a device space. Refusing ICC-based images would have made this change a no-op
on the corpus, so the profile is read from its stream and written into the extracted file as APP2
segments, which is what keeps the colours the ones the page states. A profile over a mebibyte, or
one needing more than 255 segments, falls back.

## What it costs, and what it gains

`usda-ars-agresearch-2012-11`, the one lane document with extractable figures, eight of them:

| Asset | Rendered | Extracted | Rendered pixels | Source pixels |
| --- | ---: | ---: | --- | --- |
| image-14 | 131,058 | 21,750 | 656 × 579 | 365 × 322 |
| image-21 | 441,802 | 58,597 | 1349 × 1079 | 750 × 600 |
| image-26 | 301,569 | 42,143 | | |
| image-29 | 438,792 | 60,693 | | |
| image-39 | 163,701 | 28,456 | | |
| image-40 | 171,339 | 28,617 | | |
| image-42 | 350,231 | 37,324 | 889 × 1324 | 495 × 736 |
| image-44 | 318,180 | 38,526 | | |
| **total** | **2,316,672** | **316,106** | | |

That book's images fall from 21.69 MB to 19.69 MB. The gain is not compression: the render was
*upsampling*. A 365 × 322 photograph placed at 146 × 129 points was redrawn at 656 × 579 and
re-encoded, six times the bytes for pixels the source never had. Extraction writes the pixels the
page draws.

Where a source image is higher resolution than the render — a 600 DPI plate — extraction gives
more detail and more bytes, which is why the byte budget is checked against the real size before
the asset is committed and the render is the fallback when it does not fit.

NCA5, which the lane excludes on its output budget (#242), writes 275 extracted originals among
its 1,629 images.

## The safe set

One placed image, covering at least 98% of the crop and covered by it to the same degree, with
nothing else of the page's pictures touching that crop; placed without rotation or skew on an
unrotated page; `DCTDecode`; no soft mask, colour-key mask, stencil or `/Decode` array; eight
bits a component; device RGB or gray, or ICC-based with one or three components; and a JPEG whose
own frame header states the same size and component count the image dictionary does. A page whose
content stream the walk could not follow to the end extracts nothing at all, rather than part of
what it places.

Full-page assets are never extracted, although the largest single win would be a scanned page:
a page image stands for everything on that page, and a page can draw text and annotations over a
photograph. That is left where it was.

A client that named `.png` for regions gets the render it asked for. `.automatic`'s classifier is
bypassed rather than consulted, because an extracted original has already made that choice.

## Validation

484 Swift tests pass, five new, including the refusals: a masked image, a decode array, an
indexed and a CMYK space, a dictionary that misstates the size, and a budget too small for the
original. EPUBCheck 3.3 reports no errors on the magazine. The corpus lane passes 16 of 18 with
no content-contract failures.
