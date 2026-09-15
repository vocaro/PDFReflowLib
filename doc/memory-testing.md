# Memory regression testing

The real-document runner verifies the input's byte count and SHA-256 before conversion. It
launches the release converter in a fresh process and obtains that child's peak resident set
size (RSS) from `wait4`. The measurement excludes the parent, build, structural checks and
EPUBCheck; unrelated earlier children cannot contaminate it. This kernel high-water mark
captures transient spikes between samples. Separately, 100 ms samples record the converter's
physical footprint and progress stage; the sampled peak can miss short spikes.

`Corpus/manifest.json` supplies each document's default ceiling. The FAA handbook's initial
macOS arm64 ceiling is **1,280 MiB peak RSS**. This prevents a return to the measured multi-GB
behavior; it is not a mobile shipping budget. OS/framework versions, hardware and release/debug
builds affect memory. Establish separate baselines on physical iPhone and iPad before claiming
a device limit. RSS also includes resident shared mappings; physical footprint helps explain
it but is a different metric. Apple services such as OCR can use memory outside this process.

From the package directory, with a full Xcode selected:

```sh
swift build -c release
python3 Tools/evaluate-real-document.py --case faa-phak-8083-25c \
    --pdf /path/to/faa-h-8083-25c.pdf --converter .build/release/pdf-reflow \
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
or committed artifacts; supply the exact pinned PDF separately. There are no automatic downloads.

The repository's `scripts/check-pdf-reflow-memory.sh` builds and runs this gate.
`check-all.sh` includes it outside `--fast` when the local handbook exists; source absence is
printed as a skip. Invoking the dedicated script with a missing source fails. Set
`PDFREFLOW_REAL_PDF` to use another location for the same pinned bytes.

The fast instrumentation controls exercise real child allocations above/below the ceiling,
source verification and isolation from an earlier child's high-water mark:

```sh
python3 -m unittest discover -s Tools -p 'test_*.py' -v
```

## Isolating PDFKit growth

`Tools/probe-pdfkit-memory.swift` imports only Apple SDKs. It repeatedly opens each source page
in an autorelease pool and discards every extracted object. `plain` reads selection strings,
`line` reads each line's attributed string, and `page` reads the page's attributed string.
Run modes in separate processes. Output records peak RSS and physical footprint after each pass.

```sh
xcrun swiftc -O Tools/probe-pdfkit-memory.swift -o /tmp/pdfkit-memory-probe
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
