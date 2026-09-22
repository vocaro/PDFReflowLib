# A same-binary control for the run comparison (#284)

Tier: Python tool change, gated by `tools/test_conversion_comparison.py`; the variance it controls
for was observed on an isolated macOS arm64 release CLI and on the capture probe built from the
same sources.
Build: Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0 (26A428, Darwin 27.0.0, xnu-13432.1.9~1).

## What the method assumed

`tools/compare_conversion_runs.py` compares two complete evaluations and reports every page, image
and report field they differ in. The method that uses it — convert every corpus book with two
binaries and compare — reads those differences as the change's doing. That holds only if one
binary, run twice, produces none.

It does not. #284 measured four lane runs on one machine, two from each of two binaries, over all
150 XHTML documents of the 18 covered cases, and found `census-rrs2002-01` and
`cdc-zombie-pandemic-2011` differing between two runs of a binary that did not change:
census page 4 read as joined prose in one run and as the recognition's own line fragments in the
next; CDC page 7 lost its recognition entirely to the page image, and `nav.xhtml` lost the
nineteen entries built from its headings.

The same variance is visible one page at a time. Three captures of the Warren excerpt's page 4
through `tools/probes/capture-ocr-layout-fixture.swift`, minutes apart, one host, one probe
executable: 28 lines and 1,653 characters; a probe that died before writing; 28 lines and 1,647
characters. The first held the two phrases that case used to pin and the third held neither
(measurements/warren-excerpt-recognition-comparison/record.md).

## The control

`--control` takes a third evaluation, captured the same way, of the **baseline's own** converter.
The comparison then runs twice — baseline against candidate, and baseline against control — and
reports:

- `unstablePages`, `unstableImages`, `unstableReportFields`: what the baseline's binary moves on
  its own, which this comparison cannot charge to the candidate;
- `attributedPages`, `attributedImages`, `attributedReportFields`: what is left, which alone
  decides `passed`;
- `changedPages` and the rest keep their meaning: everything the two binaries differ in. Nothing
  is hidden. An unstable page may still hold a real change; the tool says it cannot tell.

A control whose `converterSHA256` is not the baseline's is refused before any content is read: a
control built from another tree measures that tree's difference as well and would charge it to the
host. It must also pass the same provenance and capability compatibility the other two do. Without
`--control` the tool behaves exactly as before — every difference reported, nothing attributed —
so no existing procedure changes.

## Coverage

Six tests in `tools/test_conversion_comparison.py`, all against the same synthetic evaluations the
file's other 22 tests use:

- a page both the candidate and the control move is `unstable`, not `attributed`, and the run
  passes;
- a page only the candidate moves is `attributed`, and the run fails;
- images and report fields separate the same way;
- a control built from another binary is refused, naming why;
- a control incompatible on any of the fields `compatible_receipts` already checks is refused;
- without a control nothing is attributed and the verdict is what it always was.

## What is not measured here

The three-evaluation demonstration on `census-rrs2002-01` itself was attempted and could not be
run: this host's Vision text recognition began failing outright while this was being measured, so
`probe-raster-environment` exits on `CRImageReaderError.e5rtError("e5rt_e5_compiler_compile call
failed", 11)` and then on `CRImageReaderError.unknownError`, and an evaluation cannot capture the
environment receipt the comparison requires. Eight capture attempts in a row failed the same way.

That failure is the thing this change exists for, one step further along: a gate reporting the
host rather than the library. The attribution logic is gated by the tests above, and the variance
it attributes is the measurement in #284 and in the Warren record beside it; what remains unmeasured
is the end-to-end run on those two books, which needs a host whose Vision works.
