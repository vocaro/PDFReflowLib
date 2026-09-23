# IRS Publication 596 (Simplified Chinese): baseline on the tagged lane

Tier: deterministic Apple PDF/OCR stack, isolated release CLI on macOS 27.0 (26A428) arm64,
Xcode 27.0 (27A266a), EPUBCheck 5.3.0. Build: `8faeaab`, `swift build -c release`, executable
SHA-256 `497df75a3954f6c475ef9f6afe480ff695a30fad4b14254ddc6d4ec26d951cad`. Source: *Publication
596 (ZH-S), Earned Income Credit (EIC), 2025*, 36 pages, 2,674,617 bytes, SHA-256
`7d1cff45bc567f1257ea1aa1e2ce67945aafb12708b2e22901ce6392436590c2`.

The owner ruled on #293 (2026-09-23) that the corpus lane passes each case's language. This
book's manifest entry now declares `language: "zh-Hans"`, and `tools/evaluate_real_document.py`
adds `--language zh-Hans` to every conversion of it. This record is the book's baseline on that
lane: three conversions on one binary — untagged, a second untagged run as the control, and
tagged — and what the tag changed between them. The first baseline, on `c7db471` at library
defaults, is `measurements/irs-p596-zhs-2025/record.md`.

## Three runs on one binary

| | untagged | control (untagged again) | tagged, `--language zh-Hans` |
| --- | ---: | ---: | ---: |
| Receipt `options` | library defaults | library defaults | library defaults with --language zh-Hans |
| Exit, EPUBCheck, gate | 0, 0, passed | 0, 0, passed | 0, 0, passed |
| Seconds | 6.44 | 6.35 | 6.22 |
| Peak RSS | 169.7 MiB | 169.8 MiB | 167.7 MiB (ceiling 256) |
| Pages reflowed / recognized | 33 / 0 | 33 / 0 | 33 / 0 |
| Images | 140 | 140 | 140 |
| Heading elements | 85 | 85 | 85 |
| Entry bytes | 15,155,711 | 15,155,711 | **15,088,322** |
| `dc:language` | en | en | **zh-Hans** |

The warnings are the same eighty-five in every run: `imageRegion` 38, `structureFallback` 24,
`furnitureRemoved` 21, `annotationsNotConverted` 2. Memory pressure was normal (level 1)
throughout.

## What the tag changed

**One page.** `tools/epub_identity.py` finds the untagged run and its control identical, and the
untagged and tagged runs differing in six entries: `package.opf` (+5 bytes, `zh-Hans` for `en`),
`nav.xhtml` (+10), `chapter-1.xhtml` (−459), `chapter-2.xhtml` (+251), `chapter-3.xhtml` (+620)
and `images/image-27.png` (104,444 → 36,628 bytes). The comparator's own page records
(`Evaluation`, `compare_pages` and `compare_images` of `tools/compare_conversion_runs.py`, called
directly because its receipt check refuses a pair whose `options` differ, as it should) attribute
the whole difference to page 4 — fields `images`, `paragraphs`, `paragraphSpans`, `text` — with
one changed image, equal page markers, equal report fields, and 0 unstable pages under the
control. The XHTML roots also carry `xml:lang="zh-Hans"`, which moves no content.

**Why page 4.** Its left column opens with the publication's comments paragraph, whose fourth
line is Latin only: `Ave.NW, IR-6526, Washington, DC 20224）。` The link `IRS.gov/FormComments`
above it seeds a crop, and a crop takes every line it intersects except one that reads as the
book's own prose (`releasesProse`, #255): the sentence shape — four or more runs of two letters
or more — and, in a book that declares English and only there, the English word test. That line
reads as a sentence, and `Ave`, `NW`, `IR` and `DC` do not read as English words, so declared
`en` the crop keeps it; and a Chinese line with one comma is two runs of letters, not four, so
the five Chinese lines beneath it fail the sentence shape and follow it into the picture, down to
`获取税务问题的答案。` The untagged `image-27.png` is that eight-line picture, 654 × 286 pixels.
Declared `zh-Hans`, the sentence shape alone releases the Latin line, the crop ends at its third
line (`1111 Constitution`; 653 × 104 pixels) and the paragraph reflows from `Ave.NW` on. The
same page's right column, whose first paragraph continues from page 3, is set as two paragraphs
at its first line break in the tagged run where the untagged run set one; the page's free lines
changed with the release, and that split is recorded, not attributed to a named rule. The
released lines are what the contract now pins on page 4.

**The recognizer, and the rules the tag switches off.** No page of this book is recognized in
any run (`recognizedPageCount` 0), so the recognition language decides nothing here; it would,
because `zh-Hans` is one of the spellings Vision lists (`zh-Hans-CN`) and
`supportedRecognitionLanguages.contains` is true for it, where it is false for `ar` and for `en`
(#106, reconciled on #231 as unported — see the Arabic record). Every other rule that reads the
declared language asks `EnglishText.isDeclared` and stands down under `zh-Hans`: the
inherited-layer, drawn-text (#176, #192 item 2) and recognition judgments, the damaged-encoding
check, the recognized-line heading test, the prose-over-pictures protection (#239), the Cyrillic
look-alike repair and the line-end lexicon vote. Only `releasesProse` had a line to act on. The
East Asian spacing and heading joins (`CJKText`) read the text's own script and are not gated by
the tag, which is why the 85 headings and every CJK join are the same in both runs.

**Headings.** The book emits 85 heading elements on this tree, tagged or untagged, where #243
counted 99 on `7a4a5b3` after #241 and 101 before it. The cover's `目录` is not among the 85
either way — that loss is #243's, and the document-wide ranking that would restore it is #294 —
and the fourteen fewer since `7a4a5b3` are not attributed here; the contract pins no heading
count, so `目录`'s return fails nothing.

## The contract on the tagged run

Pages 1, 5, 16 and now 4 were rendered with `pdftoppm -f N -l N -r 100 -png` and read against
the tagged output: the page-1 catalog footer and cover image; page 5's rule-3 sentence with the
running foot absent; page 16's example labels, the four earned-income limits in source order and
the `Clergy filing Schedule SE` line; and on page 4 the two lines the release frees, `Ave.NW,
IR-6526, Washington, DC 20224` and `尽管我们无法对收到的每条意见进行单独回复`, both printed
plainly at the head of the left column. The 14 earlier checks pass on the tagged run as on the
untagged (`tools/check_corpus_content.py --case irs-p596-zhs-2025 --evaluation <tagged>`); the two
page-4 checks pass on the tagged run and would fail on the untagged one, which is the point of
them. `dc:language` is not a check the content checker has, and is not pinned.

## What changed in the repository

`corpus/manifest.json` carries `language: "zh-Hans"` on this entry; the evaluator, its tests and
the documentation changes are as the Arabic record lists them. No runtime source changed.
