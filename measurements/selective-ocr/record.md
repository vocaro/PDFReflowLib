# Opt-in recognition of image-backed existing text

Bounded work on [#7](https://github.com/vocaro/PDFReflowLib/issues/7), baseline
`77123fec523b871b5f171788faa940734a22d7fe`, 2026-09-15, macOS 27.0 (26A428),
Xcode 27.0 (27A266a), arm64. **Issue #7 remains open.** Fresh recognition fixes the
checked inherited-error span but also introduces other errors on that same source page.
This is a client-selectable retry policy, not a claim of improved whole-page accuracy.

## Policy

`ConversionOptions.OCRPolicy.automaticIncludingImageBackedText` includes normal automatic
OCR and additionally retries existing text over a detected graphic exceeding 75% of page
area. It shares the exact existing `unverifiedTextLayer` signal. The CLI exposes it as
`--ocr image-backed`, alongside `automatic`, `always` and `never`; `--no-ocr` remains supported.
Defaults and resource budgets are unchanged.

Selected pages replace their native text with Vision transcription. No spelling dictionary,
confidence threshold or selection between old/new words is added. Ordinary native pages and
small illustrations retain their extraction and styles. Large valid illustrations can also
be selected; cropped/tiled scans can be missed. Unsupported and rotated pages retain image
fallback. Empty recognition retains a required source image even when references are disabled.
Fresh text reports `ocrUsed` and carries a source reference by default. This does not certify
transcription, table cells, numerical values, heading detection or reading order.

## Source-derived acceptance and limitations

`measure.py` verifies the full Warren source SHA-256
`341cc3471750c9c3be68b95a34b52f6cbdc86c4392427a8483ee1c6bc53cfc19`, then creates a
local development derivative from physical pages **1, 7, 21, 30, 50, 100, 890, 910, 920**,
followed by all three original `prose.pdf` fixture pages. The twelve-page derivative retains
source resources and is not a full-book workload. Its identity and native control identity
are recorded in [results.json](results.json).

The independently rendered [physical page 50](source-page-50.png) visibly reads “his known
contacts with the Soviet Embassy”. Automatic OCR retains `bis known contacts witb tbe Soviet
Embassy` on derivative page 5 and warns `unverifiedTextLayer`. Both selective and forced OCR
recover the checked source phrase exactly; the measurement enforces it without deriving
expected text from converter output. Both also preserve the entire source-page reference.

This local improvement does **not** establish that the replacement is better overall. On the
same page, fresh OCR emits `varions` for “various” and `Jack Kuby` for “Jack Ruby”, whereas
the inherited layer spells those words correctly. It also loses the `self.` continuation
after `him-`. Page 910 still contains unreliable names and numerical references. Exact page
text for every variant is retained in the receipts. No whole-page/book error rate was measured,
and these failures are not promoted into passing transcription expectations.

All policies retain ten reflowed pages; the two blank Warren pages remain image-only.
Automatic recognizes derivative pages 1 and 9; selective recognizes all nine Warren pages;
forced recognition processes all twelve. Automatic and selective native-control pages 10–12
are identical in text, scripts, heading/paragraph semantics and image references. The nine
Warren full-page images have identical SHA-256 values across policies. These image checks
cover reference retention, not OCR or diagram reconstruction accuracy.

## Measured tradeoffs

Sequential fresh converter processes after the corpus gate, with the platform OCR service
already exercised, default 180 DPI, PNG, automatic references and unchanged byte/pixel limits:

| Policy | OCR pages | Seconds | Peak converter RSS bytes | EPUB bytes | Images |
| --- | ---: | ---: | ---: | ---: | ---: |
| Automatic | 2 | 4.29 | 763,658,240 | 14,824,825 | 9 |
| Image-backed | 9 | 8.26 | 1,131,397,120 | 15,629,859 | 10 |
| Always | 12 | 8.78 | 1,135,919,104 | 15,790,632 | 13 |

Execution order was image-backed, always, automatic. These are single observations, not a
timing distribution or device budget. RSS excludes separate platform services; the large
derivative retains resources from the original report. The earlier exploratory run overlapped
other gates and measured 4.47/37.87/9.24 seconds for automatic/image-backed/always. Those receipts
are retained separately and do not support a speed comparison. No full 920-page forced/selective
conversion or physical iPhone/iPad measurement is claimed.

## Regression evidence

- All **152 Swift tests** pass on macOS and iOS 27 Simulator. Four new tests cover mixed-page
  selection and native bold styles, blank-source replacement/fallback, rotated fallback, and
  cancellation on recognition entry with staging cleanup. The attachment-only automatic-OCR
  test now includes the new policy. Cancellation remains cooperative during platform work.
- An isolated copy of the original pipeline, retaining the new enum only so the tests compile,
  fails three of the initial four selected tests with **13 assertions**. The rotated-fallback
  positive control passes. This negative run predates the added cancellation test.
- `scripts/check-all.sh --corpus` passes: the then-current 151 Swift tests, 69 Python tests,
  six original fixture conversions, eight CLI policy conversions and twelve rejection/cleanup
  cases, fresh-process native concurrency checks, the unchanged 192 MiB structure-index gate,
  and all eight complete corpus documents with EPUBCheck, progress and their existing memory
  budgets (**221 reviewed content checks on 54 pages**). The final cancellation-only addition was followed by the full 152-test Swift suites
  on both platforms. No runtime change followed the corpus gate.
- Each measured derivative passes independent ZIP/XML/navigation/packing checks, EPUBCheck,
  page-specific selection, source phrase and image-retention assertions, monotonic progress,
  completion and staging-cleanup checks. All twelve page markers survive in order.

The full corpus protects the existing default policy; the derivative and synthetic matrix
exercise the opt-in policy. Full Warren/NOAA default completion and general source accuracy
remain outside passing baselines. No roadmap item or issue is removed.

## Reproduce and inspect receipts

```sh
swift build -c release
python3 measurements/selective-ocr/measure.py \
  --converter .build/release/pdf-reflow --epubcheck /opt/homebrew/bin/epubcheck \
  --output /tmp/selective-ocr-review --policies image-backed always automatic
scripts/check-all.sh --corpus
```

The measurement needs development-only `pypdf` and the pinned source in `corpus/cache/`.
It performs no downloads. The output directory must be new. Native controls come from committed
original fixtures. `implementation-sha256.txt` identifies runtime, test and tool sources;
`results.json` includes the release executable hash. `sequential-receipts.tar.gz` contains
per-policy reports, exact page text, progress and EPUBCheck logs; `exploratory-receipts.tar.gz`
retains the first trial. `gate-receipts.tar.gz` contains full-gate JSON/log evidence, with separate
compressed gate, macOS, iOS and negative-test logs. The large PDF/EPUB derivatives remain local.

Stronger image/text disagreement detection, cropped/tiled scan coverage, numerical/table
accuracy, content-selection quality and physical-device resource limits remain open under #7
and the existing broader corpus work. No rejected comic-heading repair is reintroduced.
