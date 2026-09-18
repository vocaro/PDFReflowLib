# Suspect inherited layers and recognitions (#7): survey, signals, precision

Tier: deterministic Apple PDF/OCR stack, macOS 27.0 (26A428) arm64, release CLI, library defaults
unless stated, built on the coordination tip `35f69c7` plus this change. Date 2026-09-18. The
machine was shared with other agents' conversions (load average 40–105), so no time here is a
budget. Recognitions in the survey come from `survey-ocr`, a separately named executable with its
own Vision compile (#94): they are measurement evidence, and the converter's own readings of the
same pages can differ in detail.

**Result.** Three gaps from #7, #93, #129 and #209 are closed with document-independent signals:

1. A third word test fails an inherited layer that reads as English but **misreads a tenth or more
   of its words in place**. Warren page 636 (`tcld t» ftboot` for "told me about", 0.50 English)
   and 22 other Warren typescripts and document photographs fail it, and so does CDC page 4
   (#168's unflagged 0.60 page). Every one reports `implausibleTextLayer`; by default each is
   recognized again and the reading that misreads fewer words is kept.
2. **Recognition under half English is noise and is discarded.** Warren's handwritten hospital
   notes 549 and 552–554, 556 (whose layers already failed #93) now report
   `implausibleRecognition` and become page images instead of mixed Latin/Arabic/Cyrillic text and
   headings.
3. **A recognized line is a heading only if it reads as English words.** Under `--ocr always` the
   Blue Book's headings, and so navigation entries, fall from 8,848 to 799 (#129).

No image-backed page outside Warren and the CDC comic fails any test, and every flagged page was
reviewed against its render as a damaged layer. The Warren budget margin grows (page images
replace five page references plus their text); all 21 lanes pass.

## Signals

Every image-backed page (text over a graphic covering more than 75% of the page, the
`unverifiedTextLayer` pages) in the 21 English corpus books was surveyed with
`../text-layer-plausibility/survey-pages.swift` (1,369 pages: Warren 910, Blue Book 312, NOAA 54,
CDC 33, Earthdata 21, FAA 18, Fed 8, NBS 7, Agricultural Research 3, Our Flag 2, DGA 1; the other
ten books have none). Every page of the five scanned books (CDC 42, NBS 7, Census 20, Blue Book 312,
Warren 920) was recognized with `survey-ocr.swift`. `score-text.swift` scores both with the
library's own code ([scores-inherited.tsv](scores-inherited.tsv), [scores-recognized.tsv](scores-recognized.tsv)).

Candidate signals examined and rejected:

| Signal | Why not |
| --- | --- |
| English share below a higher threshold | Warren's typescripts (0.50–0.82) overlap its good witness lists (0.65) and notes. |
| Share of damaged words | NBS's Paper Capture text split inside words (`fi e ld stre ngth`) reaches 0.27, above typescripts like 663 (0.23). |
| Symbol rate (`^ » \| ~`) | Highest on handwriting and document photographs, but typescripts 630–664 sit at 0.09–0.14 beside good pages. |
| Letters of another script, per page | Good recognitions carry them too: CDC's Cyrillic look-alike exclamations (12 of 224 letters on page 10), Warren's notes pages (`Seе suра`, Cyrillic е and а), Blue Book cells in Thai and Japanese. Kept as word damage and as a heading bar, not a page test. |
| Language identification | `NLLanguageRecognizer` names handwriting noise English with full confidence (Warren 289, 291, 292, 301). Other languages' lexicons are absent on this Mac (`NLEmbedding.wordEmbedding(for: .french)` is nil), so they cannot confirm words. |

The **misread share** separates: a damaged word of three or more letters (lower case unknown to the
lexicon, or irregular capitals other than a compound name such as `McDonald`) that neither
neighbour joins into an English word. Joining removes letter-spaced and split text (NBS falls to at
most 0.06, the Blue Book's worst non-table page to 0.08); all words, including names, are the
denominator, so name-heavy lists are not penalized (Warren 520: 0.07).

| Book | Pages | Highest misread share (numeric share < 0.2) | Flagged by misread |
| --- | ---: | --- | ---: |
| Warren | 910 | 0.255 (546) | 23 |
| CDC | 33 | 0.340 (5, already failing #93) | 1 (page 4) |
| NBS | 7 | 0.060 (5) | 0 |
| Blue Book | 312 | 0.080 (53); tables with more digits are exempt as before | 0 |
| Earthdata, FAA, NOAA, Fed, Our Flag, DGA, Agricultural Research | 107 | 0.053 | 0 |

## Precision

Pages flagged per class, each reviewed against a 40–80 dpi render and the layer's text:

| Class | Flagged | Genuinely bad | Good wrongly flagged |
| --- | ---: | ---: | ---: |
| Warren carbon typescripts (545, 546, 627–637, 656, 662–664) | 17 | 17 (`vao corniamiot ctatcxi`, `bnr h'^ftdauortars`) | 0 |
| Warren photographed documents and forms (201, 501, 502, 566, 601, 602) | 6 | 6 (`AiUh«irixiug rhe rmiiuiisHiuii`, `CLINICAL RECORD AUTOPSY P.^OTOCOL`) | 0 |
| CDC page 4 | 1 | 1 (`ALriSHT`, `eooeeYM`) | 0 |
| #93 flags, unchanged (CDC 27, Warren 7) | 34 | 34 | 0 |
| Every other image-backed page (1,313) | 0 | – | 0 |

Recognitions discarded (`judgeRecognized`, fewer than half of at least 20 judged words English):

| Scope | Discarded | Reviewed |
| --- | ---: | --- |
| Default policy (pages recognized in the conversion) | Warren 549, 552, 553, 554, 556 | handwritten hospital notes; recognition 0.14–0.46 English (`iar mhele aandeuzen`, `DeالasTaxaع`) |
| Every page of the five scanned books (`--ocr always`) | 13, all Warren: 289, 291, 292, 301, 328, 339, 547, 549, 551–554, 556 | handwritten letters, diary, speech draft, tourist card and hospital notes; none is typed or printed text. 548 (Romanian with full confidence) is kept by the language exemption. |
| CDC, NBS, Census, Blue Book | 0 | the Blue Book's handwritten tables are digit-exempt, as their layers are |

Recall gaps, not flagged: Warren 555 (hospital note; its recognition has 11 judged words, under the
20-word floor, so its noise `Aet Piاتهب أوبأ` still reflows, as paragraphs, never headings);
typescripts just under the misread threshold (649, 655, 657, 659, 661 at 0.087–0.097, and 367, 544);
handwriting whose layer passes (547, 548, 550, 551, 289–292, 301, 339) keeps its inherited layer
under the default policy.

## Keeping the better reading

Recognition of the carbon typescripts is no better than their layers, so replacing every misread
layer would trade one damaged transcription for another. Survey readings (misread share, layer →
recognition):

| Outcome | Pages |
| --- | --- |
| Recognition better, replaces the layer | 201 (0.158 → 0.089), 501, 502 (0.172 → 0.081), 545, 566, 601 (0.140 → 0.038), 602 (0.132 → 0.021), 629, 630, 632, 636 (0.238 → 0.190); CDC 4 (0.136 → 0) |
| Recognition worse, layer kept | 546, 627, 628, 631, 633, 634, 635, 637, 656 (0.155 → 0.343), 662, 663, 664 (0.234 → 0.350) |

The converter's Warren conversion made exactly these choices (its `ocrUsed` pages include the 11
replaced, and 664's message ends "OCR failed or read it no better, so the existing text is
retained"). Replaced page 636 now reads "and he told me about the things at ... He was placed back ...
At 6:00 PM I instructed the officers to bring Osvald back into the office", still with recognition
errors (`Osvald`, `pleture`), against the layer's `h» tcld t» ftboot Um thii^gs ftt`.

## Headings

A recognized line in an English book becomes a heading only when `readsAsWords` holds: no letter of
another script, an English word of two or more letters (the lexicon's lower-case or capitalized
entry, so `September` counts), English words at least half of its words, and digits in at most half
of its tokens.

| Blue Book `--ocr always` | Headings = navigation entries |
| --- | ---: |
| Before (`35f69c7`) | 8,848 |
| After | 799 (474 of them on the table pages 116–260; none without a letter) |

Refused examples: `139`, `1952 1950`, `a0 0.0`, `Pags`, `Certaia Doubtlul Total`, `ОVER. 3f
MINUTES`, `Cotai (CAil Toa) CeLan`, `ッッ`. Still headings: table titles (`Table A59. Evaluation of All
Sightings for 1952 by Sighting Reliability Groups`, `INDEX OF TABLES`) and table column heads that
are words (`SEPTEMBER`, `NORTH AMERICA`, `Certain Doubtful Total`), which a line-level test cannot
tell from titles. Warren's recognized page 553 (`Tag De Praciy Glii tant ami She`) no longer
reflows at all. On recognized pages, prose lines Vision boxes taller than the body still become
headings (Warren 501, `That (a) for the purposes corission in-`): a size-estimation defect, not noise.

## Lanes

All 21 cases, one per call, `tools/run_corpus_regressions.py` with EPUBCheck: all pass.

| Case | Result | Notes |
| --- | --- | --- |
| gpo-warren-1964 | PASS | entry bytes 536,114,740 (756,172 B under 512 MiB; #202 recorded 319,972); peak RSS 1,103 MiB, 1,022 s loaded; recognized pages 17 → 23; `implausibleTextLayer` 30 pages, `implausibleRecognition` 5 |
| cdc-zombie-pandemic-2011 | PASS | page 4 replaced; 37 recognized pages |
| cia-blue-book-14-1955 | PASS | no page flagged, no recognition |
| census-rrs2002-01, nbs-jres-geltman-1977 | PASS | no page flagged; Census's recognitions all pass |
| the 16 others | PASS | no image-backed page flagged |

Contracts: Warren 549, 553 and 556 pin `implausibleRecognition`, one page image and no `ocrUsed`;
636 pins `implausibleTextLayer`, two recognized phrases and the absence of `ftboot`; 664 pins
`implausibleTextLayer` with no `ocrUsed`; CDC 4 pins the warning, two recognized phrases and the
absence of `ALriSHT`. Replacement on 636 and retention on 664 depend on this Mac's Vision reading
(#94); both margins are wide (0.238 vs 0.190, 0.234 vs 0.350).

## Tools

- `survey-ocr.swift` recognizes every page with `OCRReader` (build with
  `../text-layer-plausibility/build-tool.sh survey-ocr.swift <scratch>/survey-ocr`);
  `survey-ocr-all.sh <tool> <dir>` runs the five scanned books (Warren takes about 25 minutes loaded).
- `../text-layer-plausibility/survey-all.sh <dir>` surveys inherited layers, now in all 21 books.
- `score-text.swift` scores both kinds of record: `score-text <dir>/*.jsonl > scores.tsv`.
