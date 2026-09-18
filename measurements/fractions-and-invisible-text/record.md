# Detached fractions and invisible OCR typography

The macOS 27 arm64 release CLI from `5b14026` plus the changes pinned in
[implementation identities](implementation-identities.json) passes the complete eight-document
regression gate. Executable SHA-256:
`46f82ed7841c582cc61f24ccf677b886a31f0edf2c4202d9ec99e54ba41fdbe9`.
Original PDFs and generated EPUBs remain outside this measurement. The test fixtures record
source extraction evidence, not converter-generated expectations.

## Fixed behavior

**Detached fractions (#20).** Short painted bars with nearby mathematical terms above and below
supply bounded preservation regions. A nearby equation prefix ending in `=` joins that region.
The original [source](fraction-source.png) and [actual EPUB image](fraction-output.png) retain
`x = 36²/84` with its numerator, raised exponent, bar and denominator together. Surrounding prose
remains selectable, and the report warns that the formula region is an image. This resolves the
specific detached-fraction regression without claiming general equation transcription or MathML.
The former known-failure wrapper is removed; its intact-fraction pixel predicate is mandatory.

Controls reject ordinary horizontal rules, underlines, connected table grids, monospaced text,
distant terms and unrelated prose. Source-derived algebra physical page 479 checks both terms
of the answer-key fractions. The existing connected-fraction and table cell pixel assertions
remain enforced. A neighboring-prose control exposes extra region padding that captures prose
beside an already complete fraction; removing the redundant padding fixes that failure.

**Invisible OCR fonts (#6).** The graphics scan tracks text rendering mode through text-showing
operators, saved graphics state and nested forms. Exclusively invisible mode-3 text over a
page-sized graphic contributes transcription, but its font and size cannot declare code or
headings. Mixed/visible text, clipping mode and unsupported drawing streams do not enter this
classification. Actual visible Courier and genuine visible headings retain their semantics.
Source images and the existing `unverifiedTextLayer` warnings remain available.

Warren physical pages 50 and 910 have source-derived regressions. In the final nine-page excerpt,
ordinary prose on physical page 50 becomes paragraphs; actual numbered points 10 and 11 retain
the library's list representation. Physical page 910 no longer emits font-derived code/headings.
See [source page 50](warren50-source.png), [rendered paragraph output](warren50-output.png),
[actual block structure](warren-blocks.json), [report](warren-report.json) and
[excerpt identity/page map](warren-excerpt-identity.json). The screenshot's reviewed output is
checked against the final binary for identical normalized text and image bytes.

This is not OCR correction or true heading recovery from scans. The actual excerpt still has
`Com-munist` and corrupt words such as `bis` and `witb`; bounded excerpt vocabulary differs from
whole-book vocabulary. The unit fixture separately supplies controlled vocabulary to test joining.
Index grouping and other reading-order problems remain unqualified. Skipping meaningless
attributed-style extraction on these pages is not a verified fix for the PDFKit leak in #4.

## Regression evidence

- [Detached-fraction negative](fraction-negative.log.gz): the old implementation fails the
  intact-fraction assertion after removing its known-failure wrapper.
- [Invisible-font negative](invisible-negative.log.gz): the synthetic hidden-Courier case fails
  three assertions before the fix; visible typography controls pass.
- [Warren source negative](warren-negative.log.gz): reverting only the two style guards in an
  isolated copy of the final package produces six source-fixture assertion failures. This is a
  targeted reversal, not a pristine baseline build.
- [Crop-growth negative](crop-growth-negative.log.gz): the adjacent-prose control fails before
  redundant padding is removed.
- [Fixture recapture](fixture-recapture.json): independent captures reproduce all three new
  source JSON fixtures byte-for-byte, after verifying the original PDF checksums.
- [Final corpus gate](corpus-gate.log.gz): 65 Swift tests with zero known-failure exemptions,
  49 Python tests, six small PDF conversions and eight complete corpus PDFs pass.
- [iOS Simulator](ios-tests.log.gz): all 65 Swift tests pass on iOS 27, iPhone 18 Pro simulator.
  This is compatibility evidence, not physical-device performance qualification.

The [corpus summary](summary.json) passes all 77 existing content checks across 22 reviewed
pages. These contracts are unchanged. The full eight PDFs total 2,151 pages; passing EPUBCheck,
progress and memory gates across all pages does not imply human-reviewed fidelity on all pages.
The separate Warren excerpt passes EPUBCheck, preserves nine source images, reflows seven pages
and runs with OCR disabled. Both targeted conversions have monotonic progress ending at 100%
([targeted checks](targeted-checks.json)); work fractions are not elapsed-time predictions.

## Cross-document review

The [complete output comparison](changed-pages.json) uses the preceding `5b14026` corpus outputs
as its baseline. Six documents—FAA, CDC, DGA, Fed, 9/11 and Our Flag—retain identical normalized
source text, inline script records and image bytes.

Algebra changes image bytes on nine physical pages: 43, 184, 198, 207, 208, 209, 249, 312 and 389.
Eight pages change selectable text; six change script records because mathematical terms move
into preservation images. All 14 changed image assets are retained here as `algebra-<page>-<index>.png`
and visually inspected. Fractions and nearby labels remain visible. The broader arithmetic and
long-division layouts are not fully reconstructed: for example, the top operand of the stacked
multiplication on [source page 198](algebra198-source.png) remains outside its preserved lower
region. The [page 208 source](algebra208-source.png) likewise shows why general math grouping
remains a separate qualification task. No claim is made that every equation becomes one image.
Other algebra image assets, including reviewed introduction, exercise and answer-key pages,
remain byte-identical.

Blue Book changes normalized text/order/spacing on 135 pages and script records on 259 pages
when meaningless invisible font styling is discarded; every image remains byte-identical.
The non-whitespace character comparison differs only on page 226: two hyphens are removed by
existing vocabulary-based wrap repair (`ll-` + `l` and `Ill-` + `l`). These noisy OCR glyph joins
are not verified spelling corrections. [Rendered page 226](blue226-output.png) visibly remains
unreliable transcription. The source images and warnings continue to be essential; #7 remains
open and this scan is not fidelity-qualified.

## Resources and reproduction

These are single-run measurements on macOS 27 arm64 using the release converter and library
defaults. [Run metrics](runs.json) and each case directory retain evaluator results, conversion
reports, content assessments and EPUBCheck logs. The raw progress logs and memory-sample series
were dropped in #196; each case's `result.json.gz` keeps their summary (progress-check events and result, sampled
and converter peak memory).

| Complete document | Seconds | Peak converter RSS MiB | RSS limit MiB |
| --- | ---: | ---: | ---: |
| CDC | 7.3 | 366.8 | 512 |
| Blue Book | 31.1 | 166.2 | 512 |
| DGA | 0.8 | 100.3 | 192 |
| FAA | 37.5 | 757.6 | 1280 |
| Fed | 6.9 | 276.6 | 768 |
| 9/11 | 10.8 | 120.2 | 256 |
| Our Flag | 1.3 | 86.4 | 192 |
| Algebra | 9.7 | 78.7 | 256 |

Run `scripts/check-all.sh --corpus` with full Xcode, EPUBCheck and checksum-verified corpus
cache available. The source fixture tests run in ordinary `swift test` without corpus downloads.
Prepare Warren using `measurements/gpo-warren-1964/prepare-excerpt.py`; convert that excerpt
with `pdf-reflow input.pdf output.epub --no-ocr`. Its nine-page mapping is retained above.
Full Warren and NOAA remain blocked by the image-output ceiling (#5) and are excluded from the
complete-book gate. No performance improvement or physical-device memory budget is inferred
from these single Mac runs.

Wallace source/output derivatives retain Tyler Wallace's 2010 copyright and CC BY 3.0 license;
see [attribution](../../doc/third-party-notices.md). Government-document derivatives retain the
source provenance recorded by the corpus manifest and fixture identities.
