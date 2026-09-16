# Concurrent PDFKit extraction: reproduction and mitigation

The `NSFont` exception in [#21](https://github.com/vocaro/PDFReflowLib/issues/21) is reproducible
with public Apple APIs on this Mac. It also occurs through the unmodified `NativeTextReader`.
The library now serializes synchronous native page extraction across converter instances;
finite release/debug campaigns pass with text and font-size assertions. This is a library-local
mitigation, not an Apple-confirmed fix, and it does not resolve the memory leak in #4/FB24783799.

## Host and inputs

Measurements use macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple Swift 6.4, arm64.
The baseline is `d40fe2f437af9777211a84d8d88b1e154cc95969`. Campaign identities pin exact
producer/extraction sources, optimization flags, fixture bytes and executable hashes, including
uncommitted source changes; `gitHead` alone does not identify a measured working tree.

The original synthetic RoleMap/MCR fixture recreates the earlier failing structure test's
three Helvetica text runs: “Small heading” at 12 points, “First paragraph line” and
“second paragraph line.” at 24 points. A second fixture removes the structure tree while
retaining identical visible content and marked-content operators. Both pass `qpdf --check`
without syntax or stream-encoding errors. That check does not validate all PDF semantics.

Each iteration opens a fresh PDFDocument inside an autorelease pool. Concurrent workers share
only an immutable input URL; they never share PDFDocument, PDFPage, PDFSelection or attributed
strings. Thus the reproduced workload is independent API objects reading the same file,
not a demonstration covering every combination of distinct files. Worker zero runs on the
main thread, worker one serially in the background, and worker eight starts eight independent
threads together. The probe verifies all three text lines, and attributed/native modes also
verify font sizes; an empty result cannot pass as a successful extraction.

## Observations

| Campaign | Work per process | Outcome |
| --- | --- | --- |
| Initial release matrix | 100 opens/worker; 0/1/8 workers; plain/attributed/native; both fixtures; 3 trials | 53/54 processes pass; concurrent raw attributed extraction aborts once |
| Unmodified native reader | 1,000 opens/worker; 8 workers; both fixtures; 10 trials | 19/20 processes pass; native extraction aborts once |
| Serialized native reader, release | Same 20-process workload | 20/20 pass; 160,000 completed extraction iterations |
| Apple-SDK-only build | 1,000 opens/worker; 1/8 workers; plain/attributed; both fixtures; 5 trials | 39/40 pass; concurrent attributed extraction aborts once |
| Serialized native reader, debug | 1,000 opens/worker; 0/1/8 workers; both fixtures; 3 trials | 18/18 pass; 60,000 completed extraction iterations |

In the SDK-only matrix, concurrent attributed extraction aborts in 1/10 processes; serial
attributed extraction passes 10/10 and plain extraction passes 20/20. All observed aborts use
the RoleMap fixture. These small counts do not establish a general crash rate or prove that
structure tags are required. Fresh-process trials continue after a failure to complete the
matrix, but every failed trial remains failed; none is retried or replaced by a passing result.

The fresh native failure occurs in `rolemap-native-w8-trial7`; the SDK-only failure occurs in
`rolemap-attributed-w8-trial1`. Both exit with SIGABRT and the same exception as the retained
original test failure:

```text
NSInvalidArgumentException
*** -[__NSDictionaryM setObject:forKey:]: object cannot be nil (key: NSFont)
PDFSelection.createAttributedStringForCGSelection:scaled:
PDFSelection.attributedStringScaled:
PDFSelection.attributedString
```

The native stack additionally passes through `NativeTextReader.lines`. The SDK-only binary
contains no PDFReflowLib sources, conversion pipeline, EPUB writer or third-party dependency.
This narrows the reproduction to Apple's attributed-extraction path, without identifying the
precise framework ownership/threading fault. Apple's API reference describes the relevant
[PDFSelection attributed string](https://developer.apple.com/documentation/pdfkit/pdfselection/attributedstring);
no undocumented API or exception-swallowing shim is used.

## Runtime policy and regressions

The mitigation recorded here shipped in `58da4de`, the baseline for the later cancellation
work. At that revision, `NativeTextReader` held one static NSLock for its synchronous page-text
extraction. The lock covered plain selections, attributed reads and copying results into value
types. It was released before returning to progress, OCR, graphics or packaging work.
Cancellation was checked before waiting and after acquisition; the lock wait itself was not
cancellable. Concurrent imports traded extraction throughput for serialization. A single
converter retained its page-by-page flow and all attributed formatting.

This cannot coordinate PDFKit calls outside this copy of the library, nor establish safety for
all framework rendering/document operations. These measurements did not qualify full
physical-device concurrency, cancellation latency under contention or interaction with a
host's own PDFKit reader. #21 remains open for the upstream exception and limits beyond queued
cancellation. The public API and conversion/image/resource defaults are unchanged.

Since `ea7ddfd`, acquisition tries the lock immediately and checks cancellation between 50 ms
timed waits when contended, as well as before and after acquisition. A cancelled waiter can
return while another extraction still holds the lock. Each timed wait still blocks its worker
thread, the interval is not a hard latency guarantee, and a PDFKit call already executing cannot
be interrupted. See the [later cancellation evidence](../extraction-cancellation/record.md)
for the regression and results; the historical measurements in this record are unchanged.

Every normal gate lane now runs eight fresh native processes: two fixtures, one/eight workers,
50 iterations per worker, two trials (1,800 verified iterations). The raw SDK control is an
explicit diagnostic, because it can reproduce the upstream abort.

Seven Python tests enforce incomplete/malformed receipt rejection, nonzero exit/signal handling,
retained failure logs, timeout termination/reaping, output-directory protection and independent
fixture offsets/stream lengths. A public Swift API test overlaps four different fixture
conversions and one cancelled conversion, checking separate content/metadata, bold/italic
styles, images, ordered progress, completed-file visibility and staging cleanup.

## Complete corpus and platform checks

`scripts/check-all.sh --corpus` passes 138 Swift tests, 69 Python tests, the eight-process native
smoke gate, the existing fixture/policy checks, the unchanged structure-index memory gate, and
221 content checks on 54 reviewed pages across eight complete PDFs. The same 138 Swift tests
pass on iOS 27 Simulator. This does not qualify physical iPhone/iPad memory or concurrency.

The collector compares all 2,151 source pages' EPUB entries against retained `d40fe2f` outputs:
all XHTML text/formatting, source-page anchors, navigation, CSS and 3,922 image files are
byte-identical. Conversion reports, including warnings/counts, are identical after excluding
the destination URL. Package metadata differs only in the conversion identifier and modified
timestamp. Output equality is stronger than the reviewed content checks for this change, but
still does not claim that every baseline page has correct fidelity.

All existing per-book RSS limits pass. The FAA structure-index probe peaks at 119,947,264 bytes,
below its unchanged 192 MiB gate. Full Warren and NOAA remain explicit exclusions because of
the known default output ceiling; they were not qualified here.

The full-corpus run's time/RSS values, with its retained baseline, are in
`corpus-comparison.json`. That run is slower than the older baseline. Timing investigation uses
fresh alternating baseline/current processes rather than attributing that difference to the
lock from two runs at different times; see the paired results below.

## Fresh paired timing check

`paired-timing.py` builds its evidence from eight fresh complete-document conversions in
before/after/after/before order for each book. The baseline executable is rebuilt from the exact
`d40fe2f` archive with the same full Xcode and pinned ZIPFoundation version. The current executable
is the one used by the full corpus gate. All paired outputs also match entry-for-entry after
normalizing only the package's publication ID/timestamp.

| Complete book | Baseline seconds (two runs) | Serialized reader seconds (two runs) |
| --- | --- | --- |
| The Fed Explained, 135 pages | 12.02, 15.23 | 7.16, 12.35 |
| FAA handbook, 522 pages | 42.09, 37.72 | 37.86, 38.02 |

The paired observations do not reproduce a consistent single-conversion slowdown. They also
show substantial run-to-run variation, especially for Fed, so no speedup, equivalence margin
or general latency distribution is claimed. Concurrent extraction is intentionally serialized;
these sequential full-book timings do not qualify parallel-import throughput. The older
full-corpus timing difference remains recorded rather than overwritten by this diagnostic.
`timing-summary.json` and `paired-timing.tar.gz` retain exact timing/CPU/RSS, build/binary/source
identities, complete conversion reports, progress logs and the alternating run order.

Reproduce with separate baseline/current release executables and a new output directory:

```sh
python3 measurements/pdfkit-concurrency/paired-timing.py \
  --before /path/to/baseline/pdf-reflow --after /path/to/current/pdf-reflow \
  --output /tmp/paired-timing-new
```

## Reproduction and retained artifacts

The [standalone Apple reproduction bundle](apple-reproducer.zip) contains the probe, both tiny
original fixtures, MIT license, exact failing SDK stderr and build/run instructions. It requires
full Xcode; it does not require downloading any corpus PDF or library dependency.

A fresh rebuild from this bundle on 2026-09-15, same host/OS/Xcode identity as above, reproduced
the identical exception and stack on the 3rd of 5 concurrent-attributed trials; the full run is
retained at `fresh-crash-2026-09-15.stderr.log.gz`. [`report.md`](report.md), built from the
bundle and this fresh reproduction, was filed with Apple as **FB24796210** on 2026-09-15; see
`submission.json`. No Apple diagnosis or resolution is available yet.

From the repository, with full Xcode selected:

```sh
python3 tools/check_pdfkit_concurrency.py --sdk-only --workers 1 8 \
  --iterations 1000 --trials 5 --output /tmp/pdfkit-sdk-new
python3 tools/check_pdfkit_concurrency.py --modes native --workers 8 \
  --iterations 1000 --trials 10 --output /tmp/native-new
python3 tools/check_pdfkit_concurrency.py --modes native --workers 0 1 8 \
  --optimization debug --iterations 1000 --trials 3 --output /tmp/native-debug-new
scripts/check-all.sh --corpus
```

- `campaign-summary.json` records denominators, outcomes and verified completed iterations.
- `campaigns.tar.gz` retains every trial's stdout/stderr/receipt, build logs, fixture PDFs,
  executable hashes, and exact producer source versions. Binaries are not committed.
- `corpus-receipts.tar.gz` retains before/after result, report, progress, content-check and
  EPUBCheck evidence for all eight complete documents; large corpus PDFs/EPUBs stay uncommitted.
- `full-gate.log.gz` and `ios-tests.log.gz` retain the platform checks.
- `identity.json` pins the current implementation/tests/collector and archive identities.
- `collect.py` verifies raw campaign identities and strict EPUB entry/report equality before
  writing the receipt archives. Only dynamic publication ID/timestamp/destination are excluded.
