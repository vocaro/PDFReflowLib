# Warren Commission scanned-report baseline

Tier: deterministic on-device Apple PDF/OCR stack, library defaults, macOS 27.0 (26A428)
arm64. Corpus: owner-supplied 920-page GPO Warren Commission report, identified in `result.json`.
Build: isolated release CLI from repository revision `bf4b267`, built with Xcode 27 using
`swift build -c release --scratch-path .build/corpus-cli`. Executable SHA-256:
`6ae1a17ef314531255ad1e768c4c75c6739483fe793de6627d8f9b5b2021602f`. No LLM/PCC is used.

## Full-document result: failure

The complete conversion fails after 203.44 seconds with
`Conversion resource limit: image output bytes`. The last completed reconstruction page is
390/920, at 67% reported work. Full-page scan reference PNGs exhaust the default 512 MiB
image-output ceiling. No EPUB is published; the staging directory is removed. EPUBCheck does
not run because there is no complete EPUB. The ceiling remains unchanged.

Peak converter RSS is 2,112,585,728 bytes
(2014.7 MiB). Sampled peak physical footprint is
1,294,846,424 bytes. These are different metrics and exclude
separate Apple services. This is one fresh-process Mac observation, not a physical-device
budget or a successful full-book conversion. A preceding exploratory run also fails the
same output ceiling; the retained result is the isolated-build confirmation.

`result.json` is an unmodified generated receipt, and `memory-samples.json.gz` losslessly
compresses the 323,646-byte memory-sample series. `progress.log.gz` losslessly compresses the
complete progress/debug log; `progress-audit.json` records its raw
identity and verifies monotonic events, the incomplete terminal fraction, and cleanup. The
runner's `progressCheck.passed: false` reflects missing successful completion, not backwards
progress. Only one page enters the recognizing stage during extraction. A Mac memory ceiling
is deliberately not configured for this case until full conversion is supported; the default
run remains a failing stress test, never an expected-failure green pass.

The high RSS is additional workload evidence for investigation, not proof that the increase is
entirely Apple's attributed-text leak. No allocation ownership diagnosis is made from RSS.

## Source and excerpt review

`source-inspection.json` records all-page image-resource and extractable-text counts plus
sampled invisible text rendering. All 920 pages have direct image XObjects; Poppler extracts
nonempty text from 910. Sampled pages 21, 50, 890 and 910 use invisible text rendering mode 3;
page resources on 50, 890 and 910 identify Courier, although the visible book uses proportional
print. The PDF has no structure tags and has one signature field. Counts do not establish OCR
accuracy, and this inspection does not verify the digital signature.

Because the full default conversion cannot publish an EPUB, visual comparison uses a nine-page
local derivative. `prepare-excerpt.py` verifies the original identity before producing it;
`excerpt-identity.json` maps excerpt pages 1-9 to original pages
1, 7, 21, 30, 50, 100, 890, 910 and 920. The original PDF is unchanged. The derivative may retain
shared PDF objects and is not intended to reduce file size or preserve signature validity.
It lacks whole-book vocabulary, repeated-furniture and continuation context.

`comparison-identity.json` records the actual comparison executable and output identities.
This comparison uses the previously available release executable, distinct from the isolated
full-book baseline build. Do not treat their binary identities as interchangeable. A separate excerpt conversion with
the isolated baseline build reproduces byte-identical chapter XHTML and the same report counts;
`isolated-build-excerpt-check.json` records both the executable and chapter identities.
The excerpt emits nine images and reports nine pages with reflowed text, with zero newly
recognized pages. EPUBCheck 5.3.0 reports no errors or warnings. That result applies only to
the excerpt archive and does not qualify its text, nor the complete book.

## Observed fidelity defects

- Original page 50 (excerpt 5): the scan reads “his known contacts with the Soviet Embassy”,
  while the OCR/output has “bis”, “witb” and “tbe”. No OCR-quality warning reports this
  inherited transcription. Prose is serialized as `<pre>`, preserving hard wraps and
  discretionary hyphens; ordinary lines also become spurious headings. Courier is a font
  used by the invisible OCR layer, not reliable evidence that the source is code.
- Page 890 (excerpt 7): notes interleave 415, 477, 416, then the continuation of 477.
  The left column should finish through 476 before the right begins at 477.
- Page 910 (excerpt 8): “Federal Bureau of Investigation” interrupts “De Mohrenschildt”
  before its continuation. Index entries become headings. Complete the left column through
  “Fair Play for Cuba Committee” before starting the right column.
- Page 920 (excerpt 9): the textless back-cover scan becomes two paragraphs containing only
  U+FFFC object-replacement characters plus its reference image. It is counted as reflowed
  text. The cover at original page 1 has the same placeholder-only output.

`excerpt-xhtml.json` retains exact output fragments for the listed excerpt pages. Screenshots
`page-50.png`, `page-890.png`, `page-910.png` show excerpt page numbers in the controls; consult
the mapping before citing original pages. `page-910-positioned.png` shows the usable Poppler
positioned view. The screenshot review is limited to these regions; it is not an adjudicated
full-book reference or OCR accuracy score. Government-report excerpts are evidence, not code
relicensed under MIT. No source PDF or full derived EPUB is committed.

## Comparator limitation

Poppler 26.04.0 simple HTML emits absolute filesystem paths for its PNG image sources when
given an absolute output prefix. The loopback server cannot resolve those as bundle-relative
URLs, so that pane shows broken images. The PNG files themselves are valid. Positioned HTML
uses a usable rendered page image. Default Poppler extraction also omits invisible OCR text;
a blank simple-text pane is not evidence that the PDF has no machine-readable text. Use the
positioned view and original raster for the retained review; do not relax server containment.
