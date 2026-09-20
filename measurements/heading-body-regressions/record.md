# Heading evidence beside preserved graphics

> The Swift probes moved to `tools/probes/`, and `tools/pdfreflow_tools/swift_sources.py` now owns the library source list each one compiles with (`6e6ba6c`); the paths and hand-copied source lists below are as measured.

Issue #12 is resolved for its source case and the related measured Fed pages: ordinary 10-point
prose beside small-font tables, sidebars and figures stays prose instead of entering navigation
as individual headings. Ten native source-layout fixtures and seven Swift tests protect this
behavior, short titles beside images, and genuine section/chapter headings.

## Scope and mechanism

The page-wide character-weighted font mode includes text inside preserved graphics. On physical
Fed page 46, 8-point table/sidebar text dominates the estimate and makes ordinary 10-point body
lines exceed the former heading threshold. Heading evidence now also considers the lines that
actually reflow. At least three lines and 200 characters must support their dominant size; a
candidate must exceed that supported body size by at least 10%, as well as satisfy the original
25% page-size threshold. A short title alone does not establish a replacement body estimate.
The geometry estimate for whitespace cuts and paragraph joins remains separate.

Source render review covers Fed physical pages 13, 32, 45, 46, 54, 75, 77, 103, 109 and 123.
The pinned source is `fed-explained-2021`, SHA-256
`8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60`.
`tools/capture-layout-fixture.swift` verifies that checksum before producing the extraction
fixtures. Expected prose and headings come from the source, not converted output.

## Validation

Measured on macOS 27.0 (26A428), arm64, Xcode 27.0 (27A266a), production CLI with default
options. `identity.json` pins the implementation, tests, tools and corpus definitions against
base revision `9be59c9`. The before comparison uses the retained complete default-policy corpus
outputs from [the header measurement](../local-header-regressions/record.md), not a fresh timing
run of that old build.

- 89 Swift tests pass on macOS and iOS 27 Simulator (iPhone 18 Pro); 57 Python tests pass.
- Six fixture conversions, four client-policy conversions and ten rejection/cleanup cases pass.
- All eight complete corpus documents pass EPUBCheck, progress, source anchors, configured
  memory gates and 145 content assertions across 40 reviewed pages.
- The Fed report loses 85 false prose/list-line headings on pages 13, 46, 54, 75, 77, 103 and 109:
  total headings decrease from 240 to 155. No new heading is introduced. Every removed heading
  matches a 10-point source body line in the reviewed extraction fixtures.
- Six genuine modest-size section headings remain, including page 54's “Asset Valuations and
  Risk Appetite” and page 77's “Examination Report”. Page 46's two preserved graphic regions
  remain; prose retains the reviewed top-to-bottom sequence.
- All seven control books have identical parsed page text, paragraph/heading groups, inline-script
  observations and image order. All 3,922 image files across the eight books have identical bytes
  and page ownership/order. The collector enforces these comparisons.

The Fed text differences are paragraph grouping and existing line-end word joining, such as
`suc- cessfully` becoming `successfully`. All other non-whitespace/non-hyphen characters remain
identical. Remaining ambiguous hyphens retain the existing warning behavior.

## Failing controls and retained evidence

`before-tests.log.gz` captures the initial five tests: source page 46 and the synthetic mixed-font
case fail on the original implementation, while heading/short-title controls pass.
`before-content.json.gz` applies the final corpus contracts to the retained original output:
eight paragraph expectations fail, while all six genuine-heading expectations pass.

An initial change that applied the entire 25% threshold to the reflowable font size removed six
genuine 12-point section headings. `intermediate-heading-failure.log.gz` and
`intermediate-content.json.gz` record their failures. The narrower body-sized-candidate rule
passes both these guards and the original prose tests. This rejected change demonstrates why
full-corpus comparison and positive heading controls accompany the targeted fix.

`comparison-summary.json` records EPUB identities and changed pages. `reviewed-pages.json`
retains before/after parsed text and semantics for all seven changed pages. Each corpus directory
contains compressed evaluation, conversion, content, progress, memory and EPUBCheck receipts.
`release-gate.log.gz` and `release-ios-tests.log.gz` record the final successful gates.

## Reproduction

From the repository root, with checksum-verified corpus cache files available:

```sh
PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/check-all.sh --corpus

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -scheme PDFReflowLib-Package \
  -destination 'platform=iOS Simulator,id=C4966BA9-56CD-4F21-9829-68567AAE8E6F' \
  -derivedDataPath /tmp/pdfreflow-heading-ios CODE_SIGNING_ALLOWED=NO

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 \
  measurements/heading-body-regressions/collect.py \
  --before /path/to/retained-baseline/corpus --after /path/to/new-gate/corpus \
  --logs /path/to/heading-test-logs --output /path/to/new-evidence
```

The Simulator identifier and temporary paths are host-specific. The collector requires all eight
completed cases and the named diagnostic logs; it rejects unreviewed page changes or image drift.
The permanent regression gates do not require the retained old EPUBs.

## Limits

This is a bounded heuristic fix, not a heading-precision score, validated PDF structure-tree
consumption, or table transcription. Tables and diagrams retain their existing image semantics.
The successful corpus lane still explicitly excludes complete Warren and NOAA conversions under
the default image-output ceiling. No physical-device performance or PDFKit leak resolution is
claimed. Public API, defaults, resource ceilings and dependencies are unchanged.
