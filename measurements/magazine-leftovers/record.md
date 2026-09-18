# Magazine leftovers: a dingbat, a misreported capital, bare-page headings, word breaks and a sidebar title (#186)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Baseline `4a636ae` (the coordination branch's head, which carries #158's crops, #187's alt text,
#189's ligatures and #150's borderless tables); candidate this tree on it.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `4a636ae` | `e9f4a0f3df2df9639a31c7efe3b09d43c9a699f41cf38ff49f3dd1a763446238` |
| candidate | this tree on `4a636ae` | `083371484c10bc11397708bd08b31697d7765de39ead67f8094e645b63461c0e` |
| probe | `tools/probe-raster-environment.swift` | `1b6ceaa595f3f673d23e46ddb02f2431f289da12b2c023c0c14075ef887650a5` |

Python 3.14.6; EPUBCheck from `/opt/homebrew/bin/epubcheck`. No source PDF, EPUB or raster is
committed; each evaluation was deleted once its result was recorded. Two source fixtures were captured
with `tools/capture-layout-fixture.swift` (`usda-1`, `usda-24`, text and geometry only; the back cover's
logos and indicia are not in them). Source bytes were read with `qpdf --show-object`, `mutool draw -F
stext` and `pdffonts`; geometry against 60 DPI Poppler renders.

## What had already changed

Reproduced on `4a636ae` for USDA ARS *Agricultural Research*, November/December 2012
(`usda-ars-agresearch-2012-11`):

| Item | State on `4a636ae` |
| --- | --- |
| 1. back-cover dingbat | reproduces: `ars.usda.gov/ar <sup>l</sup> Follow us`, inside an `<h6>` |
| 2. `BRAD FRITz` | reproduces |
| 3. mailing panel, cover lines | reproduce, but the tiers moved: the panel's five lines and the cover's `pages 2, 4-14` and tagline are all `<h6>` |
| 4. `com-panies`, `infec-tions`, `compli-ance` | reproduce, each with `uncertainHyphen` |
| 5. `Fighting Filth Flies` | reproduces: `<p><strong>` |
| 6. page 13's credit first | **fixed by #158.** The page no longer carries an `Original page 13` image; its photograph is a crop (540 × 422 points, y 334–756), and `SETH BRITCH (D2644-1)` is set 1.7 points *above* it at the top right, so credit-then-photograph is the page's own order, as on pages 4 and 15. Now pinned (below). |
| 7. tiers by size | the symptom is gone: there are more tiers than levels, so the panel and the nine-point subheads are all clamped to `<h6>` and neither outranks the other. Ranking by size remains the design (#43). |

## Evidence and causes

### The dingbat (item 1)

`pdffonts` lists `WVUHWN+MonotypeSorts` on every page as an **embedded** CID TrueType subset with a
ToUnicode map (object 880, map 881). The issue's "not embedded" was PDFKit's report: it names the run
`Helvetica`. The map holds one entry, `<004F> <006C>`: glyph 79 reads as `l`. Monotype Sorts is Zapf
Dingbats' clone, and in the Zapf Dingbats encoding code `l` (0x6C, glyph `a71`) is ● U+25CF. The map
copied the font's ASCII code, so no private-use value reaches #155's decoder. The back cover draws it
at 6 points with a text matrix one point above the 11-point line (`6 0 0 6 275.08 46.43 Tm <004f>
Tj`), which PDFKit reports as baseline offset 1, hence `<sup>`. The running foot draws the same glyph
at 4 points on pages 2–23.

### The credit's `z` (item 2)

Page 15's credit is set in `WVUHWN+Helvetica-Condensed` (object 1007), an embedded Type 1C font,
`WinAnsiEncoding`, descriptor flags 32 (`Nonsymbolic`), `CharSet (/parenleft … /Y/Z/c/e/m/n/o/r/s/t)`
— capitals `/Z` and no `/z`. The content stream sets the credit in capitals and gives the lowercase
letters in marked-content `ActualText`:

```
(B)Tj … /Span <</ActualText <feff007200610064>>> BDC (RAD)Tj EMC … ( F)Tj
/Span <</ActualText <feff007200690074>>> BDC (RIT)Tj EMC … (Z \(D2697-1\))Tj
```

The last `Z` carries no `ActualText`; InDesign wrote its lowercase source letter into the ToUnicode map
instead (`<5A> <007A>`). PDFKit ignores `ActualText` and trusts the map, so it reads `BRAD FRITz`;
Poppler honours `ActualText` and reads `Brad Fritz`. The page draws capitals, and every other credit
reads in capitals through PDFKit (`PEGGY GREB`, `REGIS LEFEBURE`, whose lowercase letters are also
only in `ActualText`). The glyph is the evidence the rest of the line is already read by.

### Bare pages (item 3)

Page 24's lines outside its crops are 10- and 11-point; its page estimate is 8 points, from the
subscribe box's eighteen 8-point lines inside a crop, and `headingBodySize` keeps that estimate because
the reflowable text (seven lines) establishes no body. The threshold is then 10 points: the 10-point
return address and `Official Business` and the 11-point web line pass it, and the sub-threshold label
path (1.15 × 8) admits them too. The magazine's columns are 10.5 points.

The cover (page 1) sets 10-point header lines, the 68.6- and 40-point cover lines, the 15-point
`pages 2, 4-14` and the 14-point tagline. `pages 2, 4-14` stands alone under a line 2.7 times its size
and opens in lowercase. Across the baseline corpus, 38 headings open with a lowercase letter: 32
Census OCR body lines, the 9/11 cover's `official government edition`, the CDC comic's
`http://emergency.cdc.gov` and a wrapped list line, Wallace's `whenever possible.`, the magazine's
`pages 2, 4-14` and a pull quote's second line. None is a title. On the candidate 11 remain, each
stacked with another heading-size line (nine Census lines, the CDC list line, the pull quote), which
the rule leaves to the title and pull-quote readings.

### Word breaks (item 4)

The magazine prints none of `companies`, `infections`, `compliance`, or an inflection of them
(`pdftotext`: each occurs once, as the broken word; `infected` once), so #115's evidence is absent and
the policy keeps the hyphen with `uncertainHyphen`, as designed. The #148 record already named a
lexicon as the only evidence that could close such a break. The system's English lexicon
(`NLEmbedding.wordEmbedding(for: .english)`, 57,171 words, already read by `TextLayerPlausibility`)
holds `companies`, `infections` and `compliance` and none of `com`, `panies`, `infec`, `tions`,
`compli`, `ance`.

### The sidebar title (item 5)

`Fighting Filth Flies` (9-point Helvetica-Bold, the magazine's recurring subhead style) stands at
the top of the middle column, y 745.4. The sidebar's photograph spans x 219–400, y 598–740 (6 points
beneath the title); its caption (7.98 points) and a rotated credit sit under and beside it; the
sidebar's text opens at y 553.5 on the column's 10-point first-line indent. `opens(beneath:)` read only
the nearest line below the title, 142 points away.

## Rules

- **`FontWeightReader.drawnGlyphs`** records, per font, codes whose glyph is another character than
  the map reports: in a dingbat font (`BaseFont`, `FontName` or `FontFamily` naming Zapf Dingbats, ITC
  Zapf Dingbats, `Dingbats` or Monotype Sorts) every code the map reads as a character of the Zapf
  Dingbats encoding reads as its pictograph (`zapfDingbats`, Adobe's `a1`–`a191`: U+2700 + code − 0x20
  for 0x21–0x7E except ☎ ☛ ☞ ★ ● ■ ▲ ▼ ◆ ◗, and the 0xA1–0xFE ranges); in a non-symbolic Type 1 font
  with a map and a WinAnsi-based encoding, a code whose map and encoding name the same ASCII letter in
  different case reads as the encoding's letter, unless the descriptor's `CharSet` lists the map's
  glyph or lacks the encoding's. Each show keeps its glyphs' reported and drawn text (`redraws`).
- **`FontWeightReader.redrawGlyphs`** rewrites a line's characters where its shows (`lineShows`) all
  decode and their reported characters spell the line, so a glyph is found at its own place. A line
  the page draws twice in one place (page 23's running foot, 0.17 points apart) is one line: the copy's
  rectangle claims no show and the copy's duplicate shows are dropped. `NativeTextReader` applies it
  after spacing and style evidence, to whole lines and to split pieces, and only where the attributed
  and semantic text agree. `tools/capture-layout-fixture.swift` captures attributed lines through it.
- **`NativeTextReader.isSeparatorBullet`**: a run of bullets and whitespace set a word space from the
  text on both sides (or ending the line) is no script. #155's control `a <sup>•</sup> b` now reads
  `a • b`; a bullet against a word and a raised letter stay scripts.
- **`LayoutReconstructor.documentHeadingFloor`**: on a page whose reflowable text establishes no body
  (`establishedBodySize`: three lines and 200 characters in their commonest size), a heading must be
  1.1 × the document's body, the size most of its native, unrecognised text is set in (the pipeline's
  first pass accumulates it); a label its size alone sets apart must clear the same floor. A page that
  establishes its body is unchanged.
- **Lowercase display lines**: a heading-size line opening in lowercase that stacks with no other
  heading-size line above or below it (`stacksUnderHeading`) is not heading-size.
- **`LayoutReconstructor.lexiconVouches`**: in a document declared English (the pipeline marks the
  vocabulary with `englishLexiconKey`), a lowercase line-end break the book's words and inflections
  leave undecided removes its hyphen when the lexicon holds the joined word and the halves are not both
  words (of the lexicon or the book), with #115's lengths. A hyphen PDFKit lost (#157,
  `lostLineEndHyphen`) does not consult it.
- **`sectionLabels`' `pastFigure`**: a sub-heading's paragraph may open past a picture set directly
  beneath the title (no thin rule; its top within 0.8 body of the title's foot; spanning the title's
  left edge and width), with only smaller type between the picture and the opening, the opening within
  four bodies of the picture or its last caption line (the crop takes page 9's caption, 31 points). A
  caption's own label is refused. Every other sub-heading test (recurring bold style, clear space,
  first-line indent for a title under the body's size) still applies.

## Contracts (`corpus/regressions.json`)

35 checks added (3,422 → 3,457) on 560 → 563 reviewed pages, plus one rewritten:

| Case | Added | Checks |
| --- | ---: | --- |
| `usda-ars-agresearch-2012-11` | 23 | page 1: `pages 2, 4-14` a paragraph, not a heading; 6, 15, 19: the joined words present and the broken ones absent; 9: `Fighting Filth Flies` a heading; 13: the credit captioned `before` its photograph; 15: the caption `BRAD FRITZ (D2697-1)` (replacing `BRAD FRITz`) and `BRAD FRITz` absent; 24: six absent headings, three paragraphs, `ar l Follow` absent, no `<sup>l</sup>` and no `<sup>●</sup>` |
| `gpo-911-2004` | 4 (+1 page) | page 3: the title still a heading, `official government edition` a paragraph and no heading; page 172: `excep-tional` absent. Page 172's `excep-tional commodities.` text check is rewritten to `exceptional`; its `uncertainHyphen` stays (`unquestion-ably` is still undecided, the lexicon lacks `unquestionably`) |
| `fed-explained-2021` | 2 (+1 page) | page 62: `Figure 4.5. …` a paragraph and no heading, as the book's other 33 figure titles already were |
| `wallace-algebra-2010` | 3 (+1 page) | page 266: the practice title still a heading, `1)` and `Solve.` no headings |
| `census-rrs2002-01` | 2 | pages 4 and 6: an OCR body line opening in lowercase is no heading |
| `cdc-zombie-pandemic-2011` | 1 | page 5: `http://emergency.cdc.gov` is no heading |

The baseline fails 32 checks: 31 of the 35 new ones and the rewritten page-172 text. The four it
passes are controls or already-fixed state: the magazine's page-13 credit (#158), its absent `<sup>●</sup>`,
and the 9/11 and Wallace title-heading controls. The candidate passes all 3,457.

The review file's acceptance text for magazine pages 1, 6, 9, 13, 15, 19 and 24 records the change.

## Tests

`Tests/PDFReflowLibTests/MagazineLeftoversTests.swift`, 11 tests; `ShiftedScriptBaseTests` gains one
and its #155 control changes (above).

| Test | Reproducer / control |
| --- | --- |
| `aDingbatFontsLetterReadsAsItsPictograph` | The magazine's composite Monotype Sorts map in an in-memory PDF: `ars.usda.gov/ar ● Follow us`, `Follow`'s two `l`s kept, no `<sup>`; `ZapfDingbats` and `ITCZapfDingbats` alike. |
| `aLetterMappedByAnyOtherFontStays` | The same font and map named `SyntheticSans` keeps `l`; table and family spot checks. |
| `aMapThatContradictsItsEncodingInCaseReadsTheCapitalDrawn` | The credit font's dictionary and map: `BRAD FRITZ (D2697-1)`. |
| `aMapIsTrustedWithoutTheFontsOwnEvidence` | Controls: a `CharSet` listing `/z`, a symbolic font, a map naming `q`. |
| `aBareBackCoverSetsNoHeadingUnderTheDocumentsBody` | `usda-24` with the 10.5-point document body: no headings. Control: without it, the address and `Official Business` are headings. |
| `theDocumentsBodyDoesNotLowerAPageThatStatesItsOwn` | An 11.5-point title over 9-point prose in a 12-point document stays a heading; the floor is zero on an established page. |
| `aLowercaseLineAloneOnTheCoverHeadsNothing` | `usda-1`: the cover lines stay headings, `pages 2, 4-14` is a paragraph. |
| `aLowercaseLineStackedInATitleKeepsItsReading` | `The Role of` / `the Federal Reserve` stays one heading; a lone capitalized line stays one. |
| `aSidebarTitleHeadsTheTextPastItsPicture` | `usda-9` with the book's subhead style: `Fighting Filth Flies` is the page's heading, before the sidebar's text. |
| `aTitleOverAPictureNeedsItsTextCloseBeneath` | Controls: no picture, the text five bodies lower, no recurring style. |
| `anEnglishLexiconDecidesABreakTheBookCannot` / `theLexiconLeavesCompoundsAndShortHalves` | The three magazine breaks join only with the English key (control: kept and warned without it); `on-going`, `e-mail`, an unknown word and a compound the book prints keep their hyphen. Skipped where the system has no lexicon. |

## Corpus lanes

`tools/run_corpus_regressions.py`, one case per call, with the compiled raster/Vision probe and
`--execution-context host-terminal`, baseline and candidate; `tools/compare_conversion_runs.py
--allow-different-converters --detail` on every case. **All 19 English lane cases pass on the
candidate** (the magazine and 9/11 fail on the baseline only through the checks above). No image
changed and no image was renamed in any case.

| Case | Changed pages | Heading changes | Hyphens removed | `uncertainHyphen` pages |
| --- | ---: | --- | ---: | --- |
| usda-ars-agresearch-2012-11 | 15 | −5 (page 24), −1 (`pages 2, 4-14`), +1 (`Fighting Filth Flies`) | 11 | 14 → 11 |
| gpo-911-2004 | 260 | −1 (`official government edition`); the removed h4 tier lifts 245 headings one level (h5 → h4, and 196 of 244 h6 → h5) | 68 | 133 → 75 |
| scotus-loper-bright-2024 | 40 | none | 44 | 51 → 25 |
| wallace-algebra-2010 | 160 (147 heading ranks only) | −33 on 7 exercise pages (`1)`…`22)`, `Solve.`, `whenever possible.`) | 6 | 10 → 4 |
| fed-explained-2021 | 58 (50 heading ranks only) | −1 (`Figure 4.5. …`) | 8 | 18 → 13 |
| census-rrs2002-01 | 13 | −23 OCR body lines opening in lowercase | 6 | 6 → 2 |
| cdc-zombie-pandemic-2011 | 24 (23 heading ranks only) | −1 (`http://emergency.cdc.gov`) | 0 | 0 → 0 |
| nbs-jres-geltman-1977, arxiv-replay-clocks-2023, ntrs-20190030725-dasc-2019 | 2 each | none | 2 each | 6 → 6, 2 → 0, 4 → 3 |
| techport, earthdata slides, Our Flag, FAA, DGA, Blue Book, USGS copper, Pro Se 1, GWL | 0 | — | — | — |

Review, every change read against the source text:

- **Hyphens.** 149 words across nine documents lose a line-end hyphen; all 149 were read and all are
  hyphenation breaks of ordinary words (`excep-tional`, `bun-galow`, `con-stitutionality`,
  `pharma-ceutical`, `dis-ease`, `over-whelming`, `re-jection`, `where-withal`, `noncoopera-tion`).
  None gains a hyphen. Undecided breaks whose halves are both words stay (9/11's `camera-man`), as do
  words the lexicon lacks (`unquestion-ably`). Where #153 left a broken word's halves in separate
  paragraphs, the magazine's pages 5 and 14 now join them (`con-` + `sider`, `col-` + `laborations`),
  since #148's `continuesWordBreak` accepts the lexicon's decision.
- **Headings.** Every lost heading was read; none is a title. Wallace's exercise numbers and
  instructions were headings only on seven practice pages whose problems are crops (the book's other 31
  instruction lines were already paragraphs); Fed's `Figure 4.5.` was the only figure title of 34 read
  as a heading. No heading was gained outside the magazine's `Fighting Filth Flies`. The 9/11 report's
  cover line was its only 4th tier, so every smaller tier moves up one level; its chapter titles now
  read `<h5>` rather than `<h6>` and 48 of its smallest titles stay `<h6>` instead of sharing it.
- **Glyphs.** The dingbat and case rules change text only in the magazine (`BRAD FRITZ`, and `●` on
  pages 23 and 24: page 23 still prints its running foot once, #158's doubled-foot defect). No
  `<sup>`/`<sub>` changed in any other document; the magazine loses its two `<sup>l</sup>`.

Warren and NOAA are outside the lane (#5) and were not converted.

Disk: 44–76 GB free throughout, checked before each conversion.

## Verification

- `swift test`: 957 pass.
- `scripts/check-all.sh --fast`: exit 0.
- `tools/check_corpus_content.py` on each candidate and baseline evaluation of the six cases whose
  contracts changed (above).
- `python3 tools/update_doc_counts.py`.

## Remaining defects

1. **The cover's tagline is still a heading.** `Agricultural Research Service • Solving Problems for
   the Growing World` is 14-point bold, 1.4 times the page's header strip and 1.3 times the document's
   body, in the page's foot band with nothing beneath it. Neither size nor case sets it apart from a
   title, and a heading-size line at a page's foot is also how a section opens before a page break
   (#103), so it is left.
2. **The back cover's logo crop splits the return address.** The ARS logo's crop (x 36–72) stands
   level with the address and is ordered after its first two lines.
3. **Heading tiers still rank by size alone** (item 7). With the back cover's lines no longer
   headings, no display type outranks the section titles in this magazine; the pull quotes on pages
   11, 12 and 14 are still headings (#158's defect 3) and share the subheads' `<h6>`.
4. **`unquestion-ably`** and other words outside the 57,171-word lexicon still keep their hyphen
   with `uncertainHyphen`.
