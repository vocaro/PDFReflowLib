# Memory regression testing

The real-document runner verifies the input's byte count and SHA-256 before conversion. It
launches the release converter in a fresh process and obtains that child's peak resident set
size (RSS) from `wait4`. The measurement excludes the parent, build, structural checks and
EPUBCheck; unrelated earlier children cannot contaminate it. This kernel high-water mark
captures transient spikes between samples. Separately, 100 ms samples record the converter's
physical footprint and progress stage; the sampled peak can miss short spikes.

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
python3 tools/evaluate-real-document.py --case faa-phak-8083-25c \
    --pdf corpus/cache/faa-h-8083-25c.pdf --converter .build/release/pdf-reflow \
    --output /tmp/phak-memory-run --epubcheck /opt/homebrew/bin/epubcheck
```

The output directory must be new. Override the ceiling with `--max-peak-rss-mib 1024`, or change
the checked-in manifest to set the team's agreed budget. An exceeded ceiling returns nonzero
while retaining the EPUB, result, conversion report and memory trace for diagnosis. Progress
checks enforce monotonic work percentages, valid page bounds and a final completion event.
Progress measures completed work, not elapsed time or an ETA. `--timeout` bounds the child run;
forced termination can leave a staging directory, unlike cooperative library cancellation.

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
source verification and isolation from an earlier child's high-water mark:

```sh
python3 -m unittest discover -s tools -p 'test_*.py' -v
```

## Isolating PDFKit growth

`tools/probe-pdfkit-memory.swift` imports only Apple SDKs. It repeatedly opens each source page
in an autorelease pool and discards every extracted object. `plain` reads selection strings,
`line` reads each line's attributed string, and `page` reads the page's attributed string.
Run modes in separate processes. Output records peak RSS and physical footprint after each pass.

```sh
xcrun swiftc -O tools/probe-pdfkit-memory.swift -o /tmp/pdfkit-memory-probe
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

## Page retention strategies

`measurements/page-retention/run.py` compares the pre-change converter with the current one
on complete corpus books; during the measurement the candidate also ran under each retention
strategy through `PDFREFLOW_PAGE_RETENTION`, which no longer exists, so a current build always
measures the spill store and `--strategy` labels only the run. Every candidate output must be
byte-identical to the baseline output apart from the package identifier and timestamp, and
its conversion report must match apart from the output path; `identity.py` performs that
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
strategies, apply `measurements/page-retention/measured-strategies.patch` to the sources it
names and rebuild.

Package tests cannot run on a physical device because they have no host application, so
`measurements/page-retention/device/host/measure.sh` builds a minimal host app that links the
library, stages a corpus source into its bundle, runs the public converter with the strategy
in its environment, and samples the process footprint on the phone. It needs an Xcode account
for the signing team, an unlocked device in Developer Mode, and an iOS 27 scene-lifecycle host,
which the app provides. Results and the retained device logs are in the same record.

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
