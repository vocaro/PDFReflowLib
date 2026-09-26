# Census maths pages: nothing in the file identifies the glyphs that keep them on recognition

Measured under [#297](https://github.com/vocaro/PDFReflowLib/issues/297) item 1, on `2bff36c6`,
2026-09-25, macOS 27 / Xcode 27, arm64. Source: `corpus/cache/rrs2002-01.pdf`, SHA-256
`0f97380ae4308581bd70013b7317faafd7c217654236bd31d1448f26eae56905`. MuPDF `mutool` and fontTools
4.63 for the file's own structures; a throwaway Swift Testing harness (below) for the library's own
per-page diagnosis. No library code changes with this record.

## The question

The Census contract lists pages 4–9 and 18–20 as keeping `damagedTextEncoding` and recognition, and
#149 added 10, 11, 13 and 14. `80de1223` ([glyph-index-decoding](../glyph-index-decoding/record.md))
established that the `cm` maths fonts' offsets cannot be read from the document's words, and
`0046fdd` that decoding `cmmi` alone unlocks no page. What remained was glyph identity from the
font programs themselves: glyph names, or charstrings. Item 1 is resolved when each listed page
either reads natively or is shown to depend on glyphs the file does not identify.

## What each font can say about its glyphs

`page-fonts.py` (in this directory) lists every glyph each page draws, by font, with the name the
font gives it; `glyph-outlines.py` compares the outline of every glyph of the maths fonts with
every glyph of the fonts the document's words establish (`dcr`, `dcbx`, `dcti`, `dctt`, read at
`G<n>` = Cork code + 3, #143/#226).

| Font | Program | Glyphs drawn | Names | Names stating a character | Outlines shared with an established glyph |
| --- | --- | ---: | --- | ---: | --- |
| `cmmi10084` | CFF | 497 | `G33` … `G168` | 0 of 50 | 0 of 50 (one has the same operators as `dcr`'s `.`, 244 units away) |
| `cmr10084` | CFF | 390 | `G25` … `G123` | 0 of 24 | **15 of 24 identical** (0 units) to `dcr`'s glyph at the same `G<n>`: `(`, `)`, `0`, `2`–`5`, `C`, `a`, `i`, `l`, `m`, `n`, `o`, `r`; six more have the same operators as `dcr`'s glyph at the same `G<n>` but differ by 24 to 64 units (`1`, `P`, `x`, `v`, `g`, `%`) |
| `cmsy10084` | CFF | 96 | `G3` … `G115` | 0 of 10 | 0 of 10 |
| `cmex10084` | CFF | 122 | `G3` … `G117` | 0 of 25 | 0 of 25 |
| `cmmib10084` | CFF | 1 | `G66` | 0 of 1 | 0 of 1 |
| `T2`–`T6` | Type 3 | 292 | `c<code>` (`c59`, `c105`, …) | 0 of 29 | — (each `CharProc` draws an inline bitmap, `BI /W 17 /H 40 …`, resources `/ProcSet [/PDF /ImageB]`) |

None of these fonts has a `ToUnicode`. Their descriptors state no more than `/Flags 4` (`/Flags 68`
and an italic angle for `cmmi` and `cmmib`) and `/StemV 0`. The CFF Top DICTs give only `FontMonger:<family>`. The Type 3
fonts are dvips's bitmap fonts: they carry no program, no `BaseFont` and no family, and a `c<code>`
name says only the code, whose meaning depends on the TeX encoding of a font the file never names.

So glyph names identify nothing, and outlines identify one font, `cmr`: its glyphs share `dcr`'s
index numbering and, for the glyphs the two fonts have in common, `dcr`'s exact outlines, which
corroborates `+3` for `cmr` from the document's own font programs. `cmmi`, whose letters and Greek
FontMonger numbers at different offsets (+0 and +134/+136, #226's render), matches no established
glyph at all: its math-italic outlines are not `dcti`'s text italic.

## What each page needs

The harness ran `PageReader.read` and `PageDiagnosis.assess` on each page at library defaults and
printed the counts `assess` weighs: a page is damaged when U+FFFD replacements plus `unreadGlyphs`
exceed `max(2, characters / 50)`.

| Page | Characters | Allowance | Replacements | Unread | Glyphs of fonts nothing identifies | `cmr` glyphs | Replacements if every `cmr` glyph were read | Outcome |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 4 | 2,617 | 52 | 105 | 0 | 70 | 35 | ≥ 70 | stays damaged |
| 5 | 2,241 | 44 | 85 | 125 | 70 | 33 | ≥ 52, + 125 unread | stays damaged |
| 6 | 2,936 | 58 | 151 | 0 | 124 | 65 | ≥ 86 | stays damaged |
| 7 | 2,947 | 58 | 83 | 0 | 69 | 21 | ≥ 62 | stays damaged |
| 8 | 2,453 | 49 | 95 | 88 | 119 | 23 | ≥ 72, + 88 unread | stays damaged |
| 9 | 2,290 | 45 | 118 | 0 | 120 | 64 | ≥ 54 | stays damaged |
| 10 | 1,808 | 36 | 31 | 0 | 88 | 59 | — | native already |
| 11 | 2,691 | 53 | 14 | 0 | 10 | 4 | — | native already |
| 13 | 2,674 | 53 | 8 | 0 | 6 | 2 | — | native already |
| 14 | 2,181 | 43 | 4 | 0 | 3 | 1 | — | native already |
| 18 | 2,124 | 42 | 98 | 186 | 139 | 37 | ≥ 61, + 186 unread | stays damaged |
| 19 | 1,294 | 25 | 135 | 124 | 165 | 31 | ≥ 104, + 124 unread | stays damaged |
| 20 | 295 | 5 | 30 | 0 | 23 | 15 | ≥ 15 | stays damaged |

"Glyphs of fonts nothing identifies" counts every glyph the page draws in `cmmi`, `cmsy`, `cmex`,
`cmmib` and the Type 3 fonts; the replacements left if `cmr` were read subtract every `cmr` glyph
the page draws, which is the most reading it could remove. Page 16 (#149, FB24908790) and page 2's
two stray glyphs are outside this item.

**No listed page can return to its own text.** On every page that recognition carries, the glyphs
nothing in the file identifies leave more replacements than the page's allowance, whatever is done
with `cmr`. Pages 10, 11, 13 and 14 already read natively, with their `cmmi` and `cmr` glyphs as
U+FFFD. Page 20's expected sentence, `and for diﬀerent noise proportion parameters d, we compute a
masked data set`, holds the `cmmi` `d` (`G100`), which no evidence in the file names, so the
native reading of that sentence cannot exist; recognition reads it.

## What was not done, and why

Reading `cmr` at `dcr`'s offset on the strength of the shared outlines is sound evidence, but it
unlocks no page, and on the native pages it reaches it would turn only the `cmr` glyph of a mixed
run into a character: page 11's `IL1`, `IL1s` and `1%` would read `��1`, `��1�` and `1%`, pages 13
and 14 two and one glyph. It would also need a Type 2 charstring interpreter in the library: the
matched programs are not byte-identical (their widths and hints differ), only their outlines are.
No issue is filed for it, because no page is decodable in principle.

## Result

Item 1 is resolved by measurement: the maths pages stay on recognition because the source states
no identity for the glyphs that put them there. `doc/behavior.md` (*GlyphIndexDecoder*, *Where the
document states nothing*) and the Census contract's `basis` say so. The contract's page 20 pin,
`warningCodesAnyOf: damagedTextEncoding`, stands.

## Commands

```sh
python3 measurements/census-math-glyph-identity/page-fonts.py corpus/cache/rrs2002-01.pdf
python3 measurements/census-math-glyph-identity/glyph-outlines.py corpus/cache/rrs2002-01.pdf
mutool show corpus/cache/rrs2002-01.pdf 59     # T3: /Encoding 75, /CharProcs 76, /Resources 74
mutool show corpus/cache/rrs2002-01.pdf 84     # one T3 CharProc: an inline bitmap
mutool show corpus/cache/rrs2002-01.pdf 146    # a descriptor: /Flags 4, /StemV 0
```

The harness, a Swift Testing test run once and not committed:

```swift
let source = try PDFPageSource(url: URL(fileURLWithPath: path))
for index in 0..<20 {
    let extracted = try PageReader.read(pageIndex: index, from: source, limit: 1_000_000,
                                        options: ConversionOptions(), structure: nil)
    let raw = extracted.content.lines.map(\.text).joined()
    let replacements = raw.unicodeScalars.filter { $0.value == 0xFFFD || $0.value == 0xFFFC }.count
    let evidence = try PageDiagnosis.assess(extracted, options: ConversionOptions()) { _ in nil }
    print(index + 1, raw.count, max(2, raw.count / 50), replacements, extracted.unreadGlyphs,
          evidence.damagedEncoding)
}
```
