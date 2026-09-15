# PDFKit attributed-text leak evidence

Retained observation from 2026-09-14 on macOS 27.0 `26A428`, Xcode 27.0 `27A266a`, arm64.
The input is the 522-page FAA-H-8083-25C handbook pinned in `Corpus/manifest.json`, SHA-256
`247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7`.
These diagnostic measurements are historical evidence, not a fresh run for issue filing.

The standalone probe uses only Apple SDKs. It opens pages inside autorelease pools without
retaining PDFs, selections, attributed strings or extracted contents between pages. The plain
control's after-pass physical footprints are 93,340,752, 135,857,304 and 74,957,976 bytes.
The separate attributed-text three-pass probe reaches peak RSS of 1,466,122,240,
2,308,456,448 and 3,145,564,160 bytes. RSS and physical footprint are different metrics; these
series must not be presented as a same-metric comparison.

A separate stack-logged one-pass run reports 74,930 leaked allocations totaling 247,585,696
bytes, including 506 root mutable attributed-string instances. Allocation stacks traverse
`PDFPage.attributedString`, `PDFSelection.attributedStringScaled:`,
`CGPDFSelectionCreateAttributedString` and `PageLayout::CreateAttributedStringForStringRanges`.
Retained attributes include decoded CGImage/CGDataProvider storage. See the unmodified
`leaks-excerpt.txt`, `plain.jsonl`, `attributed-three-pass.txt`, and historical
`three-pass-probe.swift`. `diagnostic.json` records source/binary and original full-log identities;
the full local log is not bundled.

The diagnosis supports a framework-path leak on this Mac build, not a claim that all converter
RSS is leaked, a precise internal ownership diagnosis, or a physical iOS reproduction. Apple
has not confirmed it; no Apple Feedback report is recorded. Stack logging changes memory and
timing, so it is unsuitable for setting converter memory budgets. The library's document
windowing, autorelease pools and skipped unnecessary style reads reduce exposure but do not
establish a fix.

Current reproduction instructions and the reusable probe are in
[the memory guide](../../doc/memory-testing.md). The current probe's comment uses the standalone
library name; its source identity is distinct from the retained pre-publication diagnostic.
