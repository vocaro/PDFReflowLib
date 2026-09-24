# CDC graphic novel: reviewed story-page image route (#18)

The source-reviewed [page map](cdc-reviewed-story-pages.json) applies to the 42-page CDC
*Preparedness 101: Zombie Pandemic* PDF, SHA-256
`d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3`.
The owner's source audit identifies wrong panel order on physical pages
4, 6, 7, 8, 11, 12, 13, 19, 21, 22, 24, 27, 29, 30 and 33. A page contact review shows the
illustrated story with speech balloons on pages 3–14 and 18–35. The wider reviewed map also includes
correct-order dialogue pages because the current OCR still turns speech into headings
on pages 3, 5, 9, 18, 23, 25, 26, 31, 32 and 34, and page 5's small `HUH?!` reads as `НИН?!`.
Selecting only the 15 wrong-order pages would leave those misread balloons as apparent prose and
headings. Page 13's lower-left response is still emitted before the upper-right awakening in
the default book; its selected image preserves their visible order without inventing a speaker.

The choice is explicit and source-specific. No raster classifier or OCR heuristic chooses these
pages. The [raster probe](reviewed-fallback-2026-09-24.md) saw strong center-crossing borders on
both wrong-order page 24 and correct-order page 26, while several other wrong-order pages have
irregular panels without that border signature. A default detector based on those borders would
miss affected pages or consume correctly reflowed material. The independent CDC *Coyote and the
Turtle's Dream* p11 has irregular comic panels and a usable native text layer, which a blanket
comic fallback would remove. The ordinary Census `rrs2002-01` p4 OCR reflows prose and headings;
a blanket scan fallback would remove those too.

## Reproduce

Verify the source SHA before applying the page list. The option uses **physical PDF page numbers**:

```sh
shasum -a 256 corpus/cache/cdc_6023_DS1.pdf
.build/release/pdf-reflow corpus/cache/cdc_6023_DS1.pdf /tmp/cdc-reviewed.epub \
  --reviewed-panel-pages 3,4,5,6,7,8,9,10,11,12,13,14,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35 \
  --package-identifier urn:uuid:00000000-0000-0000-0000-000000000018 \
  --modification-date 2026-01-01T00:00:00Z
epubcheck /tmp/cdc-reviewed.epub
```

The reviewed conversion on 2026-09-24 emitted 42 page markers and 42 page-associated images.
Each of the 30 selected pages had exactly one source-page image and no OCR dialogue in its XHTML
section. Twenty-nine images were 1530 × 1980 pixels; page 35 is a narrower 306.95 × 792 point
source page and its image was 767 × 1980 pixels. All 30 image assets were byte-identical to the
corresponding full-page reference image in a same-version default conversion. Each selected page
reported `reviewedPanelImage` and `pageImageFallback`, with text explaining that its dialogue does
not reflow or provide a verified reading order. The 12 unselected XHTML sections were byte-identical
to the default run, including the Part 2 title on p15, p36's ending illustration, p37's three
epilogue paragraphs, and p39's emergency checklist. EPUBCheck 3.3 reported zero errors and warnings.
Two same-environment reviewed runs with fixed package metadata produced identical EPUB SHA-256
`4e80430b64b56dd192051975ab01f7816b70ca02f69c95e1e4fcea4cf833eba7`. This does not
establish cross-environment pixel identity; the page choice depends only on the reviewed source
checksum and page numbers, not on raster decoding or Vision output.

The independent comic control used the CDC's public-domain
[*Coyote and the Turtle's Dream*, volume 1](https://stacks.cdc.gov/view/cdc/44241), SHA-256
`40b162990643bcf55092cff79b976012364b9b5f1801fdebeebc3f33ae04ce38`: p11 with
`--no-ocr` retained 20 reflowed paragraphs and no reviewed-page warning. The Census p4 control
had one recognized and reflowed page, 20 paragraphs, and no reviewed-page warning. Those controls
show the reviewed CDC map has no effect on other sources, while also exposing the cost of any
unqualified automatic comic or scanned-page fallback.

This is the issue's readable-image route. It preserves printed panel order and source-relative
balloon/speaker proximity for the reviewed book, but does **not** supply a transcript or accessible
speaker attribution. The 30 selected story pages lose text reflow, search, and screen-reader
dialogue. The 12 other pages keep their existing text behavior, including unrelated OCR errors.
Users converting another comic must review that source and provide its own page list; this map is
not a general comic detector.
