# Index-named glyphs decoded from the document's own words (#143)

Corpus `census-rrs2002-01` (`corpus/cache/rrs2002-01.pdf`, SHA-256
`0f97380ae4308581bd70013b7317faafd7c217654236bd31d1448f26eae56905`). Tier: deterministic Apple PDF
stack, macOS 27.0 arm64, release CLIs, library defaults unless stated. Work started on `e8bc0c3`
(#133); the facts, survey and review below were measured there. The tree was then merged with
`ec22aff` (#118 column joins, #132 blank pages, #135 drop caps, #131 hyphen joins), and the table
rule, lanes, counts and gates below are against that tip. Date 2026-09-17.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `ec22aff` | `5313437dd466f509e2c6e609a7c62ec8c8762fd146da0a82d2fc227ea830b4b4` |
| candidate | this tree on `ec22aff` | `a156267655f9922d38dc389a7d68337195b7f397d7ecbb6974d1b5c2c675c9e1` |
| first candidate (superseded) | this tree on `e8bc0c3`, before the table rule | `1a2f687bae0052539d800259bca0b3d295a51c17e188d6484442eb52e5efcfda` |
| probe | `tools/probe-raster-environment.swift` | `c53464fd9f526ea3284bcad1ce629c3b4f5c7eeaf241067b6baeff6928c8d0c8` |

Both converters were launched as `pdf-reflow` from separate directories, so every lane shares one
Vision model cache name and compiled-program fingerprint (`3dc11f83…`, #94). No PDF or EPUB is
committed; `lane-summaries/` keeps each run summary and comparison.

## Facts at `e8bc0c3`

- **Is shifted text in the EPUB?** Not under the default policy. Pages 2–20 report
  `damagedTextEncoding` (#38) and are recognized (19 OCR pages, 53 images); a scan of the EPUB for
  words that become common English under a three-letter shift finds none. Under `--ocr never`
  every body page ships the shifted text beside its source-page image: 924 shifted function words
  (`wkh`, `dqg`, `Wklv sdshu`) on pages 2–20, from 60 on page 2 to 1 on pages 12 and 15.
- **Is the page OCR'd instead?** Yes, by #38's rule, with OCR's own errors (page 3's `Ilag` for
  `flag`, `by5`; page 17's `Jourxal of Oficual Stalistics`, `Americon`, `Rescarch`), page 12's
  table titles and one page 17 reference read as headings, and page 3's paragraphs read as headings.
- **Why is PDFKit's text shifted?** Every body font is Type 1 with an embedded CFF program
  (`FontFile3`/`Type1C`), no `ToUnicode` and an `Encoding` dictionary without `BaseEncoding` whose
  `Differences` renumber codes from 1 and name them `G<n>` (`dcr10084`: `[1 /G90 /G108 /G111 …]`, 80
  codes). The embedded CFF charset names its glyphs the same way (`G19 … G125`), its built-in encoding
  places `G<n>` at code `n`, and the descriptor's `CharSet` lists the same names: nothing in the file
  states a character. `n` is a position in the font program Distiller read. For the EC text fonts it
  is the Cork (T1) code plus three (`G87` draws `T`, `G31` the `fi` ligature at T1 28, `G19`/`G20` the
  double quotes at 16/17, `G24` the en dash at 21). For `cmmi10084` it is not: the letters sit at
  their own codes (page 20's `Z = X + dY.` is `G90 G88 G100 G89`) and other glyphs above 127 (`G140`,
  `G163`). The five Type3 fonts (`T2`–`T6`) are bitmap math fonts named `c<n>`.
  PDFKit reports a `G`, `g`, `C` or `c` name as the character U+n for n in 33–126 and 161–255, and
  nothing for any other n (measured with a synthetic Type1 font over n = 0–299 and other prefixes;
  `glyph12`, `cid7`, `uni0041` and two-letter prefixes give nothing; `a<n>` reads like `G<n>` and
  `x<n>` does not, and neither is relied on). So `dcr`'s
  letters come out three letters on, and its ligatures (`G30`, `G31`, U+001E/U+001F) vanish:
  `files` reads `ohv`. Poppler reports U+FFFD for every glyph.

## Survey of the English corpus

`survey.swift` (build and run as its header says; outputs in `survey/`) reports for each book the
index-glyph fonts with the English statistics of their best offsets, PDFKit lines of four or more
words that are under 25% dictionary words as extracted but at least 75% under one Caesar shift
(`/usr/share/dict/words`), and TJ boundaries set with character spacing of at least 0.1 em.

| Book | Index-glyph fonts | Shifted lines | TJ boundaries with Tc ≥ 0.1 em (compensated) |
| --- | --- | --- | --- |
| census-rrs2002-01 | 14 on 19 pages, 3 decoded | 240 of 450 (pages 2–20) | 266 (264) on 15 pages |
| gpo-911-2004 | 0 | 1 of 23,036 (page 543: a date list) | 252 (232) on 23 pages |
| noaa-nca5-2023 | 0 | 7 of 58,428 (DOI URLs) | 2 (0) |
| scotus-loper-bright-2024 | 0 | 0 of 3,768 | 37 (36) on pages 40, 64 |
| cdc-zombie-pandemic-2011 | 0 | 0 of 71 | 45 (5) on page 20 |
| faa-phak-8083-25c | 0 | 0 of 26,327 | 7 (3) on pages 381, 416 |
| fed-explained-2021 | 0 | 0 of 3,647 | 7 (0) |
| wallace, warren, blue book, our flag, dga, nbs, arxiv, usgs | 0 | 0 | 0 |

No other English book has a font with the symptom: no index-glyph font, and the eight shift hits
are dates and DOI suffixes, not text. The Arabic and Chinese cases were not surveyed.

Census's fonts, by offset (words of two or more letters; long = four or more):

| Font | Glyphs | Best offset | Words / long / capitalized | Function words | Rare pairs | Lowercase | Next offset |
| --- | --- | --- | --- | --- | --- | --- | --- |
| dcr10084 | 31,679 | +3 | 5,158 / 3,232 / 530 | 0.456 | 0.023 | 0.972 | +35: 0 capitalized, lowercase 0.000 |
| dcti10084 | 854 | +3 | 125 / 89 / 82 | 0.264 | 0.040 | 0.881 | +35: lowercase 0.000 |
| dcbx100120 | 520 | +3 | 66 / 59 / 55 | 0.242 | 0.027 | 0.874 | +35: function words 0.062 |
| cmmi10084 | 497 | none | +7: 41 / 0 / 1 | 0.805 | 0.146 | 0.432 | |
| cmr10084 | 390 | none | −45: 10 / 0 / 2 | 0.100 | 0.000 | 0.638 | |
| T3 (bitmap) | 196 | none | −5: 41 / 0 / 0 | 0.415 | 0.196 | 0.904 | |
| dctt10075 | 63 | none | 8 words | | | | |
| cmsy, cmex, cmmib, T2, T4–T6 | ≤ 122 | none | no letters | | | | |

## Rule

**Decoding (`GlyphIndexDecoder`).** Before any page is read, every page whose resources hold an
index-style font (`TextEncodingCheck.hasUnmappedFont`) is scanned with `FontWeightReader`. A simple
font without ToUnicode whose `Differences` names at least half its codes `G<n>`, `g<n>`, `C<n>` or
`c<n>` is keyed by subtype, `BaseFont` and its whole `Differences` array, so a font shared across
pages or reopened documents is one font. Its shows are split into words where a word-sized gap
(0.15 em, from TJ adjustments and character spacing) or a show starts. Each offset k that reads at
least half the glyph occurrences as ASCII letters (index n as code n − k) is judged with #38's
embedded English tables. A font is decoded only when exactly one offset has at least 20 words, 10 of
them four letters or longer, 10% function words, at most 10% rare letter pairs, 50% lowercase
letters, one capitalized word and at most 2% words with a capital after a lowercase letter. Its codes
then read through the Cork table for an EC or DC name (`dc`/`ec` + shape + size: ligatures, quotes,
dashes, accented letters; accents, the compound-word mark and the per-mille zero stay undecoded), or
through letters, digits and `! # $ % & ( ) * + , - . / : ; = ? @ [ ]` for any other name; standard
names in the array (`space`, `quoteright`) read as their characters. Only English is judged.

The letter-shift is not assumed: the offset is whatever the document's words establish, per font,
and a font whose glyph order has no constant offset (a synthetic permutation) or too few words gives
no evidence and is left to #38's path. The rules against wrong offsets were each measured:

- **Case swap.** At k + 32 a mixed-case font's lowercase glyphs read as capitals with the same
  function words and pairs (`dcr` +35: 0.443 and 0.023). It has no lowercase letters.
- **Capitals alone.** A font of capitals reads as English lowercase at k − 32, where its digits and
  punctuation become capitals inside words (`noise.` reads `noiseN` in the synthetic control). A
  heading font of capitals with a few capitalized words fails on lowercase (synthetic).
- **Mathematics.** Two-letter variable runs land on function words (`cmmi` +7: 80% function words,
  no word of four letters).

**Line repair (`FontWeightReader.repairIndexGlyphs`).** A PDFKit line's shows (#125's ownership rule)
must all decode. Each glyph becomes the letters PDFKit reports for its name and the text of its code;
a glyph PDFKit reports as nothing (`fi`) joins the glyph before it in its word, or after it where it
starts a word, and one between two word gaps cannot be placed. PDFKit's characters must be spelled
exactly by the glyphs in reading order; each is replaced by its glyphs' text with its attributes, and
characters of other fonts and whitespace are kept. Glyphs left after the line's last character carry
to the next line when it continues the row to the right (page 12's table rows, page 17's reference
numbers), ahead of that line's own shows. A line whose index-glyph shows cannot be spelled, a carry
no line continues and an index-glyph show whose origin lies in no line are counted as unrepaired.
Repair runs before #119's spacing and #125's styles, which then read the decoded fonts' text.

**Spacing (`NativeSpacingReader`).** Decoded fonts supply its Unicode maps. Census's Distiller also
sets large character spacing that TJ adjustments offset: a heading at Tc 1.10 em with +1123 between
letters, references at Tc 0.46 em with +446. Where an array's adjustment offsets at least half a Tc of
0.1 em or more (`compensated`), a boundary's gap is adjustment plus spacing (the min rule of #119
otherwise), a zero adjustment is a boundary, and two glyphs of one string stand the spacing apart
(capped at 1 em, the quad after `2`). Without it the repaired heading reads `2DataFiles` and the
references `JournalofOﬃcialStatistics`.

**Pages.** #38's font evidence stands unless line repair read the page's index-glyph shows and
repaired every line, and the page's lines hold no numeric grid (below); the English statistics then
judge PDFKit's own text. A page drawn only in
decoded fonts therefore reflows natively; a page with an undecoded font's glyphs keeps
`damagedTextEncoding`, OCR under automatic policies, and under `.never` the source-page reference
beside its repaired lines.

## Tables stay on their previous path

The first candidate reflowed pages 12 and 15 natively. Every figure was right, but no table path
reconstructs Census's tables (a rule under the header row, right-aligned numeric columns, no cell
rules or shading, lower-case headers): `BorderlessTableDetector` needs capital headings,
`TableRegionDetector` a ruled grid, `ShadedTableDetector` shaded rows, and the conversion produced
neither a `<table>` nor a crop. The rows ran together as paragraphs (`rnkswp05 0.8861 0.9620 rnkswp10
0.2694 …`), where recognition had kept each table as an image: worse for a reader. So a repaired page
whose lines hold a numeric grid keeps #38's path (`PDFReflowLibPipeline.holdsNumericGrid`): at least
three lines, each with at least two decimal numbers (`0.8861`, `158.950`) making up at least half its
words. On the fixture, page 12's repaired rows qualify and pages 2, 3 and 17 do not (page 3's
`12. Aged exemption ﬂag` and page 17's `B, 39 (1977) 1–38.` carry no decimal); two rows are not a
grid. Pages 12 and 15 then read exactly as at the baseline (titles as headings, three images each).
A small grid page whose shifted text falls under #38's 20-word minimum would still reflow natively.

## Census before and after (defaults, `ec22aff` baseline)

| | Baseline | Candidate |
| --- | --- | --- |
| Recognized pages | 19 (2–20) | 17 (2, 4–16, 18–20) |
| Native pages with index fonts | 0 | 2 (3, 17) |
| Images | 53 | 51 |
| `--ocr never`: shifted function words (first candidate, `e8bc0c3`) | 924 | 233 (on retained pages, in lines that also hold an undecoded glyph) |

`compare_conversion_runs.py` (`lane-summaries/compare-census-rrs2002-01.json`): only pages 3 and 17
change; the 17 recognized pages have identical OCR text (5,248 words). Review of the changed pages
against 200-dpi renders, and against the baseline's OCR of the same pages:

- **Page 3.** Heading `2 Data Files`; `Two data ﬁles were used.`; the sixteen fields with `ﬂag`
  (OCR: `Ilag`); `suﬃciently`, `re-identiﬁcations`, `59,315`, `1/1600`, `(http://www.census.gov/DES)`;
  OCR's `Becaase`, `by5.` and `sex that.` are gone. Page 3 has no figure, so dropping the source-page
  image loses nothing.
- **Page 17.** Body with `diﬀerent`, `speciﬁc`, `information loss,` (OCR: `loss.`) and the closing
  `data.` OCR dropped; the fourteen references with their numbers (OCR lost several), dashes (`1–38`
  for OCR's `1-38`, `California–Riverside`), `’2001`, `Loss` (OCR: `Loas`), italic titles spaced
  (`Journal of Oﬃcial Statistics`) except entry 12 (follow-up).
- **Pages 12 and 15.** Unchanged from the baseline.

Pages 2, 4–16 and 18–20 keep OCR: numeric tables on 12 and 15; math fonts on 4–11, 13, 14, 18–20; the typewriter
e-mail line (`dctt`, one word) and the title's footnote mark (`cmmib`, bitmap `T2`) on page 2; and on
page 16 PDFKit reads the line ending `The test` beside the next line's leading `fi` as a line with
three extra `t` lines (`Wkh whvw`, `w`, `w`, `w\nohv…`), which no show spells.

## Lanes

`tools/run_corpus_regressions.py --case <id>` for each binary (one case per call, EPUBCheck, probe,
`--execution-context host-terminal`), then `tools/compare_conversion_runs.py
--allow-different-converters`, against `ec22aff`. Census's contract was updated first (below), so
the baseline fails it.

| Case | Baseline | Candidate | Changed pages |
| --- | --- | --- | --- |
| census-rrs2002-01 | fails the new contract (14 errors: pages 3, 17) | pass (71 checks) | 3, 17 |
| gpo-911-2004 | pass | pass | 45, 63, 194, 202, 309, 478, 485, 490, 560, 580 text; 42, 74, 75, 90, 301, 380, 489 note links to them |
| fed-explained-2021, faa-phak-8083-25c, wallace-algebra-2010, scotus-loper-bright-2024, gpo-our-flag-2003 | pass | pass | none |

On `e8bc0c3` the first candidate also left CDC, arXiv, NBS, DGA, USGS and Blue Book unchanged.

9/11's changes are the compensated spacing rule on letter-spaced lines (Tc 0.13–0.18 em with +131
to +177 between letters): `House.... Six, southwest.` and `it. . . . Okay.` (page 45), `threat....
I’m`, `inoperable.... We`, `real. ... Do`, `him. ... My`, `Muslims.’... Islamism`, and note citations
`Air War Over America, p. 60.` (478), `Inside Al Qaeda, p. 23.` / `p. 34.` (485), `The Cell, p.` (490),
`Bombing, p. 11.` (560). This closes the run-together ellipses the
[kerned-sentence-spaces record](../kerned-sentence-spaces-and-fusions/record.md) left closed by design
(its defect 3). Each was the run-together form before; page 45's two lines were checked on
a 200-dpi render and page 478's against Poppler's text (`Air War Over America, p. 60.`). The same
twelve changes, and no other, appear against `ec22aff`. SCOTUS and
FAA have compensated arrays but no changed page. Warren (no TJ) and NOAA (no compensated array, not
converted by the lane) were not run.

Lane wall time (conversion, EPUBCheck, content): Census 8 s → 7 s, 9/11 15 s → 15 s, FAA 49 s → 50 s,
Wallace 26 s → 27 s. The decoder's pass reads each page's resource dictionary once and scans
content streams only on pages with an index-style font.

## Content contract

`corpus/regressions.json`, `census-rrs2002-01`: pages 3 and 17 replace `damagedTextEncoding` and
`minimumImages` with `absentWarningCodes` (`damagedTextEncoding`, `ocrUsed`; page 3 also
`unverifiedTextLayer`), `maximumImages: 0`, ordered phrases read from the source renders (ligatures as
the library emits them: `ﬁ`, `ﬂ`, `ﬀ`, `ﬃ`) and absent shifted forms. Pages 12 and 15 keep
`damagedTextEncoding`, require three images, and forbid the run-together rows the first candidate
wrote (`0.9620 rnkswp10`, `0.7287 rnkswp15` for Table 2; `88.32 rnkswp10`, `13.85 add01_sw` for
Table 7; all four were in its EPUB text) and the shifted forms. The other body pages keep their
checks. 71 checks on 20 pages (54 before).

## Tests

`Tests/PDFReflowLibTests/GlyphIndexDecodingTests.swift` (8 tests) and one changed expectation:

- **Source fixture** `fixtures/census-text-operators.json` (`capture.swift`; source checksum pinned
  and checked against `census-3`): Census pages 2, 3, 12, 17 and 20 with font dictionaries,
  graphics states, decoded content streams and PDFKit's lines. Rebuilt with non-embedded fonts:
  - `censusTextFontsDecodeThroughTheOffsetTheirOwnWordsEstablish`: exactly `dcr`, `dcbx` and `dcti`
    decode, `dcr`'s 80 codes with `T`, `ﬁ`, `ﬀ`, quotes and the en dash; +3 passes, +35 and 0 fail;
    controls: French, page 12 alone, page 20 alone (only `dcr`).
  - `censusLinesAreRewrittenFromTheirShowsAndMathLinesAreNot`: every line of pages 3, 12 and 17
    repaired, 24 reviewed lines exact (carried table rows and reference numbers); page 2's two
    undecodable lines and every line of page 20 unrepaired; page 12's rows form a numeric grid and pages
    2, 3 and 17 do not; with no decodings nothing is rewritten.
  - `censusWordGapsAreReadFromCompensatedCharacterSpacing`: `2 Data Files`, `[1] Dempster, A. P.,
    Laird, N. M. and Rubin, D. B.: Maximum Likelihood from`, `of Oﬃcial Statistics`, `Table 2.
    Domingo Data Reidentiﬁcation Rates`; control without decodings.
- **Synthetic:** `offsetsNeedEnglishWordsLowercaseLettersAndOneAnswer` (offsets +3, 0, −29; a
  permutation, capitals only, lowercase only, a short text, mathematics, a capital heading font);
  `droppedLigaturesJoinTheirWordAndCarriedGlyphsContinueTheRow`; `corkAndSharedTablesDecodeOnly…`
  (tables, names, PDFKit's characters for index names).
- **End to end:** `pagesWhoseIndexGlyphsAllDecodeReflowNativelyUnderEveryPolicy` builds Type1 fonts
  at a constant offset, a font without one, and a line mixing a decoded font with WinAnsi Helvetica:
  and a page of sixteen numeric table rows in the decoded font: under `.never` and `.automatic` only
  the page with the undecodable font and the table page report `damagedTextEncoding` (and OCR), the
  others reflow repaired, the retained page keeps its repaired
  lines, and German decodes nothing. `theTypeThreeReproducerStaysDamaged…` records why #38's Type3
  fixture keeps its tests: its font decodes, but PDFKit reads its five shows as one line.
- **Changed:** `nineElevenSameFontWordSpacesAreRestoredOnSourcePages` now expects `House.... Six,`,
  `Six, south-`, `... Okay.` on page 45, removed from the list of run-together forms (render above).

Mutation checks (`swift test --filter 'GlyphIndexDecodingTests|NativeSpacingTests|DamagedEncodingTests|FontWeightDetectionTests'`
with one part disabled; sources restored):

| Part disabled | Failing tests |
| --- | --- |
| offset evidence (no font decodes) | 6 |
| long-word requirement | 1 |
| lowercase requirement | 1 |
| capital placement | 1 |
| Cork table | 4 |
| standard names in index fonts | 2 |
| dropped glyph joins the glyph before it | 1 |
| carry to the next line of the row | 2 |
| unplaced index shows | 1 |
| compensated gap is adjustment plus spacing | 1 |
| in-string gaps under compensated spacing | 2 |
| decoded fonts in the spacing reader | 1 |
| undrawn undecoded fonts are not evidence (pipeline) | 1 |
| statistics judged on PDFKit's text (pipeline) | 1 |
| numeric grid keeps the font evidence (pipeline) | 1 |

## Commands

```sh
git merge e8bc0c3
swift build -c release && swift test          # 693 tests on ec22aff (685 + 8)
scripts/check-all.sh --fast                   # passed
swiftc -O -parse-as-library measurements/glyph-index-decoding/capture.swift -o <scratch>/capture
swiftc -O Sources/PDFReflowLib/FontWeightReader.swift Sources/PDFReflowLib/NativeSpacingReader.swift \
  Sources/PDFReflowLib/TextEncodingCheck.swift Sources/PDFReflowLib/GlyphIndexDecoder.swift \
  measurements/glyph-index-decoding/survey.swift -module-name survey -parse-as-library -o <scratch>/survey
python3 tools/run_corpus_regressions.py --converter <dir>/pdf-reflow --epubcheck /opt/homebrew/bin/epubcheck \
  --output <lane> --case <id> --environment-probe <probe> --execution-context host-terminal
python3 tools/compare_conversion_runs.py --baseline <base-lane>/<id> --candidate <cand-lane>/<id> \
  --output <cmp> --allow-different-converters
```

## Limits and follow-up defects

1. **Math fonts stay undecoded** (`cmmi`, `cmr`, `cmsy`, `cmex`, the bitmap Type3 fonts): their
   glyph positions follow no constant offset or set no words, so eleven Census pages stay on OCR.
   Page 20 expected: `and for diﬀerent noise proportion parameters d, we compute a masked data set`,
   the display `Z = X + dY.` preserved as an image. Glyph identity would need outline evidence.
2. **Census page 2** keeps OCR for the e-mail line (`dctt`, 63 glyphs, one word) and the title's
   footnote mark. Expected `{william.e.yancey,william.e.winkler,robert.h.creecy}@census.gov` and the
   abstract as native text.
3. **Census page 16:** PDFKit splits the line `masking methods. The ﬁrst is that the suitable test
   ﬁles are needed. The test` / `ﬁles should have variables in which the distributions are
   representative of actual` into four overlapping lines with duplicated `t`s; expected those two lines.
4. **Census pages 12 and 15** stay on OCR with table images because no table path reconstructs
   their rule-headed numeric tables. Expected native text with a `<table>` (Table 2: columns
   `d metric`, `l metric`; row `rnkswp05 | 0.8861 | 0.9620`) or a table crop.
5. **Census page 17:** the headings `7 References` and `References` merge into one heading
   `7 References References`; each reference number is its own paragraph before its entry (`[2]`,
   then `Dalenius, T. …`), expected `[2] Dalenius, T. and Reiss, S. P. Data-swapping: …`; entry 12
   keeps `JournalofOﬃcialStatistics` (expected `Journal of Oﬃcial Statistics`); PDFKit's `[ 5]`
   (page 3) and `[ 3]` spacing, expected `[5]`, `[3]`; `Univer-sity` expected `University`.
6. **Census page 3:** `2.1 Domingo-Ferrer and Mateo-Sanz` opens the paragraph it heads instead of
   standing as a subsection heading, and `The ﬁle also has match code and a variety of identiﬁers
   and data from the` is split from its sentence's continuation `public-use CPS ﬁle.`
7. **A font of capitals alone** without digits or punctuation inside words could still decode in
   lowercase; none exists in the corpus.
8. **PDFKit's name mapping** is measured on macOS 27 only; if it changes, repair stops matching and
   pages fall back to #38's path rather than emitting wrong text.
