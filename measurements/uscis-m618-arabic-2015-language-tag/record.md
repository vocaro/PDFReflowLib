# USCIS Arabic guide: baseline on the tagged lane

Tier: deterministic Apple PDF/OCR stack, isolated release CLI on macOS 27.0 (26A428) arm64,
Xcode 27.0 (27A266a), EPUBCheck 5.3.0. Build: `8faeaab`, `swift build -c release`, executable
SHA-256 `497df75a3954f6c475ef9f6afe480ff695a30fad4b14254ddc6d4ec26d951cad`. Source: *Welcome to
the United States: A Guide for New Immigrants* (M-618-A, Arabic, rev. 09/15), 116 pages,
4,156,497 bytes, SHA-256 `354effbbe38450664959b8832d136cfd158d3c17d1ba777b8b1e4a5b6aa36d54`.

The owner ruled on #293 (2026-09-23) that the corpus lane passes each case's language. This
book's manifest entry now declares `language: "ar"`, and `tools/evaluate_real_document.py` adds
`--language ar` to every conversion of it. This record is the book's baseline on that lane: three
conversions on one binary — untagged, a second untagged run as the control, and tagged — and
what the tag changed between them. The first baseline, on `c7db471` at library defaults, is
`measurements/uscis-m618-arabic-2015/record.md`; the #41 restatement is
`measurements/right-to-left-runs-and-rows/record.md`.

## Three runs on one binary

| | untagged | control (untagged again) | tagged, `--language ar` |
| --- | ---: | ---: | ---: |
| Receipt `options` | library defaults | library defaults | library defaults with --language ar |
| Exit, EPUBCheck, gate | 0, 0, passed | 0, 0, passed | 0, 0, passed |
| Seconds | 7.92 | 8.00 | 6.91 |
| Peak RSS | 155.4 MiB | 160.5 MiB | 134.2 MiB (ceiling 256) |
| Pages reflowed / recognized | 108 / 0 | 108 / 0 | 108 / 0 |
| Images | 151 | 151 | 151 |
| Heading elements | 101 | 101 | 101 |
| Entry bytes | 40,181,360 | 40,181,360 | 40,181,360 |
| `dc:language` | en | en | **ar** |

The warnings are the same three hundred and seven in every run: `structureFallback` 100,
`imageRegion` 100, `furnitureRemoved` 99, `emptyPage` 3, `ocrFailed` 3, `pageImageFallback` 3,
`annotationsNotConverted` 1. Memory pressure was normal (level 1) throughout.

## What the tag changed

**Nothing in the pages.** `tools/epub_identity.py` finds the untagged run and its control
identical, and the untagged and tagged runs differing in seven entries — `package.opf`,
`nav.xhtml` and `chapter-1` to `chapter-5` — every one at the same byte length: the package's
`<dc:language>` reads `ar` for `en`, and each XHTML root carries `xml:lang="ar" lang="ar"` for
`en`. The comparator's own page records (`Evaluation`, `compare_pages` and `compare_images` of
`tools/compare_conversion_runs.py`, called directly because its receipt check refuses a pair whose
`options` differ, as it should — the tag is a different option set, not drift) report 0 changed
pages, 0 changed images, equal page markers and equal report fields, with the control marking 0
unstable pages.

**The recognizer never sees the tag.** `recognizedPageCount` is 0 in every run: the three
textless section dividers (pages 2, 114 and 115) go to recognition and read as nothing
(`ocrFailed`), tagged or not. And `--language ar` does not reach Vision on this host regardless.
`OCRReader.read` sets `recognitionLanguages = [language]` only when
`request.supportedRecognitionLanguages.contains(Locale.Language(identifier: options.language))`
holds; a probe of that exact call (`RecognizeDocumentsRequest().supportedRecognitionLanguages`
compiled with `xcrun swiftc` on this host) lists `ar-SA` (`ar-Arab-SA`) and `ars-SA`, and
`contains` is false for `ar` (which maximizes to `ar-Arab-EG`), false for `en` (Vision lists
`en-US`), and true for `zh-Hans` and `zh-Hant`, which Vision lists in exactly that spelling. So no
book declared `ar` — and no book declared `en` — has ever set the recognizer's language; the
Chinese publication's `zh-Hans` does. This is #106 ("bare language codes fall back to US
English"), closed by `9116393ec` on the abandoned coordination branch and reconciled on #231 as a
fix `main` does not hold ([decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md));
it is reported here, not fixed.

**The rules the tag switches off, and why none of them shows.** Every rule that reads the
declared language asks `EnglishText.isDeclared`, and with `ar` each one stands down: the
inherited-layer judgment (`TextLayerPlausibility.judge`, #93), the drawn-text rule
(`judgeImageOnly`, #176 — #192 item 2), the recognition judge (`judgeRecognized`,
`readsBetter`, #7), the damaged-encoding check (`TextEncodingCheck.isImplausible`, #38), the
recognized-line heading test (`judgesTitleWords`), the prose-over-pictures protection
(`PageDiagnosis.proseOverPictures`, #239), the English word test that keeps a book's prose out
of its crops (`releasesProse`, #255), the Cyrillic look-alike repair
(`OCRReader.repairedScript`, #168) and the line-end lexicon vote
(`HyphenContext.usesEnglishLexicon`). This book gives none of them a page to act on: no page is
recognized, none carries a text layer over a page-sized image, none has a damaged encoding, and
no line a crop would take is Latin-only prose. The right-to-left rules (#41) never consulted the
language, and the East Asian spacing rules read the text's own script, so the guide converts the
same under either declaration. The drawn-text rule #192 item 2 worried about is therefore off for
this book now, and that costs it nothing today, because it never fired on it.

## The contract on the tagged run

Pages 5 and 21 were rendered with `pdftoppm -f N -l N -r 100 -png` and read again against the
tagged output: the contents heading `جدول المحتويات`, its eight pinned entries in printed order
with two of them their own preformatted blocks, and on page 21 the card specimen, `[Permanent
Resident Card]`, `www.uscis.gov/uscis-elis`, `[USCIS Forms Line]`, `بطاقة الإقامة الدائمة`, the
five paragraph phrases carrying `I-551`, `USCIS ELIS`, `I-90`, `1-800-870-3676` and `(USCIS)`
in the page's order, and the five reversed forms the page must not produce. All 26 checks pass on
the tagged run, as on the untagged (`tools/check_corpus_content.py --case uscis-m618-arabic-2015
--evaluation <tagged>`), and the case's `basis` in `corpus/regressions.json` now says so.
`dc:language` itself is not a check the content checker has, and is not pinned.

## What changed in the repository

`corpus/manifest.json` carries `language: "ar"` on this entry; `tools/evaluate_real_document.py`
passes `--language` from the field on every conversion of a case, including a memory-attempt
retry, and its receipt's `options` names the flag; `tools/test_memory_gate.py` covers a case with
the field and one without; `doc/corpus.md`, `doc/regression-testing.md`,
`doc/conversion-options.md` and `doc/behavior.md` describe the tagged lane. No runtime source
changed.
