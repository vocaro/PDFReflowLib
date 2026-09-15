# Three fidelity fixes and cross-document controls

The macOS 27 arm64 release CLI built from `ac65df4` plus the implementation recorded in
[identities](implementation-identities.json) passes all eight complete corpus evaluations with
library defaults. Executable SHA-256:
`1e5a7489175b77dd47a5dbe26f281f57b98df5f5c5eda961711559a858309998`.
The [corpus log](corpus-gate.log.gz), [summary](summary.json), [metrics](runs.json) and individual
case directories retain the evidence. Original PDFs and generated EPUBs remain in ignored caches
and evaluation directories, not in this measurement.

## Fixes and regression evidence

- **Inline powers (#1).** Physical algebra page 343 supplies an explicit 4.2-point Core Text
  baseline shift for the `2` in `ax²`. Native extraction carries that evidence into output-neutral
  superscript/subscript flags; EPUB serialization emits `sup`/`sub`. Small fonts alone do not
  imply powers. Near-zero positioning noise and offsets approaching full line spacing are
  excluded. [Source](algebra343-source.png) and [rendered output](wallace-algebra-2010-343.png)
  show the raised exponent and adjacent selectable prose; the displayed derivation remains an
  unchanged source image. The source's wording “general from” is preserved rather than corrected.
- **Narrow prose columns (#2).** FAA physical pages 91 and 511 have continuous gutters around
  12 points, below the previous 1.5-body-font-size threshold. A 0.75 threshold now applies when
  each side has at least two substantial text lines (width at least 12 body-font sizes). Other
  cuts retain the previous threshold. This separates complete prose columns without treating
  short label/value cells as independent columns. Review [page 91 source](faa91-source.png),
  [page 91 output](faa-phak-8083-25c-91.png), [page 511 source](faa511-source.png) and
  [page 511 output](faa-phak-8083-25c-511.png). The left-column endings precede the right column;
  the glossary's Wind entries and World Aeronautical Charts precede Zone and Zulu.
- **Numeric table preservation (#16).** Our Flag physical page 27 has ten aligned numeric
  dot-leader rows and two headers. A conservative detector adds their complete region to image
  preservation, with `imageRegion` warnings; it leaves neighboring prose selectable. The
  [source](flag27-source.png) and [actual EPUB image](flag27-table-output.png) retain all ten
  associations: 20→4×6, 25→5×8, 40→6×10, 50→8×12, 60→10×15, 70→12×18, 90→15×25,
  125→20×30, 200→30×40 and 250→40×50. This is a readable image, not an accessible semantic
  table or a general borderless-table parser.

The three source regressions run before the fixes and produce seven assertion failures:
four column-order failures, two missing-superscript failures and one absent table-region failure
([baseline log](negative-baseline.log.gz)). The baseline contains only a behavior-preserving
extraction of the attributed-run helper in addition to `ac65df4`, so it can exercise that helper.
The new fixtures retain pinned source text/geometry/attributes, not reconstructed output.
The final capture tool reproduces all six new JSONs byte-for-byte ([recapture](fixture-recapture.json)).

Positive controls cover spanning headings and figures, indented single-column prose, bold/italic
combinations, both baseline keys, ordinary small fonts, native PDF superscript/subscript conversion,
monospaced text, contents entries, prose ellipses, numeric dimensions and percentages, missing
headers, sparse rows and intervening prose. Existing fraction/table pixel checks remain enforced.

Cross-document review of the first implementation finds two collateral defects before publication:
indiscriminate narrow cuts separate 9/11 appendix names from their descriptions, and full-line
OCR offsets become superscripts/subscripts in the comic. Both receive source-derived failing
controls ([name/description failure](negative-name-description.log.gz),
[OCR baseline failure](negative-ocr-baseline.log.gz)) before the final safeguards. The final
9/11 page-451 contract also checks eight ordered name/description phrases. Its
[source](911451-source.png) and [output viewport](gpo-911-2004-451.png) retain row associations;
paragraph boundaries are still imperfect. The [comic output](cdc-zombie-pandemic-2011-5.png)
retains ordinary line sizing and the source image; inherited transcription remains visibly noisy.

## Complete validation

The final macOS and iOS 27 Simulator suites each execute **58 Swift tests**: 57 without known
issues and one explicit known detached-fraction failure (#20). The expected-failure wrapper covers
only the unresolved intact-fraction assertion; decoding/conversion errors still fail normally.
The [iOS log](ios-tests.log.gz) records `TEST SUCCEEDED`. The corpus gate also passes **49 Python
tests**, six small PDF conversions with EPUBCheck, and all **eight complete source PDFs**:
2,151 pages. The **77 content checks on 22 reviewed pages** include script identity and local
context, selected reading order, text, images, warnings and complete source-page navigation.
Negative checker tests reject flattened/wrong scripts, wrong context/pages and caption/literal-tag
substitutions. These are targeted checks, not a whole-book fidelity score.

| Corpus | Conversion seconds | Peak converter RSS MiB | RSS budget MiB |
| --- | ---: | ---: | ---: |
| FAA | 36.9 | 754.3 | 1280 |
| Wallace algebra | 8.6 | 78.3 | 256 |
| 9/11 | 10.1 | 114.8 | 256 |
| The Fed Explained | 6.6 | 276.9 | 768 |
| Dietary Guidelines | 0.7 | 100.4 | 192 |
| Our Flag | 1.3 | 92.3 | 192 |
| CDC comic | 6.8 | 364.1 | 512 |
| Blue Book | 34.0 | 309.0 | 512 |

Each row is one isolated release-converter run on macOS 27 arm64 with library defaults, not a
latency distribution, performance comparison or physical iPhone/iPad qualification. RSS excludes
separate Apple services. All eight pass their existing memory ceilings, EPUBCheck and monotonic
progress/completion checks; progress measures completed work, not predicted elapsed time.
Full Warren and NOAA remain explicitly excluded for their known image-output ceiling failures
(#5), not counted as successful conversions.

## Changed-output review and practical limits

[Changed pages](changed-pages.json) compare the final EPUB spines against the complete previous
`ac65df4` run in `measurements/preserved-region-regressions/`. All image-byte multisets are
unchanged except Our Flag page 27's added table. Reflow/OCR page counts are unchanged for every
case; Our Flag image count is 147 instead of 146. Text order/spacing changes on 361 FAA pages,
58 Blue Book pages, three Our Flag pages and one page each in algebra, DGA and 9/11. Fed and
CDC normalized source text is unchanged. Inline script styling affects additional pages, listed
separately. Listing a page does not assert its full fidelity has been visually qualified.

The non-whitespace source-character multiset is identical on every page except Our Flag's table
text moving into its complete image and two justified wrap repairs: `on- line`→`online` on FAA
page 36 and `back- wards`→`backwards` on algebra page 90. This guards against unexpected loss;
it cannot establish sentence meaning or correct order by itself.

The algebra [exercise source](algebra347-source.png) and [output](wallace-algebra-2010-347.png)
retain numbered equations and powers. Source/EPUB image bytes and normalized text on pages
347, 479 and 483 are unchanged from `ac65df4`. The reviewed [answer-key source](algebra479-source.png)
and [output](wallace-algebra-2010-479.png) retain numbered radicals/fractions; the
[graph source](algebra483-source.png) and [output](wallace-algebra-2010-483.png) retain labeled
coordinates. These are selected controls, not approval of every exercise's ordering or all
answer-key fractions. Screenshots are browser viewports of actual unpacked EPUB XHTML through
the existing comparison tool; they do not show entire long reflowed source pages.

Review of [DGA page 4](dga-2025-2030-4.png) shows complete healthy-fat bullet sentences rather
than line interleaving, but its section-heading ownership remains imperfect (#13/#14).
[Fed page 14](fed-explained-2021-14.png) still misclassifies large body text as headings (#12).
[Blue Book page 74](cia-blue-book-14-1955-74.png) still contains noisy scan-edge glyphs and
unreliable table transcription; the accompanying unchanged source images and unverified-layer
warnings remain essential (#7). Our Flag drop-cap ordering and general figure/name/description
ownership remain open (#12/#17). Native baseline evidence does not recognize every mathematical
layout. Detached fractions (#20), general/scanned table semantics, full Warren/NOAA completion
and physical-device memory qualification remain unfinished.

## Reproduction and attribution

With the pinned corpus cache populated and Xcode selected:

```sh
PATH=/opt/homebrew/bin:$PATH DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-all.sh --corpus
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme PDFReflowLib-Package -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

The simulator identifier used by the retained run is
`C4966BA9-56CD-4F21-9829-68567AAE8E6F`. Fixture capture instructions are in
[regression testing](../../doc/regression-testing.md). Input identities are verified before
conversion/capture. Manifest status prose is updated after evaluation; each case's retained
`result.json.gz` records its actual evaluation metadata and pinned PDF identity.

Algebra excerpts derive from *Beginning and Intermediate Algebra*, copyright 2010 Tyler Wallace,
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/),
[source PDF](https://s3.amazonaws.com/myopenmath/cfiles/19515/Beginning_and_Intermediate_Algebra.pdf).
These extracted-text/geometry and rendered review derivatives retain that attribution and are not
relicensed under MIT. Government-document derivatives retain publisher provenance in the corpus
manifest and their source fixtures. No original corpus PDF is bundled in the shipped library.
