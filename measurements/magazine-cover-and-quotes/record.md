# Magazine leftovers after #186: cover tagline, logo beside the address, pull quotes, word forms (#201)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64, Xcode 27, release CLIs.
Baseline `baf6574` (the coordination branch's head); candidate this tree on it.

| Binary | Source | SHA-256 |
| --- | --- | --- |
| baseline | `baf6574` | `e2bebda8d1e9bc2d7fa2fd4f892c89ad76116318920e3fe7096516c7b997aeca` |
| lane candidate | this tree, before the last refactor below | `eceeb115c0df…` (compare receipts) |
| final candidate | this tree | `887ecb2f232865817986ccbd32e73e219e9a196b3bfdd6a75d78a0ffba993b59` |
| probe | `tools/probe-raster-environment.swift` | `d185e95a75d9637a82cf300e56fc6844a2bc7491f4dc49af4f72640c8a6a9d9a` |

The final candidate differs from the lane candidate only by `inflectedForms` reusing
`inflectionStems` (the same set, built once); the magazine converted with both gives identical page
text, blocks and headings. Python 3.14.6; EPUBCheck from `/opt/homebrew/bin/epubcheck`. No source
PDF, EPUB or raster is committed; each evaluation was deleted once its result was recorded. Two source
fixtures were captured with `tools/capture-layout-fixture.swift` (`usda-11`, `usda-12`, text and
geometry only); expected text was read against 50 DPI Poppler renders.

Issue item 5 (page 23's running foot, drawn twice, prints once) was not part of this assignment and
is unchanged.

## Evidence and causes

### The cover's tagline (item 1)

Page 1 sets `Agricultural Research Service • Solving Problems for the Growing World` in 14-point
bold at y 30–50, the page's last line, in its lowest tenth. The cover states no body of its own (eight
lines), so #186's `documentHeadingFloor` measures it against the document's 10.5-point body, and 14
points clears it. Neither size nor case sets it apart from a title. What does is its place: a heading
at the foot of a page of running text heads the section the next page opens (#103), but a page too bare
to state its body runs on into no section, and nothing on the page stands beneath the line.

### The back cover's logo (item 2)

Page 24's ARS logo is a vector crop at x 36–72, y 705–757 that holds no text. The return address
beside it, at x 80, is four 10-point lines (tops 759.1 to 717.8, bottom 704.5) at 13.4-point leading:
the block spans the logo's height. No whitespace cut separates them (the logo's side holds no prose,
so the 8-point gap is no column gutter), and the row sort ordered the logo by its middle, y 731, which
falls between the second line (middle 739) and the third (725.5).

### Pull quotes (item 3)

The three pull quotes are 15–16-point display lines over a photograph box:

| Page | Lines | Last line |
| --- | ---: | --- |
| 11 | 10 | `per night.”—Douglas Burkett` |
| 12 | 7 | `—Dan Kline` (centred, alone) |
| 14 | 10 | `methods.”—Ken Linthicum` |

#55's pull-quote rule reads a run of stacked heading-size lines as prose when its last line ends a
sentence. Each of these ends on its speaker's name after a dash, so none qualified; the heading merge
then stopped at the first sentence end (`…in 2003.`, `…world.”`, `…U.S.`), and each quote became two
headings in the navigation. The magazine's quotations open with `“`; the Fed's chapter-opener
summaries (#55), which the same rule reads, open with no quotation mark and name no speaker.

### Word breaks (item 4)

`unquestion-ably` (9/11 page 172) is not a lexicon gap: the English lexicon holds `unquestionably`,
and `lexiconVouches` joins `unquestion-` + `ably` in isolation. The 9/11 report prints its word breaks
as `=` (#126), which the vocabulary pass reads before the book-level evidence restores it to `-`; its
word split treats `=` as a separator, so the line `…is unquestion=` recorded `unquestion` as a book
word. With the lexicon's `ably`, the halves were both words and the break stayed undecided.

The magazine's remaining breaks: `nonagri-cultural` (the lexicon lists `agricultural`, not the prefixed
word), `launder-ings` (it lists `laundering`), `as-say` (both halves are words), `neonic-otinoids` and
`pyre-throids` (no form listed; `pyre` is a word).

## Rules

- **`LayoutReconstructor.addVocabulary`**: a line `endsWithEqualsHyphen` accepts records no last word.
  The half before the `=` is no word whether or not the book hyphenates with `=`.
- **`LayoutReconstructor.lexiconVouches`**: the joined word is also vouched for when the lexicon holds
  it without one inflectional ending (`inflectionStems`: `launderings` → `laundering`), or when it is
  a lexicon word of five or more letters under a prefix English closes up (`non`, `un`, `re`, `pre`,
  `anti`, `multi`, `over`, `under`, `inter`, `semi`, `sub`, `super`) and the break falls inside that
  word, not at the prefix. The halves still may not both be words.
- **`closesBarePage`** (in `blocks`): on a page whose reflowable text establishes no body (#186's
  `documentFloor`), a heading-size or label line whose middle lies in the page's lowest tenth, with no
  line beneath it, is no heading.
- **`besideBlock`** (in `blocks`, beside #117's section icons): a preserved region holding none of the
  page's text reads at the first line of the block to its right when that block is two or more lines
  whose middles lie within the region's height, set within two bodies of it, stacked at ordinary
  leading (gaps under 0.9 of their size) and spanning the region's height to half a body. A crop
  holding text (Wallace's formula crops beside their steps' notes) and a picture to the right of text
  keep their place.
- **`pullQuoteRuns` / `endsAttributedSentence`**: a run of stacked display lines also reads as a pull
  quote when it ends in terminal punctuation, closing quotes, a dash and one to four capitalized words.
  **`isQuotation`**: a run that opens with a quotation mark or ends in such an attribution is written
  as one `.pullQuote` block (`<aside class="pullquote" role="doc-pullquote"><p>…</p></aside>`), in no
  heading and not in the navigation; a page-crossing paragraph join passes over it as over an image.
  Display prose without either (the Fed's chapter openers) stays a paragraph, as before.
- **`tools/check_corpus_content.py`**: `pullQuotes` expectations: the phrase must sit inside one
  `role="doc-pullquote"` element on the page.

A first attempt keyed pictures beside text in the row sort (`sortedByRows`) for pictures on either
side; it split other paragraphs on magazine page 17 (a photograph right of a column) and merged
Wallace's step notes on 21 pages. It was replaced by `besideBlock` above, which changes neither.

## Contracts (`corpus/regressions.json`)

26 checks added (3,654 → 3,680) on 587 → 590 reviewed pages:

| Case | Added | Checks |
| --- | ---: | --- |
| `usda-ars-agresearch-2012-11` | 17 | page 1: the tagline no heading and a paragraph; 2: `nonagricultural` present, `nonagri-cultural` absent; 11: the Burkett pull quote, both former headings absent, `launderings` present and `launder-ings` absent; 12: the Kline pull quote, both former headings absent; 14: the Linthicum pull quote, both former headings absent; 24: the whole return address one paragraph, standing after an image (`captionedImages`) |
| `gpo-911-2004` | 6 (+2 pages) | page 172: `unquestionably` present, `unquestion-ably` absent, and `uncertainHyphen` absent (replacing its `warningCodesAnyOf: uncertainHyphen`); 298: `Fluorescent` in its paragraph, `Fluores-cent` absent; 358: `preeminent` present, `pre-eminent` absent (the book prints `preeminence` twice) |
| `noaa-nca5-2023` | 2 (+1 page) | page 53: two region impacts, each one paragraph now that their icons read before them |
| `ntrs-20200002975-gwl-2020` | 1 | page 20: the third biography one paragraph across its portrait |

The baseline fails all 17 new magazine checks (`tools/check_corpus_content.py` on both evaluations);
the candidate passes every contract. The magazine's and the NASA paper's review files record the change.

## Tests

`Tests/PDFReflowLibTests/MagazineCoverAndQuoteTests.swift`, 9 tests; `MagazineLeftoversTests`'
back-cover control now finds the address as one heading (the logo no longer splits it). Two Python
tests for the `pullQuotes` check and its parser.

| Test | Reproducer / control |
| --- | --- |
| `magazinePullQuotesClosingOnTheirSpeakerAreAsides` | `usda-11`, `usda-12`: one pull quote each, whole, with its speaker; no heading holds a quote line. |
| `anAttributionClosesAQuotedSentence` | Positives; controls `Remarks—John Smith`, a dash mid-sentence, a lowercase tail. |
| `aDisplaySentenceIsAnAsideOnlyWhenItQuotesSomeone` | A quoted display sentence is an aside; the same sentence unquoted stays a paragraph (#55); a two-line title stays one heading. |
| `aPullQuoteIsWrittenAsAnAsideOutsideTheNavigation` | The writer's markup; no heading, nothing in `nav.xhtml`. |
| `aTaglineAloneInABarePagesFootHeadsNothing` | `usda-1`: the cover lines stay headings, the tagline is a paragraph; control without the document body: a heading. |
| `aHeadingAtTheFootOfRunningTextStillHeadsTheNextPage` | Controls: a title at the foot of running text (#103); on a bare page, a title above the foot band and a foot-band title with a line beneath it. |
| `aLogoLevelWithTheReturnAddressReadsBeforeIt` | `usda-24`: the logo, then the whole address. |
| `theBooksEqualsHyphenLeavesNoFragmentInTheVocabulary` | `unquestion=` records no `unquestion`; the join closes; control: with the fragment recorded, the hyphen stays and warns. |
| `theLexiconVouchesForAnInflectionOrAPrefixedWord` | `launderings`, `nonagricultural`; controls `non-agricultural`, `as-say`, `pyre-throids`. |

## Corpus lanes

`tools/run_corpus_regressions.py`, one case per call, with the compiled probe and
`--execution-context host-terminal`, baseline and lane candidate; `tools/compare_conversion_runs.py
--allow-different-converters --detail` on every case. **All 20 lane cases pass on the candidate**;
9/11 fails only its page-172 `uncertainHyphen` warning check, rewritten above. No image changed and none
was renamed in any case.

| Case | Changed pages | What changed |
| --- | ---: | --- |
| usda-ars-agresearch-2012-11 | 20 (14 heading ranks only) | −1 heading (tagline), −6 headings → 3 pull quotes, logo before the address (page 24), 2 hyphens removed; the tagline was the only 14-point tier, so smaller headings move up one level |
| gpo-911-2004 | 11 | 10 hyphens removed: `unre-fueled`, `unquestion-ably`, `launder-ers`, `dis-sembled`, `nondis-seminated`, `Fluores-cent`, `reas-cend`, `unfath-omable`, `pre-eminent`, `overabun-dance`; page 287 only a note reference's context. `uncertainHyphen` pages 75 → 65 |
| noaa-nca5-2023 | 7 | pages 53–54: region icons read before the two-line impacts beside them, which each become one paragraph; 4 hyphens removed (`overre-liance`, `unafford-ability`, `desali-nating`, `interorganiza-tional`); page 1770 markup only |
| scotus-loper-bright-2024 | 4 | 2 hyphens removed (`elid-ing`, `im-pliedly`); two pages' note references' context |
| cdc-zombie-pandemic-2011 | 21 (20 heading ranks only) | page 8's comic lettering `WHAT IN THE... ?!`, the page's last line in its foot band, is no heading; its tier's removal re-ranks the rest |
| ntrs-20200002975-gwl-2020 | 1 | page 20: the third biography one paragraph, its portrait before it |
| fed, Wallace, FAA, DGA, Our Flag, Blue Book, Geltman, Replay Clocks, USGS copper, Census, Pro Se 1, DASC, Earthdata, TechPort | 0 | — |

Review, every change read against the source text or render:

- **Hyphens.** 18 words across four documents lose a line-end hyphen; all are hyphenation breaks of
  ordinary words, and none gains one. The 9/11 report's break signs are `=`, its word-break glyph,
  so `pre=eminent` is a break (the book prints `preeminence` elsewhere).
- **Headings.** Every lost heading was read: the magazine's tagline and its three pull quotes, and a
  CDC comic's sound-effect lettering. No heading was gained. The Fed's chapter-opener pull quotes are
  unchanged paragraphs.
- **Order.** The logo rule changed the magazine's back cover, NOAA's page 53–54 icon grid and the
  NASA paper's third biography, each for the better; Wallace's worked examples and the magazine's page
  17 are unchanged.

Warren is outside the lane (#5) and was not converted. Disk: 65–72 GB free throughout, checked before
each conversion.

## Verification

- `swift build -c release`; `swift test`: 1,029 pass.
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 251 pass; `python3 tools/update_doc_counts.py --check`.
- `scripts/check-all.sh --fast`: exit 0.
- The magazine, 9/11, NOAA and NASA Word paper lanes re-run with the edited contracts: pass.

## Remaining defects

1. **Paragraphs a pull quote interrupts stay split** on its page (page 12's `…Pest Management Research`
   / `Unit’s Aerial Application…`): the page-crossing join passes over a pull quote, but no rule joins
   the two halves of a paragraph around one inside a page.
2. **`neonic-otinoids`, `pyre-throids` and `as-say`** keep their hyphen and warn: no listed form, and
   `as` + `say` are both words.
3. **Pictures to the right of text** still order by their middle and can split the text beside them
   (magazine page 17's photograph and its credit stand between `…stem water potential,” which is the`
   and `water potential of the stressed…`), as on the baseline.
4. Issue item 5, **page 23's doubled running foot**, is untouched.
