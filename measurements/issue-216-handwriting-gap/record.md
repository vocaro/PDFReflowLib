# Inherited handwriting still passing the text-layer check (#216)

Source: checksum-pinned Warren survey at commit `4afe5c39`,
`measurements/suspect-text-layers/scores-inherited.tsv` and its `record.md`. The current
`TextLayerPlausibility` word and ink rules leave the inherited layers on these pages under the
automatic OCR policy. The other explicit #216 examples are covered by `720ef267` (Warren 555),
`10be4931` and `642aaf51` (carbon typescripts), and `fe76dc7f` (OCR headings).

| Warren page | English / judged words | Misread / all words | Uncovered rows | Uncovered ink | Current finding / disposition |
| ---: | ---: | ---: | ---: | ---: | --- |
| 289 | 11 / 15 | 3 / 24 | 5 | 54.3% | Fewer than 20 judged words; fewer than 7 uncovered rows |
| 291 | 12 / 18 | 2 / 30 | 7 | 73.4% | Fewer than 20 judged words; uncovered ink below 75% |
| 292 | 22 / 37 | 6 / 65 | 59 | 53.3% | Now flagged above the 8.5% misread cut; comparison keeps the layer when recognition reads worse |
| 301 | 23 / 24 | 0 / 30 | 24 | 40.2% | Printed heading reads well; handwritten body does not leave enough uncovered ink |
| 339 | 17 / 22 | 0 / 37 | 35 | 56.4% | No misread words; uncovered ink below 75% |
| 547 | 16 / 27 | 3 / 44 | 0 | 0% | OCR boxes cover the handwriting |
| 548 | 7 / 17 | 2 / 48 | 0 | 0% | Fewer than 20 judged words; OCR boxes cover the handwriting |
| 550 | 10 / 18 | 3 / 31 | 0 | 0% | Fewer than 20 judged words; OCR boxes cover the handwriting |
| 551 | 12 / 21 | 2 / 52 | 17 | 60.5% | Misread share below cut; uncovered ink below 75% |

The survey also includes unaffected sparse pages. Blue Book 148 has 52.4% English judged words
and 75.8% uncovered ink, but is a numeric table; Warren 148 is a photographed group of printed
forms and handwritten marks with 75.6% English, 6.2% misread and 35.3% uncovered ink. NOAA 139
is a chapter cover with only eight English words and 63.3% uncovered ink. Warren 225 is a floor
plan with 26 English words, 39 uncovered rows and 40.3% uncovered ink. A lower English or ink
threshold across these pages would also catch source content that the current rules correctly
keep. Page 301 and 339 have no misread words at all, while pages 547, 548 and 550 have no
uncovered rows, so neither existing signal alone can solve the remaining handwriting cases. The
surveyed fresh OCR of page 292 has only 94 English words of 233 judged and is discarded as noise.
`RecognitionPolicy` therefore keeps the flagged inherited layer under its compare mode, as it
must for damaged printed typescripts whose new OCR reads worse.

No additional heuristic was adopted from these measurements. #216 still needs a
document-independent way to distinguish a legible printed heading or table over a scan from
handwriting whose OCR layer only looks plausible in aggregate, with controls for both classes.

## Discriminators measured (2026-09-25, `main` at `684cf06b`)

**The source.** Every named page was rendered at 180 DPI and read. Pages 289 and 291 are
Oswald's cursive notes to the Moscow embassy under a printed title and caption; 292 is his
block-capital "Historic Diary"; 301 is two handwritten pages of the undelivered speech under a
printed title; 339 is a photographed typed letter over two handwritten drafts; 547, 548, 550 and
551 are cursive Parkland admission notes on ruled forms. Page 290 is not handwriting: it is an
ordinary printed page of the report's prose (422 English words), whose inherited layer is sound
and must stay; the issue lists it by range. For every handwritten page a reader is served by the
page image, as the same notes' pages 549 and 552–556 already are.

**Scope.** Every image-backed page of the Warren report (910) and Blue Book (312) went through
`PageReader` and `PageDiagnosis`; Census `rrs2002-01` has no image-backed page, so no inherited
layer of it is judged. All the pages above hold fewer than 32 English words, the ink test's own
gate; 120 image-backed pages do (82 Warren, 38 Blue Book), and those are the population any rule
here acts on. The typescripts 649–661 (243–461 English words), the report's printed pages and
Blue Book's typewritten tables are far above it, so a rule gated there cannot touch them.

**Three signals that do not separate the classes.** Each is given as the targets' range against
the sparse controls it overlaps.

| Signal | Handwritten targets | Overlapping controls |
| --- | --- | --- |
| Share of letter-bearing tokens holding a symbol other than prose punctuation (`^`, `<`, `«`, `*`, `\|`) | 547 0.20, 548 0.40, 550 0.32, 551 0.43; but 289 0.12, 339 0.11, 301 0.00 | Warren 615 (hair diagram) 0.21, 328 (photographed forms) 0.17, 592 (fingerprint diagram) 0.16, Blue Book 142 and 148 0.10 |
| Word-shaped connected components (height 2.5–40 pt, aspect 2.5–20, ruled lines removed) as a share of glyph-sized ink | 339 0.50, 547 0.63, 548 0.57; but 289 0.15, 550 0.22 | Warren photograph pages 110 0.73, 141 0.67, 94 0.66, 233 0.58 |
| Layer glyph boxes against ink (`OCRTextCoverage` uncovered share) | already in the table above: 0% on 547, 548, 550 | Warren 225 40.3%, Blue Book 148 75.8% |

The symbol share is the only text signal with any separation, and it misses 289, 301 and 339;
the stroke share is swamped by photographs; the coverage signal fails on cursive because cursive
words are not glyph-shaped. None was adopted.

**The signal that does separate them: recognition of the page.** Each of the 120 sparse pages,
the controls below and pages 290, 649, 655 and 50 was recognized once with `OCRReader.read`
(default options, this host's Vision) and judged with the shipped `judgeRecognized` (under half
English of at least 20 judged words, not another language, not a numeric table).

| Page | Layer English | Layer finding | Symbol share | Stroke share | Recognition English / judged | Recognition |
| --- | ---: | --- | ---: | ---: | ---: | --- |
| Warren 289 | 11 | none | 0.12 | 0.153 | 20 / 62 | noise |
| Warren 291 | 12 | none | 0.16 | 0.297 | 16 / 44 | noise |
| Warren 292 | 22 | misread | 0.25 | 0.132 | 132 / 290 | noise |
| Warren 301 | 23 | none | 0.00 | 0.380 | 70 / 217 | noise |
| Warren 339 | 17 | none | 0.11 | 0.503 | 44 / 169 | noise |
| Warren 547 | 16 | none | 0.20 | 0.629 | 25 / 128 | noise |
| Warren 548 | 9 | none | 0.40 | 0.573 | 15 / 55 | not judged: reads as another language |
| Warren 550 | 10 | none | 0.32 | 0.218 | 5 / 16 | not judged: under 20 words |
| Warren 551 | 12 | none | 0.43 | 0.339 | 31 / 126 | noise |
| Warren 328 (photographed forms) | 18 | none | 0.17 | 0.433 | 22 / 56 | noise |
| Warren 225 (floor plan) | 26 | none | 0.00 | 0.213 | 102 / 102 | English |
| Warren 615 (hair diagram) | 9 | none | 0.21 | 0.344 | 13 / 13 | English |
| Warren 331 (photographed visa papers) | 30 | none | 0.10 | 0.148 | 32 / 45 | English |
| Warren 592 (fingerprint diagram) | 12 | none | 0.16 | 0.147 | 20 / 20 | English |
| Blue Book 60 (pie charts) | 26 | none | 0.02 | 0.127 | 33 / 35 | English |
| Blue Book 142 | 15 | misread | 0.10 | 0.199 | 150 / 181 | English |
| Blue Book 189 | 17 | misread | 0.03 | 0.155 | 11 / 55 | numeric table, not judged |
| Blue Book 256 | 20 | misread | 0.03 | 0.075 | 29 / 87 | numeric table, not judged |

Of the 129 recognitions, 14 read as noise: Warren 289, 291, 292, 301, 339, 547, 551, the
already-handled 549 and 552–556, and Warren 328. The handwritten targets that read as noise run
from 20% to 36% English; every other recognition of at least 20 judged words that is not exempted
as a numeric table reads at least 71% English (Warren 331), except Warren 328 at 39%. Page 328 is a page of photographed Mexican tourist-card papers bearing
handwriting and stamps under a printed title; as a page image it loses only its title and two
captions from the reflow, and it is the one control this rule moves. Two targets are not caught:
page 548's recognition (`A scanul 1I unfunșia vor lejuna`) spells Romanian diacritics and is
taken for another language, and page 550's has only 16 judged words.

**Adopted.** Under `.automatic`, an image-backed English layer of fewer than 32 English words that
passes every test is recognized (`RecognitionPlan.Mode.verify`) and stands unless that
recognition fails `judgeRecognized`; then the page is an image, reporting
`implausibleRecognition` and `implausibleTextLayer` (`unreadWriting`). A sparse layer the misread
test sends to comparison (page 292) becomes an image on the same evidence instead of being kept.
No new threshold: the gate is the ink test's word ceiling and the judgment is the one every
recognition already receives. Vision's reading of a page varies between runs (#173), so the
tests replay captured readings (`handwrittenPagesUnderSparseLayersBecomePageImages`,
`sparseLayersAreVerifiedAgainstRecognition`). A 16-page extract of pages 289–292, 301, 328, 339,
547–551, 225, 615, 649 and 50 converted three times with the release CLI gave the same dispositions each
times: page images for 289, 291, 292, 301, 328, 339, 547, 549 and 551; the layer kept, with
`unverifiedTextLayer`, on 290, 548, 550, 225, 615 and 50; and the typescript 649 still compared.

**Cost and reach.** Verification adds one recognition for each sparse page no other test already
recognizes: 74 of Warren's pages and 32 of Blue Book's. Over the rest of the English corpus the
plan was run page by page and every verified page recognized once: NOAA's climate assessment
verifies 44 of 1,834 pages, the CDC comic 3 (and compares a fourth, page 4, as before), Our Flag,
the Dietary Guidelines, the USDA magazine and the FAA handbook one each, and the 9/11 report,
Wallace, the Fed, SCOTUS, NBS, the arXiv paper, USGS, Census, the Earthdata slides, TechPort and
the Warren suspect-text excerpt none. None of those recognitions read as noise, so no page outside
the Warren report changes disposition.

**Left open.** Pages 548 and 550 keep their layers. A recognition that reads as another language
with high confidence, or that is too short to judge, is not evidence of handwriting under the
shipped judgment, and loosening either would reach the French-page and short-caption controls
that judgment was built on.

## Pages 548 and 550 (2026-09-25, `main` at `2bff36c6`)

**Why each escaped.** Both pages are cursive Parkland admission notes under the printed title
`ADMISSION NOTE` and the caption `Commission Exhibit No. 392—Continued`, as their rendered source
pages show. Each was recognized four times on this host (twice in one probe process, once in the
survey below and once by `tools/probes/capture-ocr-layout-fixture.swift`), and all four readings
were the same text. The figures set lone letters aside, as the word test does (#275).

| Page | Layer English / judged (`PageReader` lines) | Reading English / judged | Misread / words | Accented letters / letters | Language named | Named with accents folded |
| ---: | ---: | ---: | ---: | ---: | --- | --- |
| 548 | 7 / 17 | 12 / 52 | 35 / 66 | 6 / 328 | Romanian 0.998 | Romanian 0.523 |
| 550 | 6 / 14 | 5 / 16 | 8 / 20 | 0 / 116 | English 0.616 | English 0.616 |

Page 548's reading (`A scanul 1I unfunșia vor lejuna nD îum`, `nalună, crcliăe manets`) holds no
letter of another script, but six accented Latin letters (`ș`, `î`, three `ă`, `á`) are enough for
the system language recognizer to name Romanian at 0.998, above the 0.95 at which
`readsAsAnotherLanguage` exempts a reading from the English-share test. Page 550's reading
(`artauit benepit Electrcarligagbur`, `pneed cad penntent d detiti`) holds 16 judged words, under
the word test's 20, and no letter of another script, so the short mixed-script test of Warren 555
(five such letters at least) does not apply either. Its layer, 6 of 14, is itself too short for
the word test.

**The survey.** Every page of the 19 English-declared corpus documents was put through
`PageReader`, `PageDiagnosis.assess` (with the ink test) and `RecognitionPolicy.plan` under
`.automatic` at `2bff36c6`, and each page the plan recognizes was read once with `OCRReader.read`:
333 recognitions in 13 documents (157 verifications, 42 comparisons, 134 replacements; SCOTUS,
NBS, arXiv, USGS, TechPort and Wallace recognize none). 191 of them are pages with a sparse layer.
Each is listed in [recognitions.tsv](recognitions.tsv) with its sparse layer's and its reading's
English and judged words, the language the recognizer names before and after folding accents, and
its judgment under the rules adopted below.

- *Languages.* The recognizer names another language at 0.95 or more for four readings: Warren
  548; Blue Book 29, a pie chart whose reading holds `1949-51łą` and a stray `ダ` (Polish 1.000, and
  0.998 folded, since `ł` is a letter of its own, not an accented one), which reads 24 of 26
  English and is not judged noise either way; Warren 648 (Vietnamese 0.991, no judged words); and
  Our Flag 1 (Turkish 0.972 on a single token, Spanish 0.381 folded, no judged words). 107 of the
  333 readings hold Latin letters outside ASCII, among them every handwritten Warren page's (289:
  6, 301: 27, 547: 11, 551: 10). Folding changes whether another language is named at 0.95 for
  only 548 and Our Flag 1, and Our Flag 1 has no word to judge.
- *Genuine languages.* 28 samples were written for this measurement (18 of them are in the test):
  prose and short titles in French, Spanish, Portuguese, Italian, German, Romanian, Polish, Czech,
  Turkish, Hungarian, Vietnamese, Dutch, Swedish and Catalan, a Spanish tourist-card heading, a
  French passage typed without accents, and a Latin sentence. All but the Latin are named at 0.99
  or more both as written and folded (lowest folded: a Vietnamese title 0.991, a French title
  0.992). Text of the non-English corpus documents (Arabic
  M-618 pages 3, 10 and 40, Chinese P596 pages 2, 5, 10 and 20, the Hebrew Shakespeare pages 81,
  150 and 250, the Japanese Hoshino pages 1–3 and the Hindi reader pages 3, 5, 9 and 12, taken with
  `mutool draw -F txt`) is named the same before and after folding. Latin, which the recognizer
  does not name (French 0.896), is not exempted either way.
- *Short readings.* 91 verifications read 5 to 19 judged words. Every one reads at least 70%
  English (lowest: Warren 239's labels, 7 of 10; Warren 95, 5 of 6) except page 550 (5 of 16).
  Three verified layers hold 5 to 19 judged words and read under half English: Blue Book 312, the
  back cover, whose tally strokes read as lone `I`s (1 of 5, beside a reading of `FOR OFFICIAL USE
  ONLY (AFR 190-16)`, 4 of 4), and pages 548 and 550.

**Adopted.**

1. `EnglishText.readsAsAnotherLanguage` requires the recognizer to name the other language at 0.95
   or more twice: on the reading, and on the reading with its diacritics folded to base letters
   (`String.folding(options: .diacriticInsensitive)`). Page 548's reading is then judged, and its
   12 English of 52 judged words fail the English share.
2. Under verification only, a recognition that the word test cannot judge alone is judged beside
   the sparse layer's own counts (`TextLayerPlausibility.judgeRecognized(lines:besideLayer:language:)`):
   when the reading and the layer each hold 5 to 19 judged words, neither is numeric, each reads
   under half English, and together they hold at least 20 judged words, the reading is noise
   (`fewEnglishWordsInEitherReading`). No constant is new: 5 is the short mixed-script test's
   floor, 20 and one half the word test's, one fifth its numeric exemption. Page 550's two
   readings hold 30 judged words, 11 of them English.

Both rules were replayed over all 333 recorded readings with the library's own judge against a
copy of the previous judgment: the finding changes for Warren 548 and 550 and for no other page.
The two readings are captured (`warren-548-*`, `warren-550-*`) and replayed in
`handwrittenPagesUnderSparseLayersBecomePageImages`; the language fold has its own test
(`aLanguageIsNamedByItsWordsNotByAFewAccentedLetters`, the samples above) and so does the
two-reading test (`aShortReadingIsJudgedBesideTheLayerItVerifies`,
`onlyAVerificationJudgesAShortReadingBesideItsLayer`).

Single-page extracts (`mutool merge`) converted with the release CLI: pages 548 and 550 become page
images with `implausibleRecognition`, `implausibleTextLayer` and `pageImageFallback` on two runs
each; 289, 291, 292, 301, 328, 339, 547, 549 and 551 still do; 290, 225 and 615 keep their layers
with `unverifiedTextLayer`.

Corpus lane with the release CLI on this change (`tools/run_corpus_regressions.py`, one case at a
time): `gpo-warren-1964` passes with no content error in 100 checks, now including pages 548 and
550 (`implausibleRecognition`, no `unverifiedTextLayer`, a page image). It recognizes 8 pages and
writes 932 images and 390,047,056 entry bytes, 146,823,856 bytes (140.0 MiB) inside the 512 MiB
budget, 866 bytes fewer than at `2bff36c6`; the two new page images take the place of the
reference images the kept layers carried. In that run pages 289, 291, 292, 301, 328, 339 and
547–556 are page images and 290, 225 and 615 keep their layers. `gpo-warren-1964-suspect-text-excerpt`,
`uscis-m618-arabic-2015`, `irs-p596-zhs-2025`, `ucl-hebrew-shakespeare-2017`,
`tufs-hoshino-tategaki-2017` and `openlogic-hindi-reader-2026` pass with no content error; the
five non-English books declare their language, so neither rule reaches them.
