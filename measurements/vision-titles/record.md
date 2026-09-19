# Vision container titles: do not adopt as heading semantics

> The captures and `review.json` now live in `tools/vision_titles/`, where `tools/test_vision_titles.py` reads them; the paths below are as measured.

Investigation of [#24](https://github.com/vocaro/PDFReflowLib/issues/24), baseline
`b7a5bbe5c1115e343b91294be1e308dd3b563876`, 2026-09-15, macOS 27.0 (26A428),
Xcode 27.0 (27A266a), arm64. **Issue #24's validation is complete; closure is recommended
with title-metadata mapping rejected. No production change is retained.** The controls
below establish ownership but do not qualify a safe semantic mapping rule. This does
not resolve the comic layout work in #18 or general OCR heading fidelity.

## Question and source controls

Can `DocumentObservation.Container.title`, with validated ownership of an extracted
line, supply reliable OCR heading semantics beyond the earlier
[per-line title-flag investigation](../ocr-headings/record.md)?

The new probe captures the actual container title, including transcript, region and
its own line observations, plus root line UUIDs, quadrilaterals, transcripts, wrapping
and `isTitle`. It inspects nested table-cell and list-item containers too. Each page
uses **one recognition request**, so ownership comparisons never mix results from two
requests. The probe follows `OCRReader`'s English/language-correction settings and
`PageRasterizer`'s default conversion options (180 DPI subject to the pixel limit).
It does not invoke reconstruction, read inherited text to choose headings, or change OCR.

[review.json](review.json) records roles and genuine heading groups independently reviewed
from the original source-page rasters. The 14 physical pages span five checksum-pinned
PDFs: the CDC comic, Warren scan, Blue Book scan, Fed and 9/11. Fed and 9/11 are forced
raster-recognition controls; normal native extraction is unchanged. Source identities and
actual raster dimensions are in every [capture](captures/) and [results.json](results.json).
New page rasters are under `source/`; the review references existing source images for
CDC pages 13/15/16 and Warren page 50 instead of duplicating them.

## Observations

All 13 nonempty container titles have **empty `title.lines` arrays** on this SDK/runtime.
Their transcripts and regions are populated. Matching the entire title transcript and
all four normalized rectangle values (tolerance `1e-6`) identifies exactly one root line
for each. All 13 matches also agree with the sole root `isTitle` flag. This establishes
a bounded text/region ownership observation, **not semantic correctness**. No claim is
made that title lines are always empty on other SDKs or that approximate matching is an
API guarantee. Repeated identical text in different regions and ambiguous overlapping
matches have separate diagnostic tests; ambiguity is never resolved by taking the first match.

| Source page | Container title transcript | Independently reviewed role |
| --- | --- | --- |
| CDC 13 | `OKAY, OKAY... I'M COMING.` | Speech balloon; false heading |
| CDC 15 | `PREPAREDNESS 101:` | First line of genuine three-line Part 2 title; incomplete |
| CDC 16 | `CERTERG` | OCR of tilted scene sign lettering; false heading |
| Warren 7 | `REPORT OF` | First of four title lines; incomplete |
| Warren 21 | `Contents` | Complete checked page heading |
| Warren 30 | `varied roles which an American President performs-Head of State,` | Body continuation; false heading |
| Warren 50 | `September 26 to October 3, 1963, and his known contacts with` | Body continuation; false heading |
| Warren 100 | `was stationed.es` | Body fragment with a raised reference; false heading |
| Warren 920 | absent | Textless back cover; correct absence |
| Blue Book 4 | `PROJECT BLUE BOOK` | First line of publication title; omits report identity |
| Blue Book 9 | `with the year 1952. In these charts, 3201 cases have been used.` | Body continuation; false heading |
| Blue Book 74 | `TABLE IV` | Table-caption label; table ownership is required |
| Fed 32 | `The Fed Explained: What the Central Bank Does` | Small running header; false section heading |
| 9/11 19 | `"WE HAVE` | First half of two-line chapter title; incomplete |

These are observed OCR strings, including errors, not corrected source transcriptions.
The 149 nested container visits (Warren contents: 82; Warren page 50: 7;
Blue Book table: 60) supply **zero additional titles**. Those counts are visits through
table rows and list items, not a guarantee of distinct semantic objects or exhaustive
hierarchical heading detection. Warren 920 has no recognized lines and a nil title.

Seven of the thirteen candidates are demonstrably prose, dialogue, scene text or furniture.
The table-caption candidate is counted separately because its correct representation needs
table association. Four candidates are incomplete genuine titles and one is the complete
checked `Contents` heading. Eight reviewed heading groups are absent or incomplete in the
selected title text, including the CDC title's `ZOMBIE PANDEMIC` and `PART 2` continuations,
the Fed's box and section titles, and the 9/11 chapter/section/subsection headings.
These deliberately chosen controls are counterexamples, not population precision/recall estimates.

## Decision

Issue #24 asks to evaluate source typography, establish title/line ownership, include
comic false-positive controls, document limitations, and map **only unambiguous titles**.
The retained captures and source review complete that evaluation. The mapping condition
requires semantic validity as well as a unique line owner; ownership alone fails the
source controls below. The issue does not require adopting metadata that fails validation.

The complete Warren `Contents` heading is a positive source control, but the tested
metadata checks do not distinguish it from false headings. Recognizing that one page
by its reviewed transcript is not a validated runtime selection rule. Thus no candidate
is qualified for production mapping by this investigation; this is a rejected approach,
not an unfinished implementation requirement under #24. Reconsidering adoption would
require additional semantic evidence beyond the title metadata evaluated here.

- **Direct title-line identity mapping:** supplies no candidates on these captures because
  `title.lines` is empty. UUID/equality association cannot be established from nonexistent
  title line observations.
- **Unique transcript/region ownership:** supplies all 13 candidates, including all seven
  false headings. Precise ownership cannot make an incorrect semantic label correct.
- **Require agreement with `isTitle`:** rejects none of those candidates. The two fields
  provide no independent semantic corroboration on this sample.
- **Use titles as the sole OCR heading source:** also loses complete genuine title groups
  and lower-level headings. There is no validated title hierarchy to map to H1-H6.

Apple documents [title](https://developer.apple.com/documentation/vision/documentobservation/container/title)
as the title found within a container and
[isTitle](https://developer.apple.com/documentation/vision/recognizedtextobservation/istitle)
as whether text is the document title. The local SDK exposes `title` as an optional
`Container.Text`, with text/line/region access, and no heading-level property. Neither API
description supplies a classification-accuracy guarantee. The evidence above rejects these
signals as sufficient for production heading mapping. No document-name exceptions, phrase
whitelists, threshold changes, runtime prototype or passing corpus-semantic contract is added.
Stronger source-supported semantic evidence is needed before adoption. This investigation
does not change the existing geometry-based OCR heuristic or claim it is correct.

## Verification and reproduction

- Five new offline Python tests protect the retained source counterexamples, empty-line
  versus absent-title distinction, exact transcript/region matching, duplicate ambiguity,
  invalid/overlapping-region rejection and refusal to reuse source labels when a new run
  selects a different title. They validate investigation logic and historical
  fixtures, **not a production repair or future Vision model output**.
- The complete Python suite passed **82 tests** after the final review-binding check.
- Existing Swift heading/OCR selection passed **25 tests**, including native heading controls,
  public selective OCR, empty-source fallback, cancellation and source-image behavior.
- The new Swift probe compiled and captured all fourteen selected pages. The reproduction
  script successfully built it and recreated the full selected-page campaign in a new
  directory. Reanalysis with the final reporting/review checks produced
  [reproduction-results.json](reproduction-results.json), with the same summarized findings.
- No production, fixture-conversion or EPUB serialization code changed. A complete corpus,
  EPUBCheck, iOS Simulator, physical-device, memory or timing campaign was not run for this
  diagnostic-only change; none is claimed. This is one platform/configuration qualification,
  not a cross-device or model-version guarantee.

From the repository root, with the pinned corpus already in the ignored cache:

```sh
python3 measurements/vision-titles/capture.py --output /tmp/vision-titles-new-run
python3 tools/analyze_vision_titles.py
python3 -m unittest discover -s tools -p 'test_vision_titles.py' -v
swift test --filter 'Heading|OCR'
```

`capture.py` requires a new output directory, performs no downloads, checks each full source
SHA-256 before recognition, and writes raw captures, analysis, commands, source hashes and
platform receipts. Fresh capture analysis is an observation report, not an assertion that
future OCR must match historical outputs. The committed review labels only apply to the
retained title selections; any new title selections require source review before their
semantic roles can be reused. The analyzer refuses changed title transcripts and asks for
new source review. The automatic checker must not be treated as independent semantic truth
for a future model. [implementation-sha256.txt](implementation-sha256.txt) identifies the
final probe, analysis, review, tests and supporting production files. `swift-tests.log` and
`python-tests.log` retain the successful verification output.

For source review, render the physical page independently, for example:

```sh
pdftoppm -f 7 -l 7 -scale-to 1100 -singlefile -png \
  corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf /tmp/warren-7
```

The initial filesystem-sandbox attempt could not create Vision's CVPixelBuffer; the
platform-enabled captures and Swift checks succeeded. A separate initial Swift invocation
could not write the compiler cache. The retained test logs record the successful runs.
Neither environment failure is counted as a regression or investigated under another issue.
