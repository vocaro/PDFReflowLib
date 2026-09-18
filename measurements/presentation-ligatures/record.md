# Presentation-form ligatures spelled out (#189)

Tier: deterministic Apple PDF/OCR stack, library defaults, macOS 27.0 (26A428) arm64, Xcode 27.0
(27A266a), release CLIs under other agents' load. Baseline: `ee96a72`, built from a detached
worktree (`pdf-reflow` SHA-256 `eba457a7…`). Candidate: `ee96a72` plus this change (`791c4963…`),
copied out of the build directory before the lane. Both installed as `pdf-reflow`, so they share one
compiled Vision model cache (`sameVisionPrograms: true` on every comparison). One capability probe
(`tools/probe-raster-environment.swift` built from `ee96a72`, `0f9fd80d…`) ran before every
conversion. Corpus sources are the checksum-pinned cached PDFs.

## Cause

The issue's last comment has the root cause: the extracted words are whole, but the EPUB holds
the ligature as one presentation-form character (`Diﬀerent`, U+FB00), and Charter, Times New Roman,
Avenir Next and the system font have no glyph for U+FB00, U+FB03 or U+FB04, so the reader draws it
from a fallback font whose metrics look like a gap (`measurements/math-operator-spaces/record.md`,
#189 section). Two sources produce these characters. PDFKit reports Wallace's EC-font `ff` and `ffi`
as U+FB00 and U+FB03. The #143 decoder (`GlyphIndexDecoder`, Cork indices 27–31) establishes
U+FB00–U+FB04 for Census's index-named fonts.

## Where the fix lives: at the end of extraction

`InlineText.spellingOutLigatures` writes U+FB00–U+FB06 as `ff fi fl ffi ffl ſt st`. These are the
characters' one-step compatibility decompositions: U+FB05 keeps its long s, which full NFKD would
fold to `s`. `TextLine.spellOutLigatures` applies it to a line's runs and keeps styles, note
references, page boundaries and geometry. It is called in three places:

1. `NativeTextReader.lines`, as its last step, after overprint removal and every split.
2. `OCRReader.read`, on each recognized line.
3. The pipeline, on the PDF's own metadata title. A caller's `options.title` is left as given.

**Why not earlier.** Every step inside `NativeTextReader.lines` matches line text to the page's
characters and shows, where a ligature is one character. `NativeSpacingReader` maps the glyph
names `ff`, `fi`, `fl`, `ffi` and `ffl` to U+FB00–U+FB04, and `FontWeightReader` repairs index
glyphs through the #143 decoder, which yields the same characters. The new control in
`censusWordGapsAreReadFromCompensatedCharacterSpacing` shows what spelling out too early would do.
Census page 17's repaired line `…ofOﬃcialStatistics,…` gains its word gaps from the spacing
evidence. The same line spelled out before spacing (`ofOfficialStatistics`) no longer matches the
shows and stays run together. Unit tests that pin ligatures (`repairedCensusLines`, the
operator-spacing `eight.lines`, the decoder tables) test these inner stages and stay unchanged.

**Why not at the writer.** Every rule after extraction would then still see two spellings of one
word. #123 had to record every ligature word in the vocabulary twice, as printed and spelled out, so
that Wallace's `dif-` + `ferent` found `diﬀerent`. With letters from extraction on, that double
recording is unnecessary, so `LayoutReconstructor.isLigature`/`ligaturesSpelledOut` and the second
`vocabulary.insert` are removed. Hyphen evidence now reads letters on both sides of a break,
whether the break fell inside a ligature (`oﬃ-` + `cial` is now `offi-` + `cial`) or beside it. Search,
text-to-speech and every later rule see the same letters as the reader.

**Rules checked for a dependence on the ligature character.** Checked:

- hyphen evidence and the vocabulary (above);
- `holdsNumericGrid`, which counts words and is unchanged by spelling;
- `TextLayerPlausibility` and `TextEncodingCheck`, which judge PDFKit's own text
  (`glyphReport.nativeText`) where lines were repaired, and otherwise English letter statistics;
- `MarkedTextReader`, which matches by geometry;
- `AnnotationEvidence.markBoxes`, which rewrites only checkbox glyphs;
- the character budget, where `ffi` is three characters for one.

The lane below is the evidence that none of them changed an outcome: every page differs from the
baseline in its ligatures alone.

**Fixtures.** Source-layout fixtures captured before this change record PDFKit's ligature
characters. `SourceLayoutFixture.content()` and `styledContent()` now replay extraction's final
step, and match attributed runs spelled out too. `spelledOut: false` replays the lines as captured,
which the Wallace test uses as its negative control.

## Survey: every English corpus document

The lane is `tools/lane.sh` (one `run_corpus_regressions.py` call per case, EPUBCheck, probe). The
comparisons are `tools/compare.sh`: `compare_conversion_runs.py --allow-different-converters
--detail`, then `tools/textdiff.py`, which reads each page's text with `read_pages` and spells out
the baseline's ligatures, then `tools/bodies.py`, which concatenates the spine bodies with file names
dropped from links, and `tools/count.py`, which counts U+FB00–U+FB06 in every text entry. Full output
is in `comparisons.txt`.

| Document | PDFKit text | EPUB before | EPUB after | Pages changed | Beyond ligatures |
| --- | ---: | ---: | ---: | ---: | --- |
| wallace-algebra-2010 | 224 | 182 (ﬀ 139, ﬃ 43) | 0 | 107 | none |
| census-rrs2002-01 | 0 (decoded, #143) | 28 (ﬀ 1, ﬁ 18, ﬂ 5, ﬃ 4) | 0 | 2 (3, 17) | none |
| noaa-nca5-2023 | 1 | 1 (ﬀ, page 282 `oﬀshore`) | 0 | 1 (282) | none |
| 16 other contracted English documents | 0 | 0 | 0 | 0 | none |
| gpo-warren-1964 | 0 | not converted | — | — | — |

The 16 are FAA, 9/11, Fed, DGA, Our Flag, CDC, Blue Book, USGS, Loper Bright, NBS, Replay Clocks,
the court form and the four NTRS reports. Warren has no full-conversion contract (default image
ceiling, #5). Its PDFKit text holds no ligature (`tools/probe.swift`), no font of its is decoded, and
recognized text is spelled out too, so its output cannot gain one. The PDFKit column counts
`PDFPage.string` over every page. Wallace's EPUB holds fewer ligatures than its PDFKit text because
text inside formula crops and removed furniture is not reflowed.

On all 19 converted documents:

- Every candidate passes its contract with EPUBCheck.
- Page markers, images, navigation and the conversion report are unchanged.
- No OCR page changed.
- Each changed page's text equals the baseline's with ligatures spelled out.
- The concatenated spine bodies are equal once the baseline is spelled out.
- Outside the spine, only `package.opf` differs, in the package identifier and modification time
  that every run regenerates.

Wallace's changed pages cover 11 spine files, whose boundaries move by one block in places. For
example, the `3. When 18 is subtracted…` exercise moves from the head of `chapter-3.xhtml` to the end
of `chapter-2.xhtml`. Spine packing measures UTF-8 bytes against its 60,000-byte target, and `ﬀ` is
3 bytes where `ff` is 2, so a file holds a little more text. The concatenated bodies are identical
and the comparator reports no navigation change.

## Contracts and the output check

`corpus/regressions.json` pinned 16 ligature characters: Wallace pages 7, 8, 38 and 318, and Census
pages 3 and 17. `tools/respell.py` respelled them to letters. This includes the two `absentText`
entries `Diﬀ erent`, which now forbid `Diff erent`, and Census's `JournalofOﬃcialStatistics`. No
page gained a second entry. `tools/check_corpus_content.py` now fails any contracted EPUB with
U+FB00–U+FB06 on any page. `test_manifest_contracts_have_pinned_sources_and_useful_checks` forbids
them in any contract string, and `test_presentation_form_ligatures_fail_on_any_page` checks all
seven characters, with the spelled-out word, the neighbouring code points (U+FAFF, U+FB07, U+FB13)
and other compatibility forms as passing controls.

**Negative controls on real output.** The baseline evaluations fail the new contracts:

- Wallace: `Presentation-form ligature … on 107 pages, first [2, 3, 7, 8, 18]`, plus the four
  respelled phrases missing.
- Census: the seven respelled phrases missing.
- NOAA: `… on 1 pages, first [282]`. The pre-change NOAA contract has no phrase on that page, so the
  output check alone catches it.

The candidate passes all three.

## Tests

- `extractionSpellsLigaturesOut` checks the mapping, the scalar walk for a ligature carrying a
  combining mark, the untouched compatibility forms, NFKD equivalence for all seven characters, run
  styles, note references and page boundaries, a line's geometry and trailing space, and a line
  without a ligature left as it is. It also checks hyphen joins on the spelled-out vocabulary, with a
  word the book never prints as the warning control.
- `sourceDifferentJoinsOnTheBooksLigatureSpelling` checks that Wallace pages 50 and 218 hold no
  ligature and join `different`. Controls: the lines as captured record only `diﬀerent`, keep
  `dif-ferent` and warn, and so does the spelled-out page without the word.
- `censusReferencePageReadsEachEntryAsOneParagraph` runs the rebuilt Census page 17 through the
  pipeline and finds no ligature in its blocks. It fails with the extraction step commented out
  (mutation run: `Journal of Official Statistics` missing, a ligature present).
- `censusWordGapsAreReadFromCompensatedCharacterSpacing` is the ordering control described above.
- Four output pins were respelled: Wallace 2 `affected`, 318 `different`, the radicals page
  `coefficients`, and Census 17 `Official`.

`swift test`: 910 tests pass. `tools/test_corpus_content.py`: 41 pass.

## Shared functions touched

- `TextLine`: new `spellOutLigatures`.
- `InlineText`: new `isLigature`, `spellingOutLigatures`.
- `NativeTextReader.lines`: its last step.
- `OCRReader.read`: its line construction.
- `PDFReflowLibPipeline.reconstruct`: the title line.
- `LayoutReconstructor.addVocabulary`: the #123 double insertion removed, with `isLigature` and
  `ligaturesSpelledOut`.
- `check_corpus_content.assess`: a new whole-document check.
- `SourceLayoutFixture`: `content`/`styledContent` spell out by default.

## Limits

- Only U+FB00–U+FB06 are spelled out. Other compatibility forms (superscripts, fractions,
  full-width, `ĳ`, the Armenian ligatures U+FB13–U+FB17) are unchanged.
- A caller-supplied title or author is written as given.
- Apple Books was not re-tested on a device. The fix removes the character the fallback came from
  rather than measuring the reader.
