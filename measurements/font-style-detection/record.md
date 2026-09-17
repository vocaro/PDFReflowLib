# Italic, Libertine weights, undecoded mixed lines and split runs (#133)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Work started on `0fa3057` (#125's font weight reader) and merged, without committing, the tip
`277cbde` (bfe0476 Fed tables, fbe5805 sentence spaces, 2a30da1 OCR retry, 277cbde NBS scan
figures). Every figure below compares binaries built from `277cbde` and from this tree on it, with
one capability probe for both. Lanes run before the merge against a `0fa3057` baseline gave the
same changed-page counts and classes in every case but the CDC comic, whose 30th page changed only
once composite codespaces were relaxed (below).

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `277cbde` | `130fcace83545864b9827ef3c0e97b9e55c79778b037b1171e97af470a19bd9c` |
| candidate | this tree on `277cbde` | `9b069788c578f337e14cc21d9baea687b7b935cced392eb8cdb63861acb2b7cf` |
| probe | `tools/probe-raster-environment.swift` | `c53464fd9f526ea3284bcad1ce629c3b4f5c7eeaf241067b6baeff6928c8d0c8` |

No source PDF or EPUB is committed. Each lane's EPUBs were deleted after review;
`lane-summaries/` keeps both run summaries, the comparison and the page classification per case.

## Diagnosis

#125 showed that PDFKit names an embedded font only when the system has one by that name, so
every run of the Fed, 9/11, Wallace, Our Flag, DGA, Supreme Court and most of NOAA reports
`Helvetica`. `NativeTextReader.inlineText` read italic only from `italic` or `oblique` in that
name, so every embedded italic was lost: 9/11's `Bembo-Italic` (725 shows: ship names, foreign
terms, book titles), the Supreme Court's `CenturySchoolbook-Italic` (1,773 shows: case names),
the Fed's `FranklinGothicLTPro-BkIt`/`-DmIt`, Our Flag's `StoneSerif-Italic`, arXiv's
`LinLibertineTI`, NOAA's `Lora-Italic`/`Roboto-Italic`.

Three gaps also remained in #125's bold:

- **Libertine.** arXiv's `LinLibertineTB` and `LinBiolinumTB` state bold only in the Libertine
  naming scheme's capital after the format letter `T`.
- **Undecoded mixed lines.** `apply` needs every show on a line decoded to split a line's styles.
  Its decoding read only simple fonts' ToUnicode maps under a one-byte codespace. Three forms fell
  through: Wallace's Computer Modern fonts have no ToUnicode map, only a WinAnsi encoding
  (`World View Note:` on a regular line); the Supreme Court's Century Schoolbook maps declare
  PScript5's `<00> <EF>` plus `<F000> <FFFF>` codespace over one-byte entries (1,229 lines); DGA,
  NOAA and the CDC comic set text in `Identity-H` Type0 fonts with two-byte maps (DGA 88 lines,
  CDC 217).
- **Split runs.** `EPUBTextEncoder` wrapped each `InlineText` element separately, so a style split
  across PDFKit runs became `<strong>F</strong><strong>AA</strong>…` (FAA cover).

## Survey

`tools/survey-font-weights.swift` (extended; build and run as its header says) records for each font
resource the name, subtype, FontWeight, StemV, Flags, ItalicAngle, ToUnicode and show count,
PDFKit's names for lines drawn in it alone, both bold verdicts, the name's slope and both italic
verdicts. It then counts the PDFKit line runs (with a letter or digit) whose bold or italic status
the reader changes, and the lines with a styled show that stay unresolved because a show does not
decode and the shows do not share the style. Tables are in `survey/` (one per book; Warren and
NOAA in page ranges), from the final reader on `277cbde`; the survey was first run, with the same
verdicts for every font, before `inlineText` or the encoder changed. Every English corpus book is included;
the Arabic and Chinese cases are not.

| Book | Font resources | Line runs | Bold changed (pages) | Italic by name rule | Italic with resources | Italic changed (pages) | Unresolved mixed lines |
| --- | --- | --- | --- | --- | --- | --- | --- |
| fed-explained-2021 | 25 | 4,793 | 530 (121) | 0 | 119 | 119 (61) | 0 |
| gpo-911-2004 | 9 | 29,310 | 797 (243) | 0 | 763 | 763 (195) | 0 |
| wallace-algebra-2010 | 35 | 38,580 | 1,773 (408) | 0 | 10 | 10 (7) | 6 |
| scotus-loper-bright-2024 | 9 | 7,339 | 0 | 0 | 1,560 | 1,560 (114) | 1 |
| gpo-our-flag-2003 | 5 | 1,893 | 172 (44) | 0 | 191 | 191 (15) | 0 |
| dga-2025-2030 | 6 | 428 | 40 (9) | 0 | 5 | 5 (3) | 0 |
| arxiv-replay-clocks-2023 | 19 | 2,553 | 206 (12) | 0 | 39 | 39 (8) | 0 |
| cdc-zombie-pandemic-2011 | 22 | 929 | 583 (32) | 234 | 405 | 171 (27) | 0 |
| census-rrs2002-01 | 13 | 1,093 | 21 (10) | 3 | 4 | 1 (1) | 50 |
| noaa-nca5-2023 | 75 | 100,878 | 5,247 (1,279) | 2 | 3,463 | 3,461 (1,031) | 1 |
| faa-phak-8083-25c | 129 | 35,589 | 6 (1) | 1,680 | 1,681 | 1 (1) | 147 |
| cia-blue-book-14-1955 | 9 | 152,722 | 0 | 86,465 | 86,465 | 0 | 0 |
| nbs-jres-geltman-1977 | 7 | 3,686 | 0 | 318 | 318 | 0 | 13 |
| usgs-mcs2025-copper | 4 | 190 | 0 | 0 | 0 | 0 | 0 |
| gpo-warren-1964 | 2 (OCR `Courier`) | 417,823 | 0 | 0 | 0 | 0 | 0 |

"Bold changed" counts against PDFKit's name rule, so it includes #125's changes. The decoders added
here raise Wallace from #125's 1,449 runs to 1,773, CDC from 495 to 583 and arXiv from 1 to 206
(Libertine). Unresolved lines remain only where PDFKit already names the fonts (FAA, NBS), in
Census's `dc` fonts with custom encodings, and in one Supreme Court and one NOAA line.

Italic fonts PDFKit reports as `Helvetica` (shows summed over the book):

| Book | Font (subset tag removed) | Flags | ItalicAngle | Shows |
| --- | --- | --- | --- | --- |
| Supreme Court | CenturySchoolbook-Italic (TrueType) | 98 | −15 | 1,773 |
| 9/11 | Bembo-Italic, Bembo-BoldItalic | 70, 262214 | −11.5 | 778 |
| NOAA | Lora-Italic, Roboto-Italic, Roboto-BoldItalic, Arial-ItalicMT (TrueType and Type0) | 68–98 | −3, −12 | 11,716 |
| Our Flag | StoneSerif-Italic | 98 | −12 | 345 |
| Fed | FranklinGothicLTPro-BkIt / -DmIt, MinionPro-BoldIt, FrutigerLTStd-LightItalic | 96, 98 | −1, −12 | 120 |
| arXiv | LinLibertineTI | 4 | −12 | 40 |
| Census | dcti10084 | 68 | −14 | 40 |
| Wallace | EuropeanComputerModern-ItalicRegular12pt | 32 | 0 | 10 |
| DGA | RobotoCondensed-Italic | 96 | −12 | 6 |
| CDC | Corbel-BoldItalic, Corbel-Italic, Verdana-Italic, SegoeUI-BoldItalic (Type0) | 96, 131168 | −120 to −130 | 203 |

Every font the reader reads italic states it in its name. The descriptor decides only CDC's
`FranklinGothic-Medium` (FontWeight 700, Flags 96, no shows). The descriptor is unreliable where
the name is clear: the Fed's `BkIt` leans −1°, Wallace's `ItalicRegular12pt` carries neither flag
nor angle, and Wallace's `CMMI12` (math italic) also reports angle 0 with Flags 34. So the name
comes first, and the descriptor is read only where the name states no slope.

Fonts that lean without emphasis:

- **Math italic.** TeX's `CMMI6`–`CMMI12` and `CMMIB7`/`CMMIB10` (Wallace, 19,482 shows), `cmmi10084`
  (Census, 393), and newtx's `LibertineMathMI`/`MI5`/`MI7`, `NewTXMI`/`MI5` and `txmiaX` (arXiv,
  1,140). Built with math italic read as italic (on `0fa3057`), the survey reaches 14,193 italic runs on 385
  Wallace pages (`x`, `y`, `a`, `b` one or two letters at a time) and 929 on all 12 arXiv pages. The
  arXiv variables are already the mathematical alphanumerics (`𝑅𝑒𝑝𝐶𝑙`, U+1D445…), which carry the
  slope in the character. **Decision: math italic is never italic.** `<em>` is stress emphasis,
  which assistive reading can voice, and the encoder has no non-emphasis italic (`<i>`, `<var>`).
  The book's text italic (Wallace's `The Elements`, `Check:`) is still read.
- **Script faces.** Our Flag's `SnellRoundhand-BoldScript` (Flags 262240: Italic and ForceBold;
  ItalicAngle −40) sets its section titles, drop caps and signatures. A first lane marked every
  title `<strong><em>`. Calligraphy's slant is its letterform, so a script face (the Script flag,
  or `Script` in its name) is not read italic. Its bold, from #125, stays.
- **Symbol fonts.** TeX's `CMSY10` leans −14°. TeX short names decide by name alone, and a symbolic
  font (Symbolic flag without Nonsymbolic) whose name states no slope is never italic.

## Rule

`FontWeightReader` (extended).

**Slope.** The name, without its subset tag, is read first:

- **Italic:** `italic`, `oblique`, `kursiv`, `slanted` or `inclined` anywhere, or `It`, `Ital` or
  `Obl` as a style-suffix token (`BkIt`, `SemiboldIt`); a TeX, EC or cm-super short name with an
  italic or slanted shape (`cmti`, `cmbxti`, `cmsl`, `cmbxsl`, `cmitt`, `cmsltt`, `cmssi`, `cmu`;
  `dc`/`ec`/`tc`/`sf` + `ti`, `sl`, `bi`, `bl`, `si`, `so`, `it`, `st`, `ui`); Libertine's
  `^Lin(Libertine|Biolinum)(Display)?[TO][BZ]?[IO]$`.
- **Math italic:** `cmmi`/`cmmib` short names, `mathmi` anywhere, or a `newtx`, `ntx`, `tx` or `zx`
  prefix with `mi` or `bmi`. Never italic.
- **Upright:** any other TeX short name or Libertine name; `roman`, `upright`, `regular` or
  `normal` in the style suffix (in the whole name when there is none), or `Rom`, `Reg` or `Rg` as a
  suffix token.
- **Unstated:** italic when the descriptor sets the Italic flag (bit 7) or `|ItalicAngle|` is at
  least 5°, unless the font is symbolic or a script face.

**Weight additions.** Libertine's `B` (bold) and `Z` (semibold), and EC's and cm-super's `bx`, `bi`,
`bl`, `sx` and `so` shapes, are bold.

**Decoding.** A show's text now comes from, in order: a simple font's ToUnicode map as #125 read it;
the same map with any codespace read as one byte (a simple font's codes are one byte, and a
two-byte entry still fails); a Type1 font's WinAnsi encoding (`NativeSpacingReader.encodingUnicodeMap`,
#110) when it has no map; an `Identity-H` Type0 font's two-byte map, whose codespace consists of
two-byte ranges, read two bytes per code.

**Lines.** `apply` marks `italicAttribute` beside `boldAttribute`. Where every show decodes and
spells the line, each character takes its show's weight and slope. Otherwise a style every show
shares marks the whole line, and a style they do not all share is left unmarked. Whitespace follows
PDFKit's run for each style as #125 defined it for bold. `read` returns shows for a page with any
bold or italic font. `inlineText` adds italic as it adds bold, with the same display-initial
exemption. It adds neither style to a **leading marker**: the line's first non-blank run, when it
holds no letter or digit and the next non-blank run lacks that style (DGA's bold `+` bullets; also
#125's bold `•` before regular items on 10 Fed pages).

**Encoding.** `EPUBTextEncoder.inline` and `note` join adjacent text elements of equal style before
writing them. Page boundaries, note references and elements of other styles stay apart.
`InlineText` itself is unchanged, so reconstruction sees the same runs.

There is no public API or default change.

### Narrowed during measurement

- **Script faces** (above): 14 Our Flag pages lost `<em>` on titles.
- **Leading markers** (above): the first DGA lane after Type0 decoding marked `<strong>+ </strong>` on
  6 pages. The same rule removed #125's `<strong>• </strong>` on Fed pages 58, 60, 61, 90, 91, 113,
  114, 117, 118 and 124.
- **Composite codespaces.** The first decoder required `<0000> <FFFF>`. The CDC comic's maps
  declare `<0001> <0022>` and left 217 lines unresolved; any two-byte ranges are now accepted.

## Lanes

`tools/case.py <case>` (with `FONT_STYLE_WORK=<scratch>`) runs `tools/run_corpus_regressions.py`
for base and cand with the probe, then `tools/compare_conversion_runs.py
--allow-different-converters`. `tools/classify.py` sorts changed pages into **merge-only** (the
baseline with adjacent same-style elements joined equals the candidate), **emphasis-only**
(equal once `<strong>` and `<em>` are removed, no other field changed) and **structural**. All
lanes passed their gates (epubcheck, content, memory) in both binaries. No images, report fields,
page markers, OCR pages or navigation changed in any case.

| Case | Changed pages | Merge-only | Emphasis-only | Structural |
| --- | --- | --- | --- | --- |
| gpo-911-2004 | 224 | 28 | 196 | 0 |
| scotus-loper-bright-2024 | 114 | 0 | 112 | 2 (86, 87: merges) |
| wallace-algebra-2010 | 108 | 9 | 96 | 3 (18, 380: paragraphs; 255: merge) |
| fed-explained-2021 | 77 | 6 | 71 | 0 |
| cdc-zombie-pandemic-2011 | 30 | 1 | 28 | 1 (12: merge) |
| gpo-our-flag-2003 | 29 | 14 | 15 | 0 |
| arxiv-replay-clocks-2023 | 12 | 0 | 12 | 0 |
| faa-phak-8083-25c | 6 | 6 | 0 | 0 |
| dga-2025-2030 | 2 | 0 | 2 | 0 |
| census-rrs2002-01, usgs-mcs2025-copper, nbs-jres-geltman-1977, cia-blue-book-14-1955 | 0 | 0 | 0 | 0 |

Not converted: NOAA, which the corpus gate records as NOT COVERED at the default image-output
ceiling (8,708 changed runs on its survey). Also Warren, whose only fonts are OCR `Courier` and
hidden text with no style (0 changed runs). Joining unstyled elements writes the same bytes.

### Review

Every changed page's newly styled spans were listed (`classify.py --emphasis`) and read. Pages
were rendered where a class was new.

- **9/11:** ship names (`Cole`, `The Sullivans`, `Limburg`), foreign terms (`jihad`, `fatwa`,
  `hawala`, `sic`), stress (`any`, `before`, `not`), book and newspaper titles in the notes (pages
  469–583), photo captions, the staff list's job titles (13–14), the hearings appendix's venues and
  dates (457–465), the italic Presidential Daily Brief (279), and the contents page's front-matter
  entries. No italic line became a heading. #97's italic-title
  rule needs a recurring italic label style over non-italic body, and none formed.
- **Supreme Court:** case names (`Chevron U. S. A. Inc. v. Natural Resources Defense Council, Inc.`),
  `Id.`, `Ibid.`, `supra`, `e.g.`, `et seq.`, `stare decisis`, `amici` (112 pages). Structural pages 86 and 87
  join an empty superscript with the next one (`<sup></sup><sup> </sup>` becomes `<sup> </sup>`), a
  merge whose empty element the classifier's join does not model.
- **Wallace:** `World View Note:` (bold, 76 pages), definitions (`Like terms`, `monomial`,
  `directly proportional`), `Table N.` labels, bold example expressions, `NOT`, and italic book
  titles (`The Elements`, `The Nine Chapters on the Mathematical Art`). No math italic variable gained
  `<em>`; the few `x` set in the text italic font (pages 38, 40) did.
  Structural pages 18 and 380: `World View Note:` now opens its own paragraph (#60's lead-in rule).
  Renders show each note set apart as its own paragraph below the text. Page 255 joins three
  subscript runs (`<sub>6a</sub><sub>2</sub><sub>b </sub>`).
- **Fed:** the chapter summaries on each opener (pages 8, 14, 24, 50, 66, 88, 116), the demibold
  italic sidebar subtitles (`Demand Shocks`, `Supervisory Ratings`), publication titles (`Annual
  Report`, `Financial Stability Report`, `Monetary Policy Report`), the Chair's quotations,
  `(continued on next page)`, and the Fed's bullets losing #125's bold.
- **Our Flag:** quotations and their attributions (`—Francis Scott Key`), the resolution's opening
  (page 4), `E Pluribus Unum`, the bibliography's titles (53–54), and the anthem (56). Page 7's
  render: the script title stays bold without italic, and the quotation is italic.
- **arXiv:** Libertine section titles (`1 INTRODUCTION`, `ABSTRACT`, `7.4 Feasibility Regions`),
  figure and algorithm captions, run-in heads (`Requirement 1.`, `Lemma`, `Definition`), italic
  emphasis (`perfect-replay`, `at most`) and the references' venues. Bold stops at math symbols
  inside a caption (`<strong>Here, </strong>𝜖<strong>=15</strong>`), as the source sets them.
- **CDC:** the comic's Corbel bold-italic lettering gains italic beside #125's bold. The text is
  garbled OCR either way (`e v e ry w h e re !`).
- **DGA:** `Dietary Guidelines` in italic in prose (pages 9–10). The bold `+` bullets stay plain.
- **FAA:** merge only: the cover's `<strong>FAA-H-8083-25C</strong>`, contents entries (page 7:
  `<strong>Aircraft Construction...3-1</strong>`) and captions split at a line break (page 373:
  `<em>…(formerly Airport/Facility Directory).</em>`).

No structural change came from italic. The two Wallace paragraph splits come from decoded mixed
bold lines, and both were checked against renders. No rule was narrowed for structure.

## Cost

`tools/cost.py` converted each book alternately with the baseline (`130fcace`) and the candidate
(`9b069788`): base, cand, three times each. It used release CLIs under `/usr/bin/time -l`, library
defaults and an unlimited output byte budget. Other agents shared the machine; figures are medians.

| Input | Baseline wall | Candidate wall | Change | Baseline peak RSS | Candidate peak RSS |
| --- | --- | --- | --- | --- | --- |
| gpo-911-2004 (585 pages) | 13.27 s | 13.15 s | −0.9% | 107 MiB | 108 MiB |
| wallace-algebra-2010 (489 pages) | 22.55 s | 21.73 s | −3.6% | 84 MiB | 84 MiB |
| fed-explained-2021 (135 pages) | 6.99 s | 7.07 s | +1.1% | 286 MiB | 287 MiB |

The changes are within run-to-run variation (Wallace's baseline ranged 20.7–29.3 s). A run before
the merge, against `0fa3057`, gave −1.4%, −2.8% and +2.2%. The added work is decoding more shows,
and scanning pages whose only styled font is italic (every Supreme Court page).

## Tests

`Tests/PDFReflowLibTests/FontWeightDetectionTests.swift` (15 new tests, 2 changed):

- **Classification:** 24 italic names and 15 upright names, including `CMSY10` and roman names
  under a leaning descriptor. Math italic (8 names) and script faces are never italic, with
  descriptor controls: the Italic flag, a −12° angle, a −1° angle, no evidence, a symbolic font.
  Libertine and cm-super weights.
- **Synthetic reproducers** (through `NativeTextReader.lines`, with PDFKit's names asserted not
  italic): named, suffix (`BkIt`) and descriptor italic read `<em>`, with controls: `CMMI12`, a
  script face, and a roman name under the Italic flag. A mixed line marks only `Cole`, also under
  PScript5's codespace; undecodable shows leave it upright. WinAnsi-encoded fonts without
  ToUnicode now mark `NEADS:`, and a font with neither map nor encoding is the negative control
  (#125's test, changed). A Type0 `Identity-H` show decodes two bytes per code; another CMap does
  not. `readerFindsNoEvidenceOnPagesWithoutABoldOrItalicFont` now also covers math italic and an
  italic positive control.
- **Map parsers:** two-byte bfchar and bfrange entries; a one-byte codespace and `usecmap` refused;
  PScript5's codespace refused by `simpleFontUnicodeMap` and read by `oneByteUnicodeMap`; a two-byte
  entry refused.
- **Line matching:** bold and italic marked independently. Undecoded shows mark only the style they
  all share.
- **Inline styling:** leading markers without letters, with controls: a lettered label, a marker in
  its item's style, and punctuation later in a line.
- **Encoding:** the FAA cover and a split caption join; controls keep other styles, a page
  boundary, a note reference and a separate superscript apart; a note's split number joins before
  it is read. `PreformattedStyleTests`' spine-budget test now alternates two styles, since equal
  adjacent runs join.
- **Source fixtures** (`*-styles-layout.json`, captured at `277cbde` with this change by
  `tools/capture-layout-fixture.swift`, which now records `"italic": true`;
  `tools/capture.sh` recaptures them). Each check has a `fontWeights: false` negative control:
  - Supreme Court 9's case names inside prose lines.
  - 9/11 171's ship names.
  - Fed 8's summary, with contents entries as controls.
  - arXiv 1's Libertine titles and italic venue, with its math italic unstyled.
  - Wallace 18's `World View Note:` opening its paragraph (fused without resource styles), and 23's
    bold labels with no italic variable.
  - DGA 3's plain bullets under bold titles.
  - Our Flag 7's script title (bold, not italic) and italic quotation.

**Mutation checks** (`swift test --filter FontWeightDetectionTests` with one part disabled). Each
part fails at least one test:

| Part disabled | Failing tests |
| --- | --- |
| italic in `inlineText` | 7 |
| math italic exclusion | 3 |
| script exclusion | 2 |
| descriptor italic | 2 |
| Type0 two-byte decoding | 1 |
| one-byte codespace fallback | 1 |
| WinAnsi encoding decoding | 1 |
| run joining | 1 |
| leading marker rule | 2 |
| Libertine names | 1 |

**Also changed:** `SourceLayoutFixture` replays `italic`; `NativeSpacingReader.encodingUnicodeMap` is
no longer private; `doc/architecture.md` and `doc/regression-testing.md` describe the rule and tests.

## Commands

```sh
swift build && swift build -c release
swift test                               # 639 tests passed (624 at 277cbde + 15)
scripts/check-all.sh --fast              # passed: 639 Swift, 217 Python, 8/8 concurrency processes
swiftc -O -parse-as-library tools/survey-font-weights.swift Sources/PDFReflowLib/FontWeightReader.swift \
  Sources/PDFReflowLib/NativeSpacingReader.swift -o <scratch>/survey
<scratch>/survey <case> [first last] > measurements/font-style-detection/survey/<case>.tsv
FONT_STYLE_WORK=<scratch> python3 measurements/font-style-detection/tools/case.py <case>
python3 measurements/font-style-detection/tools/classify.py <scratch>/review/base-<case>.epub <scratch>/review/cand-<case>.epub [--emphasis]
python3 measurements/font-style-detection/tools/cost.py <base> <cand> corpus/cache/<pdf> 3 <scratch>/cost
measurements/font-style-detection/tools/capture.sh <capture-layout-fixture binary>
```

## Limitations and defects to file

1. **Math italic has no markup.** Variables lose their slope in Wallace (Computer Modern) and in
   any PDF whose math italic is not a mathematical alphanumeric. A non-emphasis italic (`<i>` or
   `<var>`) in `TextStyle` and the encoder would carry it without `<em>`.
2. **Nested styles are not merged.** Adjacent bold and bold-italic runs write
   `<strong><em>Demand</em></strong><strong> Shocks</strong>` rather than nesting. An unstyled
   line-join space also splits elements (arXiv page 4: `<strong>=15, and the</strong> <strong>shift
   is issued…</strong>`).
3. **Census's `dc` fonts** use Differences encodings without a WinAnsi base and no ToUnicode map
   (50 unresolved lines). Their PDFKit text is also shifted by three letters (`Wklv sdshu` for
   `This paper`; survey examples).
4. **The descriptor rule is unexercised by the corpus.** No font with shows is italic by its
   descriptor alone. The 5° threshold rests on the synthetic tests.
5. **NOAA was not converted** (gate ceiling). It has 5,247 changed bold and 3,461 changed italic
   runs.
6. **Pre-existing, seen in review:** Supreme Court pages 86–87 write each `•` bullet of Justice
   Kagan's list as an empty `<sup></sup>`; expected `• Under the Medicare program, …`. Wallace page
   255 lowers `6a2b` as a subscript; expected `6a<sup>2</sup>b` in its LCD line.
