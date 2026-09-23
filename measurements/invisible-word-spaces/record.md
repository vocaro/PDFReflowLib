# Invisible transcription word spaces (#295)

Measured 2026-09-23 against `a1bd1c8`, on the checksum-pinned 920-page Warren
Commission report (`341cc3471750c9c3be68b95a34b52f6cbdc86c4392427a8483ee1c6bc53cfc19`).

The library's visible-font spacing repairs already stay off this scan. PDFKit's
plain line selections themselves read `twoon`, `runningboard`, `wasapproved`,
`ChapterI.`, and the other five reported lost boundaries. The content stream does
not encode literal spaces at these positions: it puts each OCR word in its own
invisible (`3 Tr`) text show, scales standard Courier to the word's box, and
positions the next word separately. Poppler keeps those word boundaries; PDFKit
sometimes fuses them. On page 30 the gaps after `two`, `running`, `was`, and `House`
are respectively 0.284, 0.265, 0.295, and 0.278 em of the larger adjacent font size.
These are word-box gaps, not measurements of the letters visible in the scan.
The page 30 scan was also rendered and checked directly: all four are ordinary
printed word boundaries, as are the additional `jump seats`, `Governor Connally`,
`who was in`, and `windows of` repairs on that page.

The invisible-layer path now reads those shows using the existing bounded stream
walk and supported font decoders. Standard unembedded Courier has a 0.6-em advance;
other fonts still need their stated widths. It inserts a boundary between letters
or digits when adjacent shows have at least the existing 0.15-em word gap and their
baselines agree within 0.1 em. Full-width East Asian neighbors retain their own
spacing convention. Only complete line agreement authorizes a repair; unsupported
text state, visible shows, ambiguous anchors, unreadable codes, and unmeasured
advances provide no new boundary. The visible-font repair path is unchanged.

PDFKit also returns an attachment-only selection covering the whole scan. That
selection owns no text, so it must be excluded from the rectangles that establish
ownership of invisible word-box anchors. Without that exclusion every anchor
appeared shared and real source pages received no repair, even though source
fixtures that carried only text lines passed. The pipeline regression includes a
real image selection and catches that distinction.

A native extraction audit across the full source inserts 4,084 spaces in 2,208
lines on 655 pages. Every non-whitespace character remains in order. The small
summary retains every changed line on the four issue pages. This count describes
extraction, before recognition policy or reconstruction; it does not claim every
line is present unchanged in the final book. Inherited OCR mistakes such as
`\Yhite`, `adtually`, and `Kemiedy` remain as the source states them.

The four Warren spacing fixtures come from `tools/probes/capture-spacing-source.swift`;
three additional layout fixtures come from `tools/probes/capture-layout-fixture.swift`
(the existing page 50 capture is reused). Both capture tools verify the source hash.
They record source streams, font metadata, PDFKit text and geometry, never converted
output. Tests pin all nine reported boundaries and non-whitespace identity, alongside
visible/unmodeled-state refusal, saved rendering state, unknown-width fonts,
negative/zero/narrow gaps, mismatched text, and ambiguous ownership controls.

Reproduce the extraction audit from the repository root:

```sh
swiftc -O $(python3 tools/pdfreflow_tools/swift_sources.py audit-invisible-spacing.swift) \
  -o /tmp/audit-invisible-spacing
/tmp/audit-invisible-spacing corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf /tmp/warren-word-spaces.json
```

The same audit on the pinned 312-page CIA Blue Book and 56-page Our Flag finds no
changed lines. The former has invisible text with a different source spacing
pattern; the latter's visible typography remains outside this path.

As a second extraction check, `pdftotext -layout` independently supports 3,962 of
the inserted boundaries when the changed line has a unique character-for-character
match on its source page. Another 116 cannot be aligned under that strict test.
Five differences are `A` followed by an ordinary word (`person`, `delustering`,
`boy`, `mastoidectomy`, `young`), which Poppler fuses too. The remaining difference
is the clipped, widely spaced newspaper fragment on page 367 (`m a l` in the
scan, whose inherited OCR reads the final letter as `1`); this was reviewed on the
source render. This comparison qualifies the spacing evidence, not the correctness
of inherited OCR characters or a full-book fidelity claim.

## Full conversion and gates

Both release CLIs converted the complete, pinned Warren source at library defaults,
with the same unsandboxed access to PDFKit and Vision. The baseline is exact
`a1bd1c8`; executable SHA-256 identities and the evaluator's gate receipts are in
`conversion-summary.json`. An earlier sandboxed baseline produced 40 `ocrFailed`
notices and recognized no pages; it was discarded as an unequal comparison and is
not the baseline summarized here.

| Full 920-page run | Baseline | Candidate |
| --- | ---: | ---: |
| Reflowed pages | 905 | 905 |
| Recognized pages | 14 | 14 |
| Images | 934 | 934 |
| Output text characters | 2,434,805 | 2,438,818 |
| EPUB bytes | 531,580,017 | 531,577,707 |
| Peak process RSS bytes | 1,261,748,224 | 1,253,015,552 |
| Conversion seconds | 445.39 | 437.96 |

Both pass EPUBCheck, the structural, progress, output-size and configured memory
gates. These are single runs on a shared host, not a performance benchmark. The
candidate passes all 94 reviewed content assertions; the baseline fails exactly
the eight strengthened/new assertions covering the nine reported boundaries.

Across the complete EPUB, 648 pages change text. Every page's non-whitespace
characters agree after removing hyphens: 61 pages also let the existing hyphen
repair recognize a now-separated word, such as `House representa-tives` becoming
`House representatives`. No other character changes occur, including on the 14
recognized pages. All 934 image filenames and image bytes are identical.

Validation: all 722 Swift tests pass; the final 28 focused spacing tests pass,
including the East Asian control; all 31 content-checker Python tests and three
probe-source-list tests pass; `check_measurements.py` and `git diff --check` pass.
The corpus contract gains seven assertions and strengthens the existing Chapter I
entry. Counts and the issue-state snapshot are maintained by the integrating task.

Reproduce each full conversion with its own release executable and output directory:

```sh
python3 tools/evaluate_real_document.py --case gpo-warren-1964 \
  --pdf corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf --converter /path/to/pdf-reflow \
  --output /tmp/warren-spacing --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/check_corpus_content.py --case gpo-warren-1964 --evaluation /tmp/warren-spacing
```
