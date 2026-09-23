# Memory regression testing

The real-document runner verifies the input's byte count and SHA-256 before conversion. It
launches the release converter in a fresh process and obtains that child's peak resident set
size (RSS) from `wait4`. The measurement excludes the parent, build, structural checks and
EPUBCheck; unrelated earlier children cannot contaminate it. This kernel high-water mark
captures transient spikes between samples. Separately, 100 ms samples record the converter's
physical footprint and progress stage; the sampled peak can miss short spikes. Each sample also
carries `ri_lifetime_max_phys_footprint`, the kernel's own high-water mark of the footprint
ledger, recorded as `converterLifetimeMaxPhysicalFootprintBytes`. Unlike the sampled footprint it
cannot miss a spike, and the ledger counts compressed pages that a resident size does not — but it
counts them at their compressed size, so it bounds nothing. It is corroborating evidence; the
ceilings are peak RSS ceilings and nothing gates on it
([decision 0009](decisions/0009-an-unmeasured-ceiling-is-not-a-failure.md)).

Memory is measured on the whole machine, so the machine is part of the measurement. Under
pressure macOS compresses and pages out resident memory, which can only lower a peak RSS. The
evaluator samples `kern.memorystatus_vm_pressure_level` while the converter runs and reports one
of three outcomes: `exceeded` when the peak is above the ceiling, which pressure cannot explain
away; `passed` when the peak is inside it and pressure stayed normal; and `notMeasured` when the
peak is inside it but pressure rose, which neither passes the ceiling nor fails it. An
unmeasured ceiling exits 3, apart from a failure's 1, so that a loaded host is not investigated
as a regression. Before settling for that the evaluator waits up to `--settle-seconds` (default
60) for the host to go quiet ahead of each conversion, and spends a second of `--memory-attempts`
(default 2) conversions on a spoiled measurement — but only once the host has settled, so a
machine that stays loaded costs one conversion, not several. Every attempt is kept, in
`conversionAttempts` and in `memory-samples-N.json`. None of this makes a busy machine a fit
place to measure memory: build other projects elsewhere, or afterwards.

What the gate cannot see is stated here rather than carried as a defect. A heavy-OCR book's peak
RSS moves 50–135 MiB between two runs of one binary on one host, because which pages the
recognizer retries, and what Vision holds for them, differs from run to run (#173). A regression
smaller than that spread is invisible to this gate whatever it measures — peak RSS today, or the
footprint high-water mark should the ceilings move onto it (#244) — and the ceilings are set with
that in mind: they catch a return to the measured multi-gigabyte behaviour, not a creep of a few
per cent. The owner accepted this as the gate's limit on 2026-09-23 (#244).

`corpus/manifest.json` supplies each document's default ceiling. The FAA handbook's initial
macOS arm64 ceiling is **1,280 MiB peak RSS**. This prevents a return to the measured multi-GB
behavior; it is not a mobile shipping budget. OS/framework versions, hardware and release/debug
builds affect memory. Establish separate baselines on physical iPhone and iPad before claiming
a device limit. RSS also includes resident shared mappings; physical footprint helps explain
it but is a different metric. Apple services such as OCR can use memory outside this process.

From the package directory, with a full Xcode selected:

```sh
python3 tools/fetch_corpus.py --case faa-phak-8083-25c
swift build -c release
python3 tools/evaluate_real_document.py --case faa-phak-8083-25c \
    --pdf corpus/cache/faa-h-8083-25c.pdf --converter .build/release/pdf-reflow \
    --output /tmp/phak-memory-run --epubcheck /opt/homebrew/bin/epubcheck
```

The output directory must be new. Override the ceiling with `--max-peak-rss-mib 1024`, or change
the checked-in manifest to set the team's agreed budget. An exceeded ceiling returns 1, and a
ceiling host pressure left unmeasured returns 3; both retain the EPUB, result, conversion report
and memory trace for diagnosis. Progress checks enforce monotonic work percentages, valid page
bounds and a final completion event. Progress measures completed work, not elapsed time or an
ETA. `--timeout` bounds the child run; forced termination can leave a staging directory, unlike
cooperative library cancellation.

The memory ceiling is a regression gate, not a runtime allocation limiter. A successful package
and memory result does not mean the book has passed fidelity review. The FAA case explicitly
records known column-order and raster-sizing defects. Large PDF/EPUB files are not test resources
or committed artifacts. The explicit corpus fetcher verifies sources into `corpus/cache/`;
tests never download them automatically.

The repository's `scripts/check-pdf-reflow-memory.sh` builds and runs this gate.
`check-all.sh` includes it outside `--fast` when the local handbook exists; source absence is
printed as a skip. Invoking the dedicated script with a missing source fails. Set
`PDFREFLOW_REAL_PDF` to use another location for the same pinned bytes.

The fast instrumentation controls exercise real child allocations above/below the ceiling,
source verification, isolation from an earlier child's high-water mark, and each pressure
outcome with its settle-and-retry:

```sh
python3 -m unittest discover -s tools -p 'test_*.py' -v
```

## Isolating PDFKit growth

`tools/probes/probe-pdfkit-memory.swift` imports only Apple SDKs. It repeatedly opens each source page
in an autorelease pool and discards every extracted object. `plain` reads selection strings,
`line` reads each line's attributed string, and `page` reads the page's attributed string. `text-line`
reads only lines with text other than attachments, as the library does, and `union` reads those
lines in one request per page (#4).
Run modes in separate processes. Output records peak RSS and physical footprint after each pass.

```sh
xcrun swiftc -O tools/probes/probe-pdfkit-memory.swift -o /tmp/pdfkit-memory-probe
/tmp/pdfkit-memory-probe /path/to/faa-h-8083-25c.pdf plain 3
/tmp/pdfkit-memory-probe /path/to/faa-h-8083-25c.pdf page 3
MallocStackLogging=1 leaks --atExit -- \
    /tmp/pdfkit-memory-probe /path/to/faa-h-8083-25c.pdf page 1
```

Leak inspection may require a debug-signed temporary probe with `com.apple.security.get-task-allow`;
this entitlement never belongs in the distributed library. Allocation-stack logging changes
memory and timing, so those runs diagnose ownership and do not set performance baselines.
A growing footprint alone does not prove a leak. Compare plain/attributed modes, object
lifetimes and unreachable allocations before attributing a defect to PDFKit.

Apple report **FB24783799** tracks the framework-path leak. The
[submission evidence](../measurements/apple-feedback-pdfkit/record.md) includes the standalone
reproducer, fresh plain/attributed measurements and full allocation diagnostics. The issue remains
unresolved; a submitted report is not an Apple-confirmed diagnosis.

## Repeated conversions in one process

An app that converts several PDFs in one process keeps every attributed string PDFKit leaked
while doing so. `tools/repeated_conversions/measure.sh` builds a small harness that
converts the given PDFs through the public API a number of times in one process, with pinned
packaging, and prints the physical footprint, peak RSS and default malloc zone after every
conversion. `LEAKS=1` adds a `leaks` count after every round on the Mac; `SIMULATOR=<udid>` runs
it in a booted iOS Simulator instead.

```sh
LEAKS=1 tools/repeated_conversions/measure.sh 10 \
    corpus/cache/THM-Close-Out-Report-and-Exec-Summ-for-STI-Review.pdf \
    corpus/cache/the-fed-explained.pdf corpus/cache/November-December2012.pdf
```

Every leaked allocation is an attributed string from `PDFSelection.attributedString`, which
`NativeTextReader` requests for a page's styled lines. It requests them as one union selection
per page and slices each line out, which leaves about a twelfth of the leaked objects of one
request per line (135-page Fed: about 22,900 objects per conversion before, about 1,760 after),
with byte-identical output on the FAA corpus source. What is left is the page's text itself,
which only Apple can release (FB24783799). The physical footprint after a conversion swings by
hundreds of MiB with the allocator's reclaim of freed pages, so it cannot bound the growth; the
leak count and the default zone can. `tools/check_repeated_conversions.py` gates the leaked
objects each Fed conversion adds, in a process of its own; the package tests run suites in
parallel, so they check the single request per page instead of measuring memory. See the
[record](../measurements/pdfkit-repeated-conversions/record.md).

## Page retention strategies

`measurements/page-retention/run.py` compares the pre-change converter with the current one
on complete corpus books; during the measurement the candidate also ran under each retention
strategy through `PDFREFLOW_PAGE_RETENTION`, which no longer exists, so a current build always
measures the spill store and `--strategy` labels only the run. Every candidate output must be
byte-identical to the baseline output apart from the package identifier and timestamp, and
its conversion report must match apart from the output path; `tools/epub_identity.py` performs that
check and has negative controls. Each run records the evaluator's peak RSS, sampled physical
footprint, CPU and wall time, plus the peak size of the run's own directory, which includes
staged images and spilled pages. Explicit image policies keep both binaries on the same
options regardless of library defaults.

```sh
git worktree add /tmp/pdfreflow-baseline <pre-change commit>
(cd /tmp/pdfreflow-baseline && swift build -c release)
swift build -c release
python3 measurements/page-retention/run.py \
    --baseline /tmp/pdfreflow-baseline/.build/release/pdf-reflow \
    --candidate .build/release/pdf-reflow --output /tmp/retention \
    --epubcheck /opt/homebrew/bin/epubcheck
```

The output directory must be new. Output EPUBs are deleted after comparison unless
`--keep-epubs` is given, because four NOAA-sized archives do not fit comfortably beside the
build directories. Repeat `--case` or `--strategy` to narrow a run. To re-measure the retired
strategies, apply `measurements/page-retention/measured-strategies.patch` as of commit a28fb09 (the patch was removed from the tree afterwards) to the sources it
names and rebuild.

Package tests cannot run on a physical device because they have no host application, so
`measurements/page-retention/device/host/measure.sh` builds a minimal host app that links the
library, stages a corpus source into its bundle, runs the public converter with the strategy
in its environment, and samples the process footprint on the phone. It needs an Xcode account
for the signing team, an unlocked device in Developer Mode, and an iOS 27 scene-lifecycle host,
which the app provides. Results and the retained device logs are in the same record.

## Structure-tree text-layout cost

PDFKit loads a tagged document's entire structure tree the first time it lays out text on
a page that carries `/StructParents`. On the FAA handbook that costs about 489 MiB of
transient small allocations once per process, on the Mac and on an iPhone, and leaves
about 204 MiB of fragmented allocator pages resident. Hiding the tree from PDFKit changes
extracted text and is rejected. Apple report **FB24798533** tracks it. See the
[structure-tree investigation](../measurements/pdfkit-structure-tree/record.md), which
retains the standalone reproducer and the submitted report text.

## Output storage budget

`ConversionOptions.maximumOutputBytes` defaults to 512 MiB. It bounds image bytes during
reconstruction and total EPUB entry bytes before ZIP compression during packaging. It is
separate from peak RAM and the corpus RSS gates. This initial configurable engineering budget
is not an EPUB, Apple SDK or measured hardware limit. Clients may set another positive budget or `Int64.max` to effectively disable it;
raising it does not qualify memory, readability or reader performance. The
[Warren encoding experiment](../measurements/warren-image-encoding/record.md) uses a 2 GiB
override to measure a complete book while leaving the production default unchanged.

`maximumEPUBBytes` independently caps the finished archive, including ZIP overhead, before
publication. It defaults to nil and does not bound intermediate disk use or RAM. Reference
inclusion and page/region encoding are also client options; see [the policy guide](conversion-options.md).
