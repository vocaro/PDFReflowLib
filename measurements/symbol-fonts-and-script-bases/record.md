# Symbol-font characters and shifted script bases (#155, #144)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Work started on `d62224a` and was rebased on `1a18b7a` (the DASC paper of #163, #93's OCR policy,
#141) and then on `b1c7043` (#151's annotation references and checkbox glyphs, the Earthdata slides
and the Tank Health Monitoring report) before the lanes recorded here. Both binaries are built from
`b1c7043`: the baseline from `git archive b1c7043`, the candidate from the same tree with this change
applied. The same lanes on `1a18b7a` gave the same changed pages and script counts.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `git archive b1c7043` | `5186a7aeaaf3ab8df626c8673e377447603168f8eed2a2a36516870e99471464` |
| candidate | `b1c7043` with this change | `e576aef39bf5f5e76f21a3cddad638cd678e55cc7fda7163f501f2d89770fecc` |
| probe | `tools/probe-raster-environment.swift` | `cbf9fabb801c2acd89433d713236eacac103824f3749e254b0b1ef15c4bc72e3` |

No source PDF or EPUB is committed; every lane's EPUBs were deleted after its comparison and page
review. Three source fixtures were captured (`algebra-255`, `scotus-86`, `ntrs-13`).

## Evidence: where the private-use characters come from (#155)

| Source | Font | Evidence | PDFKit reports |
| --- | --- | --- | --- |
| NASA GWL page 4, 13 | `SymbolMT`, Type0 `Identity-H`, CIDFontType2, embedded, descriptor `Flags 32` (**Nonsymbolic**) | ToUnicode `<0044> <F061>`, `<0078> <F0B7>` | U+F061 (α) ×2, U+F0B7 (•) ×5 |
| Supreme Court page 86–87 | `BDGFGH+SymbolMT`, Type0 `Identity-H`, embedded, `Flags 4`, `FontFamily (Symbol)` | ToUnicode `<0078> <F0B7>` | U+F0B7 ×5 |
| Wallace page 312 | `RRTZXD+CMEX10`, Type1, `Flags 4` | `Differences [48 /parenlefttp /parenrighttp 64 /parenleftbt /parenrightbt]` and ToUnicode to `F8EB`, `F8F6`, `F8ED`, `F8F8` | U+F8EB, U+F8ED, U+F8F6, U+F8F8 ×2 each |
| DASC page 3, 9 (#163) | `EYRYPR+CMEX10`, `OECAAE+CMEX9`, Type1 built-in encoding, no ToUnicode | the embedded program's `/Encoding` (`dup 62 /braceex put`) and the descriptor's `CharSet` | 207 characters, U+F8EB–U+F8FE |

Word's map is the font's Microsoft symbol `cmap`, which places the built-in code `xx` at U+F0xx; the
embedded `SymbolMT` programs have no `post` names (CoreGraphics reports `gid68`, `gid120`), so the
name `Symbol` and the built-in Symbol encoding are the only evidence for those code points. The
descriptor flag is not evidence either way: Word writes `Nonsymbolic` for the NASA paper's SymbolMT
and `Symbolic` for the Supreme Court's. Adobe's glyph list assigns the Symbol font's pieces to
U+F8E6–U+F8FE and U+F6D9–U+F6DB; a built-in-encoded `Symbol` Type 1 font makes PDFKit report
`bracerighttp` as U+F8FC (probed with a synthetic page).

## Rule (#155)

`PrivateUseDecoder` reads the page's font resources (Form XObjects followed, 256 fonts and depth 4 at
most) the first time one of the page's lines holds a private-use character. Per font:

- with a ToUnicode map, each code it maps to a single private-use scalar is decoded from the glyph
  name its `Differences` gives that code (`parenlefttp` → ⎛ U+239B, `uni23A3` → ⎣), else, for a Symbol
  font, through the Symbol encoding (U+F0xx = built-in code xx) and Adobe's piece table, and for a
  Wingdings font through the eight bullets Word's gallery inserts (`§` ▪, `Ø` ➢, `ü` ✔, …);
- without one, through the piece names the font states — its `Differences`, the built-in encoding of
  its embedded Type 1 program's clear text, its descriptor's `CharSet` — and, for a Symbol font, every
  Adobe piece.

A font is Symbol or Wingdings when its `BaseFont`, descriptor `FontName` or descriptor `FontFamily`
names it (subset tags and style suffixes aside). A code point a font yields without evidence, or that
two fonts on the page decode differently, is left as PDFKit reported it. `NativeTextReader` replaces
the characters last, after spacing and style evidence have compared PDFKit's text with the shows'
own maps (which hold the same private-use values); every replacement is one UTF-16 unit, so attribute
ranges, and therefore the runs' styles, are unchanged. Line pieces cut at column joints (#65) and
borderless-table gaps (#121) are decoded the same way.

## Rule (#144)

- **Bullets.** A run of a line's opening bullets, and the whitespace after them, is never a script,
  however it is raised: the Supreme Court's decoded bullets are 7.98-point glyphs raised 1.02 points
  beside 10.98-point text, just past the 0.12-em tolerance, with the space after each raised alike.
  The bullet set is filled marks only (`•`, `▪`, `●`, `■`, `◆`, `❖`, `❑`, `➢`, `➤`, `►`, `✔`, `✓`, `‣`,
  `⁃`): Wallace sets its degree signs as a raised `◦`, which is a superscript, so open marks are out.
- **Shifted bases.** PDFKit measures every run of a selection from one baseline. A run followed, with
  no space between, by a clearly smaller run (at most its size / 1.1) shifted to the same side of that
  baseline and away from the run, by no more than 0.75 of the run's size, is that run's base: the base
  is no script, and the smaller run is measured from the base's offset. A run of the base's size that
  follows such a script with no space, on the base's baseline, resumes the base. A base that is itself
  a clearly smaller script of the run before it (a nested index) keeps the stated offsets.

Both checks only change which runs carry `<sup>`/`<sub>`; neither changes text, spacing, weight or
slope. `hasScriptBase` (#138), the offset window and the drop-cap and display-type exclusions are
unchanged.

## Line-end hyphen after a number (#155.3)

`LayoutReconstructor.joinOperation`: a line-end hyphen whose preceding character is an ASCII digit,
before a lowercase word, joins with no space (`45-` + `degree-increment`). Before, the letters after
the hyphen alone decided (`degree` is a book word, `-degree` is not), so the hyphen was removed.

## Survey: private-use characters in every English corpus book

`measurements/symbol-fonts-and-script-bases/survey.swift` reads every PDFKit line of a book and
decodes it as the pipeline does (`survey/<case>.txt`); `output-private-use.txt` counts the characters
in the converted EPUBs of both lanes. The twenty-one English sources (Warren and NOAA, excluded from
full conversion, are in the PDFKit survey only):

| Source | PDFKit lines before | after | EPUB before | EPUB after |
| --- | ---: | ---: | ---: | ---: |
| ntrs-20190030725-dasc-2019 | 207 (pages 3, 9) | 0 | 146 | 0 |
| ntrs-20200002975-gwl-2020 | 7 (pages 4, 13) | 0 | 7 | 0 |
| scotus-loper-bright-2024 | 5 (pages 86, 87) | 0 | 5 | 0 |
| wallace-algebra-2010 | 8 (page 312) | 0 | 0 | 0 |
| faa, 9/11, Fed, DGA, Our Flag, Blue Book, CDC, NBS, arXiv, USGS, Census, Pro Se 1, USDA, Earthdata slides, Tank Health Monitoring, Warren, NOAA | 0 | 0 | 0 | 0 |

Wallace page 312's four CMEX pieces are decoded (⎛⎝⎞⎠) but never emitted: the page keeps them inside
a preserved region. The DASC EPUB holds 146 of its 207 for the same reason; #163 keeps the pieces that
do reach the text as its own defect (they belong inside the display crop).

## Tests

| Test | Reproducer / control |
| --- | --- |
| `SymbolFontCharacterTests.wordSymbolFontAlphaAndBulletReadAsTheirCharacters` | In-memory pages built from the sources' own font dictionaries and ToUnicode maps: Word's SymbolMT (`Nonsymbolic`), the Supreme Court's subset with `Symbolic` and family `Symbol`, a family-only subset name, and a Symbol font inside a Form XObject. |
| `…privateUseCharactersWithoutFontEvidenceStay` | The same map under `SyntheticSans` (flags 32 and 4) and `SymbolicSans`; a Symbol and a Wingdings font claiming one code point differently; each alone (`♣`, `▪➢`); a Wingdings pictograph outside the bullet table. |
| `…glyphNamesTheFontStatesDecodeAdobesPrivateUsePieces` | Wallace's CMEX10 `Differences` with its map; index names as a control; the DASC program's built-in encoding (clear text as in object 109) and a descriptor `CharSet`; a built-in `Symbol` font; a font naming no piece. |
| `…symbolEncodingTablesAndFamilies` | The 188-entry Symbol encoding, the piece table, family names (`Symbol,Bold`, `Wingdings2` against `SymbolicSans`, `CMSY10`, `ZapfDingbats`), and that decoding keeps attribute ranges. |
| `ShiftedScriptBaseTests.exponentsBesideAShiftedBaseAreMeasuredFromIt` | `algebra-255` fixture (`6a<sup>2</sup>b First identify LCD`), a raised numerator's exponent, the slope formula, FAA page 262's `v²`. |
| `…basesOnTheSelectionBaselineAndSeparatedRunsAreUnchanged` | `H₂O`, `8x³`, #138's Fed letter without its space, a space between the runs, a third baseline after the script, an equal-size run, opposite-side shifts, a nested index. |
| `…openingBulletsAreNeverScripts` | `scotus-86` fixture; a synthetic bullet and a lowered `▪`; controls: a raised `*` opening a line, Wallace's `29◦`, a raised bullet inside a line. |
| `…symbolBulletListsReflowAsListItems` | `ntrs-13` fixture: five decoded bullets become five list items, each with its wrapped line. |
| `LineEndCompoundTests.aNumberBeforeALowercaseWordKeepsItsCompoundHyphen` | `45-` + `degree-increment`, `3-` + `dimensional`; controls: a letter before the hyphen, a soft hyphen, an address segment. |
| `test_corpus_content.test_absent_script_rejects_the_script_with_its_tag_text_and_context` | `absentScripts` matches tag, text and optional context; plain text passes; another tag, text or context does not match; invalid expectations raise. |

Disabling each of fifteen parts (the decode step in line extraction; the Symbol family name; the
descriptor `FontFamily`; nested Form resources; the conflict rule; glyph names with a map; the
built-in encoding; `CharSet`; the Wingdings table; opening bullets; the shifted base; the resumed
base; the same-side condition; the nested-base exclusion; the digit hyphen) fails at least one test
(`mutations.txt`).

## Corpus contracts

`corpus/regressions.json` gains, and `tools/check_corpus_content.py` a new `absentScripts` expectation
(a `sup`/`sub` tag and text with optional `before`/`after` context that the page must not hold):

| Case | Page | Expectation |
| --- | --- | --- |
| ntrs-20200002975-gwl-2020 | 4 | the two `α` sentences; U+F061 absent |
| | 13 | `45-degree-increment`, the five `•` list items; `45degree` and U+F0B7 absent |
| scotus-loper-bright-2024 | 86, 87 | the five `•` items; no `<sup>` bullet; U+F0B7 absent |
| wallace-algebra-2010 | 255 | `6a<sup>2</sup>b`; no `<sub>6a2b</sub>` |
| | 96 | the slope formula's two `<sub>`; no `<sup>y</sup>`/`<sup>− y</sup>` |
| uscourts-pro-se-1-2016 | 3 | no `<sub>.</sub>` after `(foreign nation)` (#138's fix, guarded) |
| ntrs-20190030725-dasc-2019 | 3, 9 | the CMEX private-use pieces absent |

Against the baseline these fail exactly the new checks (11 on the NASA paper, 7 on the Supreme Court,
6 on Wallace, 8 on the DASC paper); the candidate passes all of them. The Pro Se 1 expectation passes
both binaries: #138 fixed it before this work, and the Python control test shows the check catching
the markup it fixed.

## Corpus lanes

`tools/case.py` (`run_corpus_regressions.py --epubcheck /opt/homebrew/bin/epubcheck
--environment-probe <probe> --execution-context host-terminal`, then `compare_conversion_runs.py
--allow-different-converters`), one case per call; `scriptdiff/<case>.txt` (the #138 lane's
`scriptdiff.py`) lists every `<sup>`/`<sub>` lost or gained per changed page, and
`tools/epub-private-use.py` reads a converted page's markup and counts its private-use characters.
33–41 GB free throughout.

| Case | Baseline | Candidate | Changed pages | What changed |
| --- | --- | --- | ---: | --- |
| ntrs-20200002975-gwl-2020 | fails the 11 new checks | pass | 4, 13 | α twice; `45-degree-increment`; the five bullets become `•` list items with their wrapped lines |
| scotus-loper-bright-2024 | fails the 7 new checks | pass | 86, 87 | five `<sup>U+F0B7 </sup>` become `•` list marks |
| ntrs-20190030725-dasc-2019 | fails the 8 new checks | pass | 3, 5, 6, 9 | 146 pieces decoded; 13 scripts lost and 13 gained around the nested indices |
| wallace-algebra-2010 | fails the 6 new checks | pass | 96, 184, 205, 255 | `6a<sup>2</sup>b`, `2b<sup>2</sup>f<sup>2</sup>`, `4x<sup>2</sup>`, `y<sub>2</sub>− y<sub>1</sub>` |
| cia-blue-book-14-1955 | pass | pass | 222 | OCR debris `1-` + `lg.` keeps its hyphen (`1- 1lg.` → `1- 1-lg.`) |
| faa-phak-8083-25c, fed-explained-2021, gpo-911-2004, uscourts-pro-se-1-2016, dga-2025-2030, gpo-our-flag-2003, cdc-zombie-pandemic-2011, nbs-jres-geltman-1977, arxiv-replay-clocks-2023, usgs-mcs2025-copper, census-rrs2002-01, usda-ars-agresearch-2012-11, ntrs-20180003024-earthdata-slides-2018, ntrs-20210020887-techport-thm-2021 | pass | pass | 0 | — |

No page changed images, navigation, page markers or the conversion report in any lane. The changed
pages of Wallace (96, 184, 205, 255), the NASA paper (4, 13) and the Supreme Court (86, 87) were read
in both EPUBs against 100–200 DPI renders of the source pages.

DASC pages 5 and 6 are a mixed result inside #163's nested indices: the candidate loses two wrong
`<sub>`s (`A<sub>n</sub>`) and gains `j<sub>k</sub>` twice (right) and `j<sub>N</sub>` once (wrong:
`N` is a superscript of `n`). The nested-base exclusion keeps the rule out of the deeper stacks.

## Verification

- `swift test`: 748 pass, including the new `SymbolFontCharacterTests` (4), `ShiftedScriptBaseTests`
  (4) and the new compound-hyphen test.
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 233 pass (1 new).
- `scripts/check-all.sh --fast`: exit 0, including the generated doc counts (`tools/update_doc_counts.py`).
- Corpus lanes above, and `tools/check_corpus_content.py --case <id> --evaluation <lane>` against both
  binaries for the five cases with new expectations.

## Not fixed here

- **#154/#146 (list items).** Where a decoded bullet's item wraps onto a line that starts a new
  sentence, reconstruction writes the item's first line as `<pre>` and the rest as `<p>`: Supreme Court
  page 86's first item and page 87's last two (the items whose first line ends in a hyphen join). The
  bullets themselves are now list marks; the split is the `<pre>`/list defect the DASC review already
  records ("bullets are `<pre>` holding only their first line").
- **#163.** The CMEX pieces are decoded but still reach the text as `⎪⎪⎪` paragraphs on DASC pages 3
  and 9; they belong inside the display crop. Nested index stacks (`STA` with `n` raised and `i`
  raised again) still shatter into one-token paragraphs.
- Fonts whose private-use characters PDFKit derives from an embedded `cmap` without a ToUnicode map
  and without glyph names (no corpus instance: a non-embedded TrueType Symbol font without a map
  extracts as WinAnsi letters, and a non-embedded `CMEX10` extracts as nothing).
- Embedded TrueType `post` glyph names are not read: both corpus SymbolMT programs have none.
