# Native sparse-title qualification after the complete integration audit

Follow-up to #296, 2026-09-23. The first-five integration's all-page audit found that the
sparse-title fallback was also lowering thresholds for OCR fragments and for the byline of
a native cover whose title was already larger. The source-backed scope is now explicit:

- Only native, nonsynthetic font sizes can establish this extra title evidence. OCR box
  heights are not font sizes. Recognition retains exactly its pre-fallback threshold.
- The dominant size being rescued must also be the largest reflowable size. Earthdata's
  cover has a 52 pt title and a character-dominant 28 pt byline/affiliation; the latter do
  not borrow a smaller document body merely because the page is sparse.
- A sole dominant token mixing letters and digits with no whitespace is insufficient
  evidence for the rescue. On FAA physical page 1, `FAA-H-8083-25C` is the publication code
  above the real, much larger raster title. The source render confirms that role. Ordinary
  heading classification remains unchanged; this guard only declines the added fallback.

The source fixtures retain Earthdata pages 1, 2, 3 and 6, FAA page 1, and the Arabic guide's
page 1. Earthdata's cover byline and NASA remain prose; its true slide titles on pages 2, 3
and 6 remain headings. The Arabic cover's 34 pt title and 30 pt subtitle remain headings.
The seven NOAA opener controls still pass, including the lowercase second title lines, and
the DGA six-label negative control still passes.

Census physical page 7 is ordinary prose and an equation: the source render shows that
`[16]) in that it uses Dijkstra's shortest augmenting path for many computations` continues
an existing paragraph. The first-five run promoted it to a heading. A fresh source OCR
capture reads more of the page and gives some prose lines tall bounding boxes; that is a
host-variable reading, not the exact first-five transcription. The deterministic regression
replays a sparse pair from this actual capture and separately uses explicit synthetic OCR
geometry with the observed Dijkstra text. Both recognized and invisible/synthetic-style
pages must retain the original threshold. The source corpus contract additionally requires
the Dijkstra phrase in a paragraph on physical page 7. The frozen first-five output fails
exactly this new paragraph assertion; the guarded output passes it.

Validation: all 91 focused heading/title tests pass, including the source and OCR controls;
the PDFKit gate and diff whitespace check pass. The complete guarded Census conversion
passes 61 content checks, EPUBCheck, structure, progress and memory gates. The Dijkstra
sentence is in prose. The fuller fresh OCR reading still produces three unrelated false
headings from unusually tall boxes (`probabilities...`, `truly matching...`, `ing an updated...`)
under the original OCR typography rules; this follow-up does not claim to solve every OCR
heading error. The complete Earthdata conversion passes all 21 content checks and confirms
its cover byline/affiliation paragraphs and the three rescued slide titles.

The guarded converter SHA-256 is
`d484faad9567c418817391498751def031efda9e9fa02be73b895da1a4fba229`.
The Census EPUB SHA-256 is
`5844849f896c249b17c82f1855792e9083c7ebaf367e0136fcaba05af1570a0b`;
the Earthdata EPUB SHA-256 is
`4d036f6812aa3d1b2220f663be997ebd6fd2e7f12dcc1ca0f8449c9c7a3ea151`.
These are macOS 27 arm64 source-validation runs, not whole-document visual or mobile-device
qualification. Raw captures, renders, logs and EPUBs remain in
`/tmp/pdfreflow-296-final-guards`; the integration's frozen first-five Census failure is in
`/tmp/pdfreflow-census-same-name`, with its main control in
`/tmp/pdfreflow-census-main-control`.

Reproduce with `swift test --filter 'sparse|repeatedCoverLabels|Heading|heading|Title|title'`,
then the normal `tools/evaluate_real_document.py` and `tools/check_corpus_content.py` commands
for `census-rrs2002-01` and `ntrs-20180003024-earthdata-slides-2018`, using the built converter
under its ordinary `pdf-reflow` basename. Keep raw source captures distinct from reconstructed
output, and compare OCR readings before attributing differences to code.


## Same-executable rule control

The integrated final release at `89ea015` again transcribes some Census OCR pages differently
from the earlier executable, even with the normal basename. To isolate the heading rule, a
separate worktree at that commit adds one temporary environment switch: value `1` selects the
old `established == nil && dominantLines.count <= 2` fallback condition; value `0` selects the
final native-size/maximum-size/identifier guard. Both full source runs use the same executable
bytes, recorded in `same-executable-control.json`. This instrumentation is not production code.

The Census controls have identical parsed pages, markers and image bytes with either rule.
This particular OCR reading establishes enough ordinary body text that the sparse fallback
does not change its classification. The deterministic sparse-OCR regression and the earlier
frozen-output failure remain the evidence for the reported Dijkstra promotion; this control
does not substitute a different OCR transcription for that reproducer. It shows that toggling
the guard does not reproduce the broad cross-build transcription difference in this run.

The native Earthdata controls preserve all text, source markers and image bytes. Only page 1's
byline/affiliation changes from headings to paragraphs; the actual title and the other slides
retain their readings. These paired controls support the bounded classifier change, without
claiming general Vision determinism or identifying a framework cause for cross-build readings.
