# Current raster qualification (#28)

> Qualification complete for the named Mac, iPhone and iPad environments. Defaults remain unchanged.
> All outcomes, including the iPhone storage-cap failure and interrupted iPad attempt, are retained below.

2026-09-24; library revision `1ec71183`. No library default or production implementation changes.
This record re-verifies the 2026-09-16 study from abandoned-branch commit `dc81a78` on current
`main`, following [decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md).
That branch was recorded by an `ours` merge without bringing its content into the tree.
The historical study's book tables cover
120/180/240 DPI; its recommendation paragraph claiming book passes at 300 DPI is not supported
by those tables. Its “at most one” fixed-DPI JPEG phrase difference is also contradicted by
its own raw data (up to three). Its old defaults, OCR counts and budget failures do not describe
today's build. The [historical audit](historical-audit.json) records the counterexamples and
archived book
settings; `tools/raster_qualification/audit_previous.py` regenerates it from the retained Git objects. The old results
are not treated as current qualification.

## Scope and decisions

Keep 180 DPI, automatic JPEG quality 0.90 and the 12-million-pixel ceiling as the defaults.
A requested DPI is not a minimum: the ceiling can reduce it independently for each raster.
Lower DPI changes recognition as well as image size. Higher DPI does not monotonically improve
recognition. Successful conversion and reference-image correlation do not establish reading accuracy.

The current page sweep supports trying JPEG 0.75–0.90 for tinted scans when lossy encoding is
acceptable. Keep PNG for fine colored labels, clean tables and equations. Do not extend the
scan recommendation to all artwork or interpret the encoder quality as a fidelity percentage.
150 DPI is a measured storage trial for body-size scan text; it does not preserve tiny notes as
well as 180/240/300. Neither 96 nor 120 DPI is a general recommendation for small scan print.

Device qualification below is limited to the named devices, OS build, foreground measurement
host and sources. The pixel ceiling bounds one raster, not all process allocations. It is not
a shipping RAM limit, a jetsam guarantee, or evidence for older/lower-memory hardware.

## Current page sweep

The source-reviewed targets are the same 17 pages from eleven English-language documents as the historical
study. `tools/raster_sweep.py` compiles the current production rasterizer, renders each complete
page and reviewed region at 96/120/150/180/240/300 DPI, and encodes the same raster as PNG and
JPEG 0.60/0.75/0.85/0.90/0.95. Every input is checked against the corpus byte count and SHA-256.
All 1,224 encoded images decode at the recorded size and below the 12-million-pixel ceiling.
All 612 region recognition requests succeeded. The current driver records phrase recovery and
same-raster pixel error; the retired glyph/appearance checkers are not restored as current gates.

[Identity](sweep/identity.json), [aggregate results](sweep/results-summary.json),
[per-target counts](sweep/per-target-summary.json) and [generated tables](sweep/summary.md)
retain the measured settings, source hashes, phrase-recovery counts and byte counts.
The [capture digest manifest](sweep/capture-digests.json) identifies the full results, exact
capture targets, producer script and image sheets kept outside the repository under
`/tmp/pdfreflow-raster28-evidence/sweep`, following [decision 0006](../../doc/decisions/0006-measurements-are-records.md).
These raw files are retained; the current driver subsequently fixed half-percent filename rounding
to agree with Swift, which does not affect these five integer-percent quality settings. The Mac measurements used macOS 27 with functioning Vision;
first-request model setup and other host activity affect timing, so these probe timings are
not conversion or device performance budgets.

Relative to 180-DPI PNG, the total full-page bytes are 0.373× at 96, 0.527× at 120, 0.729× at
150, 1.489× at 240, and 1.930× at 300. The Warren page-890 tiny-note region recovers 0/0/3/5/6/8
of nine reviewed phrases at those six resolutions; page-100 body prose recovers 0/4/7/6/7/7
of seven. The typewritten Blue Book table recovers all 21 phrases at every PNG resolution.
FAA's colored label recovers 3/3/1/3/3/3 phrases: scale-sensitive OCR is not a monotonic quality
metric. At fixed DPI, a JPEG result differs from PNG by up to three recovered phrases in this
run, in either direction. This probe recognizes the encoded region as a legibility proxy;
production OCR reads the raster before output encoding, so these JPEG differences do not
measure production OCR drift. The old study's “at most one” claim is unsupported even by its own archived raw rows; those also differ by up to three.

At 180 DPI, JPEG 0.75 uses 3,178,075 bytes over the six scan pages, versus 3,876,899 at
0.90 (18% less) and 5,998,092 for PNG. The clean table page uses 230,401 bytes as PNG versus
309,940 at JPEG 0.75; the two equation pages similarly total 445,345 versus 486,017. A scan
saving does not transfer to clean regions.

The Warren DPI sheet (`review/warren-890-dpi-comparison.png` in the external capture bundle) shows broken small strokes at
96/120 and clearer fine detail at 240/300. The FAA encoding sheet (`review/faa-121-encoding-comparison.png` in that bundle)
shows visible ringing and block boundaries at 0.60 and some edge damage at 0.75. A source crop
rendered independently by Poppler is included in each sheet. Equal-area magnification exposes
artifacts; it is not a user study at ordinary reading distance.

## Physical-device method

`tools/raster_qualification/device/host/RasterHost` links the public library in a Release iOS app. One fresh process runs
one complete conversion. The source is hashed in the app before conversion; settings and source
identity are checked again after copying results back. The host keeps the EPUB, full conversion
report, and 100 ms memory samples. RSS is the process's kernel high-water mark, while physical
footprint and purgeable resident memory are sampled and can miss short spikes. RSS includes
startup and input hashing. Footprint includes the conversion and serialization of its report.
Available memory is the OS estimate from `os_proc_available_memory`, not total physical RAM
or a measured jetsam threshold. Purgeable resident bytes are not an attribution to a particular
framework or IOSurface owner.
Separate Apple-service memory is outside these process metrics. The host does not instrument OS
memory-warning notifications or jetsam thresholds; runs are foreground tests on available devices,
not controlled system-memory-pressure experiments. Fresh app processes do not reset Vision
service/model caches, so the elapsed times are observations rather than cold-start guarantees.

The runner checks source-page order and the current reviewed content contracts. `tools/raster_qualification/summarize.py`
also runs EPUBCheck, decodes every output image, records its identity and dimensions, and compares
page text against the same book's 180-DPI output. Raw reference-image failures are retained.
A separately labeled diagnostic rescales images to 180 DPI before the content checker; this
explains scale failures but does not replace the raw gate or qualify fine detail. That diagnostic
is only used on ordinary book runs below the ceiling, never the ceiling stress case.

All normal runs retain the default 512 MiB entry budget, automatic OCR and automatic image
encoding. The explicitly labeled larger-budget Warren experiment changes only the entry cap;
its result cannot count as default-budget success. A fixed package identifier and modification date remove packaging-only noise.
Failed default runs are retained separately from any explicit-budget experiment; no failed
conversion or content check is relabeled as a default success.

## Whole-book observations

The historical claim that changing DPI leaves all image, OCR and reflow counts unchanged is
not true of the current build. CDC now recognizes 34 pages rather than the historical nine;
96/150/300 DPI changes normalized text on 29/30/30 pages against 180. At 300 DPI, page 5 changes
`THROUGH` to `THROUIGH` and page 13 changes `OKAY` to `OKДY`. Other words improve. Fed retains
one OCR page and changes only that page (7) at 96 and 300; its 150-DPI text matches 180.
These are observed differences, not estimates of which whole-book transcription is more accurate.

Blue Book recognizes 55/56/57/57 pages at 96/150/180/300 DPI, reflows 311/311/307/310, and
writes 417/444/455/444 images. Its 300-DPI EPUB is 127.7 MiB versus 192.6 at 180 despite higher
resolution. All 444 images at 300 are PNG; 180 writes 345 PNG and 110 JPEG. On physical page 57,
the source is a one-bit 3,279×2,544 scan at 300 DPI (`pdfimages -f 57 -l 57 -list`). The 300-DPI
output preserves those dimensions and only black/white pixels; its 180-DPI JPEG has 256 gray
levels. Matching the scan's native grid can therefore compress better than resampling it.
Higher DPI does not reliably predict larger final files under automatic encoding.

## iPhone results

Physical iPhone 17 Pro Max (`iPhone18,2`), iOS 27.0 build `24A435`, 12,263,424,000 physical
memory bytes. [Hardware identity](iphone-identity.json). The initial sweep's binary and
host-source hashes are in [the receipt](iphone/books/identity.json); adding the stress PDF
resource re-signs the executable but changes no host or library code. Every corpus input is
manifest-pinned. The first four books cover 978 source pages per setting.

All 16 conversions at 96/150/180/300 completed within the unchanged output budget and passed
EPUBCheck. Every 180-DPI content contract passed. The six raw non-180 failures are the CDC and
Wallace source-image references; all six pass the separate normalization diagnostic. No text,
math, page-order or other reviewed contract fails. This remains sampled content coverage.
The [complete table](iphone/books/table.md) and [comparison](iphone/books/summary.json)
retain text drift, warnings, image counts, peak memory and timings. Full reports, source receipts, 100 ms memory samples and image identities remain in the
external capture bundle; the [digest manifest](iphone/books/capture-digests.json) identifies its archives.

A same-setting repeat of CDC and Blue Book produces byte-identical EPUBs and identical reports
apart from the destination URL ([hash comparison](iphone/repeat/repeat-comparison.json),
[measurements](iphone/repeat/summary.json)). Host and library source are identical; the
signed executable changed only when the stress PDF was added to the app bundle. This rules out
ordinary recognition drift in these particular controls, not in every future run. Blue Book's
sampled footprint still moves from 340.9 to 357.0 MiB with identical output, so small memory
differences between settings are not resolved by these one-run measurements.

The binding-ceiling experiment requests 600 DPI, forces OCR and source-page references, and
completes both source pages at every ceiling. Every result passes EPUBCheck and its two
image-presence checks. All three output images are PNG. Actual largest raster sizes confirm that
the ceilings bind, unlike ordinary letter pages through 300 DPI:

| Ceiling | Largest raster pixels | Seconds | Peak RSS MiB | Sampled footprint MiB |
| ---: | ---: | ---: | ---: | ---: |
| 6 million | 5,997,420 | 1.61 | 185.7 | 237.3 |
| 12 million | 11,999,086 | 2.42 | 263.2 | 320.3 |
| 24 million | 23,999,117 | 3.40 | 407.9 | 386.4 |
| 48 million | 47,996,344 | 6.19 | 709.4 | 647.7 |

The [6M](iphone/ceiling-6000000/summary.json),
[12M](iphone/ceiling-12000000/summary.json),
[24M](iphone/ceiling-24000000/summary.json) and
[48M](iphone/ceiling-48000000/summary.json) summaries have adjacent identity and capture-digest manifests. Sampled purgeable resident bytes are zero throughout these iOS runs; that
counter does not prove that Vision has no IOSurface cache or external service allocation.
The smallest process-available-memory sample is still about 2.66 GiB at 48M, so successful
48M conversion on this phone is not evidence for a low-memory shipping budget.

Warren fails at the default entry cap after 551.9 seconds with `resourceLimit("EPUB total size")`,
337.7 MiB peak RSS and 307.3 MiB sampled footprint. No EPUB is published. These memory figures
are for a failed conversion and do not establish a completed-book budget.

With an explicitly declared 4 GiB entry cap, the same Warren source completes all 920 pages in
544.1 seconds, with 342.9 MiB peak RSS and 297.5 MiB sampled footprint. It recognizes 17 pages,
reflows 905 and writes 931 images. The 531,873,555-byte EPUB passes EPUBCheck and the current
reviewed content contract. Expanded entries total 536,989,648 bytes: only 118,736 bytes over
the default 512 MiB entry cap, although the final ZIP itself is below 512 MiB. That is a storage
cap distinction, not a raster-memory failure. The 4 GiB allowance is experimental; this does not
change or recommend a default cap. [Comparison](iphone/warren-4g/summary.json) and
[capture digests](iphone/warren-4g/capture-digests.json) retain the explicit option.

The first host-side inspection rejected that retained EPUB at its own default expanded-byte
bound. The checker was rerun on the same output with an explicit 4 GiB inspection bound;
conversion was not repeated and the inspection exception is recorded in the results.

NOAA completes all 1,834 pages at the defaults in 166.4 seconds: 227.9 MiB EPUB, 476.3 MiB peak
RSS and 247.1 MiB sampled footprint. Its current content contract and EPUBCheck pass. Together
with FAA and the failed Warren run, the [large-book comparison](iphone/large-defaults/summary.json)
and [capture digests](iphone/large-defaults/capture-digests.json) preserve the outcomes without increasing
the default budget.

The full FAA handbook at default 180 DPI/12M completes in 61.6 seconds with 795.0 MiB peak RSS
and 532.0 MiB sampled footprint, passing its current content contract. That exceeds the 12M
stress case because raster buffers are only part of the converter's memory. Do not turn
`maximumRasterPixels × 4` into an application memory estimate.

## iPad results

Physical iPad Air 13-inch (M3), `iPad15,5`, iPadOS 27.0 build `24A435`, 7,993,540,608
physical memory bytes. [Hardware identity](ipad-identity.json). The ordinary book and ceiling
runs use the exact signed executable used for the iPhone ceiling and repeat runs, with identical
host and library source hashes. The first iPhone book sweep predates only the added stress-PDF
resource. Hardware, OS family and framework execution differ; these are two observed environments.

The [initial book table](ipad/books/table.md) records 15 completed conversions and one interrupted
Wallace 150-DPI attempt. The separate [150-DPI control](ipad/wallace150-control/summary.json)
completed in 32.8 seconds. Together they cover the same four books at 96/150/180/300 DPI.
All 16 completed EPUBs pass EPUBCheck. Every 180-DPI content contract passes. As on iPhone,
the six non-180 CDC/Wallace raw reference-image checks fail, and all six pass the separately
reported normalization diagnostic. Every other reviewed contract passes.

The interrupted attempt published only its initial receipt, with no EPUB, final report or
sampled peak. It remained unusually long while CoreDevice listed its PID; Instruments could
not attach, and LLDB obtained no stopped-process backtrace. The console ultimately reported
signal 9. Debugger cleanup may have contributed to termination, and no matching app-crash or
contemporaneous jetsam report was found. Neither an OS-memory-limit explanation nor a library
hang is established. Its [diagnostic record](ipad/interruption.json) remains separate; the
successful control does not turn it into a successful original run or a measured memory peak.

The iPad CDC text changes on 30/30/28 pages at 96/150/300 DPI against its own 180-DPI output;
Blue Book changes on 56/56/57, and Fed on its one OCR page at every alternative DPI. Blue Book
recognizes 55/55/57/57 pages, reflows 311/310/309/309 and writes 416/432/453/439 images at
96/150/180/300. Counts and recognition differ from the iPhone. At identical 180-DPI settings,
CDC, Blue Book and Fed differ between devices on 26, 54 and one text page respectively. These
are [observed differences](ipad/cross-device-books.json), not an accuracy ranking or proof of
which hardware/framework component caused them. Wallace's native-text EPUB is byte-identical
between devices at every DPI, including the separate [150-DPI control](ipad/cross-device-wallace150-control.json).

The [CDC/Blue Book repeats](ipad/repeat/comparison.json) produce byte-identical EPUBs and
identical reports except the destination URL on iPad, as they do on iPhone. These two local
controls are stable even though the cross-device OCR results differ; this does not establish
universal recognition determinism. The [repeat measurements](ipad/repeat/summary.json)
retain memory/timing variation separately from output equality.

The same two-page 600-DPI forced-OCR/reference experiment binds each pixel ceiling:

| Ceiling | Largest raster pixels | Seconds | Peak RSS MiB | Sampled footprint MiB |
| ---: | ---: | ---: | ---: | ---: |
| 6 million | 5,997,420 | 2.19 | 224.5 | 293.6 |
| 12 million | 11,999,086 | 2.31 | 296.2 | 310.6 |
| 24 million | 23,996,821 | 3.78 | 443.7 | 477.7 |
| 48 million | 47,996,344 | 6.68 | 739.3 | 718.9 |

The [6M](ipad/ceiling-6000000/summary.json), [12M](ipad/ceiling-12000000/summary.json),
[24M](ipad/ceiling-24000000/summary.json) and [48M](ipad/ceiling-48000000/summary.json)
outputs all pass EPUBCheck and their image-presence contracts, and all output images fully
decode. Purgeable resident samples remain zero. The minimum available-memory sample at 48M
is about 4.30 GiB; this is not a memory-pressure or jetsam-threshold test. The same limits as
the iPhone experiment apply: foreground named hardware, sparse sampling and external services
unmeasured. Keep 12M as the starting bound and profile the target workload/device; successful
6–48M trials on these devices do not establish that range as universally safe.

The default-budget Warren run completes all 920 pages in 524.9 seconds on iPad, with
408.7 MiB peak RSS and 315.9 MiB sampled footprint. The 531,573,084-byte EPUB's expanded
entries total 536,685,938 bytes, only 184,974 bytes below the default 512 MiB cap. It recognizes
15 pages versus the iPhone's 17 and retains 905 reflowed pages. The iPhone's explicit-budget
output is 303,710 expanded bytes larger and crosses the same cap. This narrow margin and
changed recognition mean that fitting this book is environment-dependent, not a new general
storage guarantee. The default iPhone failure remains a failure.

FAA completes all 522 pages at defaults in 66.5 seconds, with 815.0 MiB peak RSS and
531.6 MiB sampled footprint. NOAA completes all 1,834 pages in 172.0 seconds, producing a
227.5 MiB EPUB with 508.2 MiB peak RSS and 236.5 MiB sampled footprint. Their reviewed content
contracts and EPUBCheck pass; the [large-book summary](ipad/large-defaults/summary.json)
retains all three outcomes, including Warren. As on iPhone, full-book allocations exceed what the raster pixel ceiling alone
predicts; these are measured workloads, not whole-process caps.

The final iPad Warren run with the explicit 4 GiB entry cap completes in 541.6 seconds,
with 373.7 MiB peak RSS and 284.0 MiB sampled footprint. Its EPUB is
[byte-identical to the default-cap iPad output](ipad/warren-budget-comparison.json).
The [run summary](ipad/warren-4g/summary.json) records the explicit budget, passing content
checks and EPUBCheck. At that same explicit budget, the iPhone and iPad outputs differ on
20 text pages and in encoded image bytes ([comparison](ipad/cross-device-warren-4g.json)).
This is observed drift, not a transcription-accuracy verdict.

## Reproduction

With the manifest-pinned corpus already downloaded and full Xcode selected:

```sh
python3 tools/raster_sweep.py --targets tools/raster_qualification/targets.json \
  --output /tmp/new-raster-sweep
python3 tools/raster_qualification/device/build.py \
  --team YOUR_SIGNING_TEAM --derived-data /tmp/raster-device-build \
  --stress-plan /tmp/raster-stress-plan.json
```

The build stages verified sources temporarily and removes them on exit. It does not use a
physical device. Coordinate exclusive device access before the following command; it installs
and launches only `com.vocaro.pdfreflow.rasterhost`, leaving other applications' data alone:

```sh
python3 tools/raster_qualification/device/run.py \
  --device PHYSICAL_UDID \
  --app /tmp/raster-device-build/Build/Products/Release-iphoneos/RasterHost.app \
  --output /tmp/new-device-books \
  --case cdc-zombie-pandemic-2011 --case fed-explained-2021 \
  --case cia-blue-book-14-1955 --case wallace-algebra-2010
python3 tools/raster_qualification/summarize.py /tmp/new-device-books
```

The default sequence is 180, 96, 150, 300 DPI. `--dpi` is repeatable. Run 180 DPI more than once
in separate output directories to measure variability. For a binding ceiling, use the two-page
stress derivative of Blue Book page 74 and FAA page 121, enlarged 3× without changing content:

```sh
python3 tools/raster_qualification/device/run.py \
  --device PHYSICAL_UDID \
  --app /tmp/raster-device-build/Build/Products/Release-iphoneos/RasterHost.app \
  --output /tmp/new-device-ceiling-12m --plan /tmp/raster-stress-plan.json \
  --case raster-ceiling-stress --dpi 600 --pixels 12000000 \
  --ocr always --references always
```

A separate storage experiment can pass `--maximum-output-bytes 4294967296`; this is an
explicit 4 GiB entry cap, not a new default or a recommended device budget. For that output,
pass `--max-uncompressed-bytes 4294967296` to `tools/raster_qualification/summarize.py` as a separate inspection allowance. The original
default-only host source is retained as `device/host-default-budget.swift.gz` in the external
capture bundle to match the early binary receipts.

Repeat at 6, 24 and 48 million pixels in new directories. The stress source's PDF metadata can
change on regeneration; the build records its exact bytes and source parents in the plan. The
runner verifies that identity against both its app bundle and the device's receipt.

Repository device identities omit the unique device UDID; the external captures retain it.
Raw captures are local artifacts, not committed records. `tools/raster_qualification/archive.py`
collects a completed run directory into an external compact archive; `record.py` in the same
tool directory extracts the small summary and capture hashes for the repository. The current
raw device runs are under `/tmp/pdfreflow-raster28-{iphone,ipad}-*`; their archived receipts are
under `/tmp/pdfreflow-raster28-evidence/{iphone,ipad}`. For example:

```sh
python3 tools/raster_qualification/archive.py /tmp/new-device-books /tmp/new-device-capture
python3 tools/raster_qualification/record.py /tmp/new-device-capture /tmp/new-device-record
```

Re-run the commands above if these local temporary artifacts are no longer available.
`tools/raster_qualification/compare.py BASELINE_DIR CANDIDATE_DIR OUTPUT.json` compares completed
runs at identical settings by EPUB hash, normalized page text, report fields and encoded image
bytes. It reports incomplete runs separately and makes no accuracy or causal-attribution claim.

## Validation

- The current sweep produced and independently decoded 1,224 images; all 612 OCR calls succeeded.
- The iPhone completed 25 runs and all 25 EPUBs pass EPUBCheck. One additional default-budget
  Warren run failed and is retained. Six non-180 raw image-reference checks fail; all six pass
  the separately labeled normalization diagnostic. Every other reviewed content check passes.
- The iPad completes 26 conversions, all passing EPUBCheck. One additional Wallace attempt is
  interrupted without a final report; its separately retained control completes. Six raw non-180
  reference-image checks fail and pass the separate normalization diagnostic; other reviewed
  content checks pass. The [iPad decode summary](ipad/image-decode-summary.json) records
  20,874 fully decoded images. Across both devices: 51 completed EPUBs and 40,835 decoded images.
- Release iOS measurement builds pass. The documented staging/build/cleanup procedure was exercised,
  including its executable and 99-library-source build receipt; no source PDFs remain staged.
- The Python tool suite reports 263 passed and one pre-existing skip (no debug test binary to
  list), 264 tests total. Three device-receipt controls reject simulator/unknown hardware, wrong source/settings,
  and a copied result without the matching fresh console result.
- The fractional-quality filename control checks the Python label against the actual Swift probe.
- The same-setting comparator reproduces both known byte-identical iPhone controls and retains
  the interrupted iPad run as skipped, not equal. The relocated build procedure was exercised
  and its library-source hashes match the measurement builds.
- All 19,961 images in the 25 completed iPhone EPUBs decode fully; the
  [decode summary](iphone/image-decode-summary.json) records the counts.
- The compact evidence passes the measurements policy; raw captures remain outside the tree.
- Receipt archive sizes and SHA-256 digests are verified. Production library sources are unchanged;
  no unrelated corpus regeneration or library-default change is part of this work.
