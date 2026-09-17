# Font weights PDFKit cannot name (#125)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Work started on `605d7e3` and merged, without committing, each tip the coordinator announced:
`e949bea` (#111/#112), `9803329` (#11), `e002972` (#119, 9/11 word spaces), `458a2e9` (#116, OCR
text loss), `be34d39` (#122/#123) and `a295f33` (#126/#127, 9/11 line-end `=` and code serials).
Lanes were rerun after each merge. Every lane figure below compares these binaries, built from the
`a295f33` tree with one capability probe for both. They match the `458a2e9` and `be34d39` lanes page
for page, except that one 9/11 subhead split (`NYPD Initial Response`) is now attributed to page
309 rather than an emphasis-only page:

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `a295f33` (the untracked `FontWeightReader.swift` compiled in, called by nothing) | `aaf11c9250b5d108c1baeb7b32721c538f7c6a0fbb2c914a1df56d9e4c7d0031` |
| candidate | this tree on `a295f33` | `2e0ef4d0cc405f2340a155d048c4bc21931d1c26e694a7652ec8c271ce54258e` |
| probe | `tools/probe-raster-environment.swift` | `7a2e890e771daabeac7b95bb797af12fe9b211133d2c3dfaaa3e9a7b3a16f48d` |

The survey tables were produced at `458a2e9` by the reader before its last change (lighter weight
words read in the style suffix only). That change alters no verdict among the survey's 179 font
names (see Rule), so the tables stand for the final reader.

No source PDF or EPUB is committed. Each lane's outputs were deleted after comparison and review;
`lane-summaries/` keeps both summaries and the comparison for every case run.

## Diagnosis

`NativeTextReader.inlineText` marked a run bold only when PDFKit's font name contained `bold`.
PDFKit names a run's font only when the system has a font by that name. Every embedded font in the
Fed, 9/11, Wallace, Our Flag, DGA and most of NOAA is reported as `Helvetica` with no bold symbolic
trait. Runs in two embedded fonts of one colour merge into one PDFKit run: Fed page 46's
`Table 3.1 Traditional tools…` title (FranklinGothic Demi) is one run with nothing to tell it from
the Book prose. A name rule could not work even where PDFKit keeps names: `Dm`, `Demi`, `Semibold`,
`Heavy` and `Black` contain no `bold`.

The PDF still states each weight. Fed page 46's `KGIFBZ+FranklinGothicLTPro-Dm` has
`/FontWeight 600 /StemV 148`, beside `NSVCRT+FranklinGothicLTPro-Bk` with `/FontWeight 400 /StemV 80`.
9/11's `Bembo-Semibold` and Our Flag's `StoneSerif-Semibold` set `ForceBold` in `/Flags` (262150,
262178).

## Survey (no behaviour change)

`tools/survey-font-weights.swift`, compiled with `FontWeightReader.swift` and
`NativeSpacingReader.swift`, scans every page of a book. For each font resource a text show selects
(following Form XObjects) it records BaseFont, subtype, descriptor FontWeight, StemV and Flags,
ToUnicode, and show count. It also records PDFKit's font names on the runs of lines drawn in that
resource alone, and both verdicts: the name rule on PDFKit's most frequent name, and the
weight-aware rule. Then it applies the line matching below to every PDFKit line and counts line runs
(with a letter or digit) whose bold status changes. Tables are in `survey/` (one file per book;
Warren and NOAA in page ranges). Every English corpus book is included; the Arabic and Chinese
cases are not.

| Book | Font resources | Line runs | Bold by name rule | Bold with resources | Changed runs (pages) |
| --- | --- | --- | --- | --- | --- |
| fed-explained-2021 | 25 | 4,770 | 0 | 530 | 530 (121) |
| gpo-911-2004 | 9 | 28,335 | 0 | 795 | 795 (243) |
| wallace-algebra-2010 | 35 | 38,234 | 0 | 1,449 | 1,449 (406) |
| gpo-our-flag-2003 | 5 | 1,877 | 0 | 172 | 172 (44) |
| dga-2025-2030 | 6 | 419 | 0 | 40 | 40 (9) |
| noaa-nca5-2023 | 31 | 96,273 | 609 | 5,453 | 4,844 (1,253) |
| cdc-zombie-pandemic-2011 | 22 | 925 | 267 | 762 | 495 (32) |
| census-rrs2002-01 | 13 | 1,093 | 2 | 23 | 21 (10) |
| arxiv-replay-clocks-2023 | 19 | 2,310 | 0 | 1 | 1 (1) |
| faa-phak-8083-25c | 56 | 35,589 | 3,744 | 3,750 | 6 (1, the cover) |
| cia-blue-book-14-1955 | 9 | 152,722 | 18,020 | 18,020 | 0 |
| scotus-loper-bright-2024 | 8 | 4,756 | 5 | 5 | 0 |
| nbs-jres-geltman-1977 | 7 | 3,686 | 24 | 24 | 0 |
| usgs-mcs2025-copper | 4 | 190 | 26 | 26 | 0 |
| gpo-warren-1964 | 1 (OCR `Courier`) | 417,823 | 0 | 0 | 0 |

Font resources whose weight-aware verdict is bold while PDFKit's name for them is not (`-`: no line
is drawn in that resource alone). Shows are summed over the book; FW is FontWeight.

| Book | Font (subset tag removed) | FW | StemV | Flags | Shows | PDFKit name |
| --- | --- | --- | --- | --- | --- | --- |
| Fed | FranklinGothicLTPro-Dm / -DmCm / -DmIt, ITCFranklinGothicStd-Demi | 600 | 128–148 | 4, 32, 96 | 930 | Helvetica |
| Fed | FrutigerLTStd-BoldCn, MinionPro-BoldIt, MinionPro-Semibold, BerlinSansFBDemi-Bold | 600–700 | 112–172 | 32–98 | 18 | Helvetica / - |
| 9/11 | Bembo-Bold, Bembo-Semibold, Bembo-BoldItalic | - | 95–122 | ForceBold | 812 | Helvetica / - |
| Wallace | EuropeanComputerModern-BoldExtended{7,10,12,17}pt | - | 133–174 | 32–131104 | 1,503 | Helvetica / - |
| Wallace | CMBX12, CMBX8, CMMIB10, CMMIB7, CMBSY10, CMBSY7 (TeX names) | - | 121–169 | 4–65568 | 1,371 | Helvetica / - |
| Our Flag | StoneSerif-Semibold, SnellRoundhand-BoldScript | - | 80–133 | ForceBold | 209 | Helvetica |
| DGA | RobotoCondensed-Bold (TrueType, Type0) | 700 | 140 | 4, 32 | 127 | Helvetica |
| NOAA | Lora-Bold, Roboto-Bold, Roboto-BoldItalic, Calibri-Bold, TimesNewRomanPS-BoldMT | 700 | 124–144 | 4–96 | 13,937 | Helvetica / - |
| CDC | LucidaSansUnicode, Corbel-BoldItalic, SegoeUI-BoldItalic (Type0) | 700 | 0 | 32–131168 | 618 | Helvetica / - |
| CDC | MicrosoftSansSerif (Type0) | 700 | 0 | 32 | 16 | MicrosoftSansSerif |
| Census | dcbx100120, cmmib10084 (TeX names) | - | 0 | 4, 68 | 41 | Helvetica / - |
| FAA | *Times New Roman-Bold-256-Identity-H (Type0) | - | 100 | ForceBold | 9 | Helvetica |
| arXiv | Inconsolatazi4-Bold | - | 112 | 4 | 1 | - |

No font anywhere is named bold by PDFKit and regular by its resources: the FAA's, CIA's, NBS's,
USGS's and Supreme Court's bold faces keep system names (`Helvetica-Bold`, `Times-Bold`,
`Arial-BoldMT`) and both rules agree. NOAA's `ProximaNova-Bold` and CDC's `Trebuchet-BoldItalic`
keep their names too.

Evidence not used:

- **StemV** separates weights within one family (Fed Book 80 against Demi 148) but not across
  families. Wallace's regular `CMSY10` (141) and `CMEX10` (153) are heavier than its bold `CMBX12`
  (121), and NOAA's `Roboto-Medium` (120, FontWeight 500) is not bold.
- **FontWeight 500** (`Roboto-Medium`, `FranklinGothicLTPro-Md`, `ProximaNova-Medium`) stays regular.
- **arXiv's `LinLibertineTB` and `LinBiolinumTB`** (Libertine's bold, 240 shows, section titles)
  state their weight in neither a word nor a descriptor (`TB` is a Libertine naming scheme, StemV
  130 against 79). They remain undetected.

## Rule

`FontWeightReader` (new, `Sources/PDFReflowLib/FontWeightReader.swift`).

**Font resource weight.** The name is read without its subset tag and a composite `-Identity-H/V`
suffix:

- **Bold names:** a name containing `bold` (not `light`) is bold. So is one containing `demi`,
  `heavy` or `black`, or whose style suffix (after the last `-` or `,`, split at case changes) holds
  `Dm`, `Bd`, `Db`, `SmBd`, `SemiBd`, `Sb`, `Sbd`, `Hv`, `Hvy`, `Blk`, `XBd`, `ExtBd`, `XBold`, `Ub`
  or `Ubd`, unless the name also states a lighter weight. So is a TeX Computer Modern shape code:
  `(cm|dc|ec|tc)(ss)?(bx|b|mib|bsy)(sl|ti|sc)?<digits>`.
- **Lighter names:** `light`, `book`, `medium`, `regular`, `thin` or `hairline` in the style suffix
  (in the whole name when it has no suffix), or `Lt`, `Bk`, `Md`, `Med`, `Reg`, `Rg`, `Th`, `Roman`,
  `Rom` or `Normal` as a suffix token, is never bold, even under `FontWeight 700` or `ForceBold` (a
  conflict, read conservatively). A family name is not read for lighter words, so `Bookman-Demi` is
  bold. Of the survey's 179 distinct names, only `CenturySchoolbook-Bold`/`-Italic` carry such a word
  in the family, and neither verdict changes.
- **Contradicted bold names:** a bold name other than `Bold` (or a TeX code) under a descriptor
  `FontWeight` below 500 is regular (a conflict). `Bold` names stay bold, as PDFKit's own rule
  already reads them.
- **Names stating no weight:** bold when the descriptor's `FontWeight` is at least 600 or `Flags`
  has ForceBold (bit 19). A Type3 font with no descriptor or name has no weight.

**Line matching** (`apply`). A PDFKit line is marked only where the page's text shows explain it:

1. **Its shows.** A show belongs to a line when its origin lies in the line's bounds (±0.75 pt). A
   show inside several lines' bounds belongs to the one clearly tighter than the others (each other
   line at least a third taller). Fed page 66's first title line is as tall as its 70-point numeral
   and reaches over the second line's baseline. Lines of like height overlapping stay ambiguous and
   are left alone, and a line that needed this choice must be confirmed by decoded text (step 3).
2. **Its start.** At least one show is bold, and the leftmost starts within half an em (at least 2 pt)
   of the line's left edge, so no show begun on another line draws its first glyphs.
3. **Its weights.** Where every show decodes through its font's one-byte ToUnicode map
   (`NativeSpacingReader.simpleFontUnicodeMap`), the decoded letters (whitespace and soft hyphens
   removed, NFKC) must spell the line's letters exactly. Each character then takes its show's weight.
   Otherwise every show must be bold, and the whole line is marked.
4. **Whitespace** follows PDFKit's run. A space in a run whose other characters are all bold is bold
   (`Figure 2-8. `); one in a wholly regular run, or in a run of spaces alone, is not. In a run PDFKit
   merged across fonts, a space takes the weight of the character before it.

Anything else leaves the line as PDFKit read it. The mark is a private attribute
(`FontWeightReader.boldAttribute`) set on the attributed string after `NativeSpacingReader`'s
repair, in full-line extraction and in `piece` (column-joint and borderless-table splits).
`inlineText` adds bold for it except on a display run of at most one letter: a drop cap or numeral
at least twice the size of its neighbours. Our Flag sets its drop caps in `SnellRoundhand-BoldScript`,
and `<strong>T </strong>he` is ornament, not emphasis. PDFKit's own `bold` name rule is unchanged.
`read` returns no shows for a page without a bold font, so such pages skip matching. There is no
public API or default change.

### Narrowed during measurement

- **Whitespace.** The first rule marked letters only, which split FAA's already-bold `Figure 2-8. `
  runs into `<strong>Figure 2-8.</strong><strong> </strong>` (91 FAA pages changed markup). Giving
  whitespace the preceding character's weight moved spaces into bold after bold labels whose space
  PDFKit sets regular (312 pages). Following PDFKit's run, but inheriting in space-only runs, gave
  `<strong> </strong>` between bold figure numbers and italic captions (133 pages). The final rule
  leaves FAA with only its cover (page 1) changed.
- **Tall lines.** Before the tie-break, Fed chapter openers were marked only on their second title
  line (`5 Supervising … and <strong>Activities</strong>`).
- **Drop caps** (above).

## Lanes

`measurements/font-weight-detection/tools/case.py <case>` runs `tools/run_corpus_regressions.py`
for base and cand with the probe, then `tools/compare_conversion_runs.py
--allow-different-converters`, keeping both EPUBs for review. `tools/classify.py` sorts changed
pages into emphasis-only (markup equal once `<strong>` tags are removed, no other field changed) and
structural. `tools/categorize.py` sorts structural hunks by kind. All lanes passed their gates
(epubcheck, content, memory) in both binaries. No images, report fields or page markers changed in
any case.

| Case | Changed pages | Emphasis-only | Structural | Navigation |
| --- | --- | --- | --- | --- |
| fed-explained-2021 | 121 | 121 | 0 | unchanged |
| gpo-911-2004 | 244 | 74 | 170 | changed (headings) |
| wallace-algebra-2010 | 402 | 402 | 0 | unchanged |
| faa-phak-8083-25c | 1 | 1 | 0 | unchanged |
| gpo-our-flag-2003 | 43 | 43 | 0 | unchanged |
| dga-2025-2030 | 8 | 8 | 0 | unchanged |
| usgs-mcs2025-copper | 0 | 0 | 0 | unchanged (passed) |
| census-rrs2002-01 | 0 | 0 | 0 | unchanged (its bold pages are OCR pages) |
| cdc-zombie-pandemic-2011 | 32 | 32 | 0 | unchanged |
| arxiv-replay-clocks-2023 | 1 | 1 | 0 | unchanged |

NOAA was surveyed but not converted: the corpus gate records it NOT COVERED (default image-output
ceiling). Its 4,844 changed runs are the largest unmeasured effect.

### Emphasis-only review

- **Fed:** part and section titles inside their existing heading elements; figure and table titles
  in captions; table header cells and row labels (`Interest on reserve balances (IORB)`); sidebar
  titles (#100's `A fresh look at the monetary policy framework`); the bold lead phrases of bullets
  (`• conducts the nation's monetary policy`); run-in labels (`Federal Advisory Council (FAC).`).
  Chapter openers: `5 <strong>Supervising and Regulating</strong>`. No heading, paragraph or table
  boundary changed. The Fed's run-in labels close with a period, not #60's colon, so they stay
  emphasis.
- **Wallace:** `Example N.` (522 runs), exercise instructions (`Solve each equation.`), chapter and
  section titles, `Objective:` lines, `Warning N.`.
- **Our Flag:** Semibold section titles and the SnellRoundhand-BoldScript epigraphs. Drop caps carry
  no emphasis; their baseline split (`T he`) is unchanged.
- **DGA:** section titles (`Prioritize Protein Foods at Every Meal`) and the signatures on page 2.
- **FAA:** the cover's `FAA-H-8083-25C`, emitted per PDFKit run (`<strong>F</strong><strong>AA</strong>…`).
- **CDC:** comic lettering, already `<em>`, is bold-italic capitals in the source (page 5 render). The
  text layer is garbled OCR either way.
- **arXiv:** `epoch` in a listing (`Inconsolatazi4-Bold`).

### 9/11 structural review

All 170 structural pages were categorised hunk by hunk. No hunk removed a heading, merged blocks
or changed text.

- **180 hunks on 165 pages: a subhead now stands apart from its paragraph.** Bembo-Semibold
  subheads were the opening words of the paragraph beneath (`Boarding the Flights Boston: American
  11…`). With bold evidence, #76's label rule reads them as a recurring label style and emits `h6`.
  Every one of the 180 titles was read: `The Hijacking of American 11`, `Bin Ladin's Worldview`,
  `FDNY Initial Response`, `The Protection of Civil Liberties`, and the hearings appendix's panel
  titles (pages 457–465). Renders of pages 19 and 458 were checked: each is a bold subhead on its
  own line above its text.
- **2 hunks: a standalone question retagged as a heading** (`What If?` on page 62, `A Follow-On
  Campaign?` on 137, each already its own paragraph).
- **5 hunks on pages 41, 44, 48 and 49: transcript turns split.** Each speaker's turn (`NEADS:`,
  `FAA:`, `Boston Center:`) begins its own source line with a bold label closing in a colon, and #60's
  lead-in rule now opens a paragraph there: `NEADS: He—American 11 is a hijack?` / `FAA: Yes.` rather
  than one paragraph per exchange. Run-in heads closing with a period (`FAA Mission and Structure.`,
  `Military Notification and Response.`) remain emphasis.

No rule over-fired: no Fed table label, box line or caption became a heading, and no Wallace or
DGA structure changed. So no heading, label or lead-in rule was narrowed.

## Cost

The reader adds a second content-stream scan per styled page. `apply` also compares each matched
show's origin with every line's bounds, which is quadratic in a page's lines. Pages without a bold
font skip `apply` entirely (`read` returns no shows).

`tools/cost.py` converted each book with the baseline (`aaf11c92`, `a295f33`) and the candidate
(`2e0ef4d0`) alternately: base, cand, base, cand. Each run used release CLIs under `/usr/bin/time -l`
on the same machine, with library defaults except an unlimited output byte budget (so the NOAA
excerpt is not stopped by the default ceiling). Six agents shared the machine, so single runs vary
by up to about 10%. Figures are medians; each EPUB was deleted after its run.

| Input | Runs each | Baseline wall | Candidate wall | Change | Baseline peak RSS | Candidate peak RSS |
| --- | --- | --- | --- | --- | --- | --- |
| gpo-911-2004 (585 pages) | 3 | 10.64 s | 10.99 s | +3.3% | 97 MiB | 98 MiB |
| wallace-algebra-2010 (489 pages) | 3 | 20.53 s | 21.08 s | +2.7% | 79 MiB | 82 MiB |
| fed-explained-2021 (135 pages) | 3 | 6.80 s | 7.06 s | +3.9% | 285 MiB | 247 MiB |
| noaa-nca5-2023 pages 1700–1799 (qpdf excerpt: the 100-page range with most pages of changed runs, 84) | 2 | 6.97 s | 7.05 s | +1.2% | 533 MiB | 531 MiB |
| cdc-zombie-pandemic-2011 (42 pages, Type0 bold fonts) | 3 | 7.14 s | 7.01 s | −1.9% | 375 MiB | 372 MiB |

No book slows by more than 4%, and peak memory is unchanged within run-to-run variation (the Fed's
peak RSS varied 223–295 MiB across runs of both binaries). No hot spot was changed.

## Tests

`Tests/PDFReflowLibTests/FontWeightDetectionTests.swift` (15 tests):

- **Classification:** 23 bold names (Dm, Demi, Semibold, SmBd, Hv, Blk, Black, ExtraBold, `Bookman-Demi`, TeX
  `CMBX12`/`CMMIB10`/`dcbx`…) and 20 regular names (Bk, Md, Medium, Lt, SemiLight, DemiLight, `Bookman-Light`, `cmb`,
  `bbm10`…). Descriptor rules with controls: FontWeight 500, the SmallCap flag, no evidence, and
  conflicts (Medium under 700 with ForceBold; Dm under 400; Bold under 400).
- **Reproducers.** Synthetic PDFs through `NativeTextReader.lines`:
  - A `-Dm`/`-Demi` font PDFKit names without `bold` reads bold (asserted on PDFKit's names), with a
    `-Bk` control.
  - A `FontWeight 700` descriptor under a name without a weight reads bold, with controls: 400, the
    `-Medium` conflict, and `Helvetica-Bold` as the positive name-rule control.
  - A mixed line (`NEADS:` Semibold, then regular) marks only the label; the control without
    ToUnicode leaves it unmarked, and a wholly bold undecoded line is still marked.
  - A page without a bold font returns no shows.
- **Line matching** on constructed shows:
  - Fed 66's tall-line tie-break, with an equal-height control and an undecoded control.
  - The left-edge rule and spelling mismatch.
  - The four whitespace cases.
- **Source fixtures** (`*-weights-layout.json`, captured at `458a2e9` by
  `tools/capture-layout-fixture.swift`, which now records `"bold": true` on runs the reader marks;
  `measurements/font-weight-detection/tools/capture.sh` recaptures them). Each check has a
  `styledContent(fontWeights: false)` negative control replaying PDFKit's runs alone:
  - Fed 46's table title, header row and labels bold, and Book cells not.
  - Fed 66's opener.
  - 9/11 19's subhead as a heading, fused without weights.
  - 9/11 62's `What If?`.
  - 9/11 44's transcript turns, fused without weights, with the period run-in head unsplit.
  - Wallace 7, DGA 3 and Our Flag 7's titles, and Our Flag's unemphasised drop cap.

Fixture replay matches attributed lines to layout lines by text, so a line that #119's word-space
repair respelled (`FAA: Yes. This could be…`) replays unstyled. The pipeline applies weights after
the repair; the 9/11 lane shows that turn split.

**Mutation checks.** Disabling the style in `inlineText` fails 9 of the 15 (the 6 that pass test
classification and the reader directly). Disabling the drop-cap exemption fails the Our Flag check.
Disabling the tall-line tie-break fails `showInSeveralLinesBelongsToTheClearlyTighterLine`.

**Also changed:** `tools/check_pdfkit_concurrency.py` and the two capture commands in
`doc/regression-testing.md` compile `FontWeightReader.swift`; `doc/architecture.md` describes the rule.

## Commands

```sh
swift build && swift build -c release
swift test                               # 605 tests passed (590 at a295f33 + 15)
scripts/check-all.sh --fast              # passed: 605 Swift, 214 Python, 8/8 concurrency processes
swiftc -O -parse-as-library tools/survey-font-weights.swift Sources/PDFReflowLib/FontWeightReader.swift \
  Sources/PDFReflowLib/NativeSpacingReader.swift -o <scratch>/survey
<scratch>/survey <case> [first last] > measurements/font-weight-detection/survey/<case>.tsv
FONT_WEIGHT_WORK=<scratch> python3 measurements/font-weight-detection/tools/case.py <case>
python3 measurements/font-weight-detection/tools/classify.py <scratch>/review/base-<case>.epub <scratch>/review/cand-<case>.epub
python3 measurements/font-weight-detection/tools/categorize.py <base.epub> <cand.epub> [--list heading-split]
```

## Limitations and defects to file

Items 1, 2, 3 and 7 are addressed by #133 ([the font style evidence](../font-style-detection/record.md)).

1. **Undeclared bold faces.** arXiv's `LinLibertineTB`/`LinBiolinumTB` (section titles, 240 shows)
   state bold in neither a weight word nor a descriptor. Only a family-relative StemV comparison
   could see them, and StemV is not comparable across families.
2. **Italic has the same gap.** PDFKit's `Helvetica` renaming hides `Italic` and `It` faces (Fed
   `FranklinGothicLTPro-BkIt`, 9/11 `Bembo-Italic` with 725 shows, NOAA `Lora-Italic`), and
   `ItalicAngle` is in the same descriptors. This change reads weight only.
3. **Mixed-weight lines without one-byte ToUnicode maps stay unmarked:** composite (Type0) fonts,
   Wallace's WinAnsi-only CM fonts. A bold word inside such a line gains no emphasis; wholly bold
   lines are unaffected.
4. **Two-line hanging-indent bold titles are not headings.** 9/11 page 458's `Law Enforcement,
   Domestic Intelligence, and` / `Homeland Security` (second line indented) stays fused into its
   witness-list paragraph, now visibly bold. The witness names in each panel also run together as
   one paragraph.
5. **Drop caps separate from their word in the pipeline** (Our Flag pages 5–27: `T he`, `D uring`),
   though `DropCapTests` rejoins them from fixtures. Pre-existing; unchanged here.
6. **NOAA was not converted** (gate ceiling); its 4,844 changed runs on 1,253 pages need a lane run
   with the larger storage caps of `measurements/noaa-output-policies`.
7. **Adjacent same-style runs are emitted as separate `<strong>`/`<em>` elements**
   (`<strong>F</strong><strong>AA</strong>` on the FAA cover, CDC lettering). Pre-existing encoder
   behaviour, now visible in more places.
