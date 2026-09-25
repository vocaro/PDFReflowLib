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
