# Native column order across preserved background crops

Physical NOAA pages 50, 60, 63, 64 and 78 retained their letters but interleaved
left and right columns after native prose was released from background artwork.
The columns already supplied sufficient margins for `PrintedColumns`; one
preserved crop crossed the gutter midway through those columns and rejected the
plan. Row-major fallback then mixed separate sentences.

The correction carries the existing evidence of at least six native body rows
reflowing over a crop into its ordering element. Only a crop with that evidence
may follow independently established columns when its bounds cross their gutter.
The image is retained once. An unproved figure or semantic table still rejects
that fallback. OCR and synthetic text cannot supply the new flag.

After the columns were restored, native panel grouping could move an already
contiguous ordinary paragraph beside its geometrical neighbor in another column.
Its relocation now requires overlapping ordered ranges: a panel that does not
interrupt the adjacent paragraph keeps its established position. The existing
Fed sidebar controls continue to pass. This change is independent of the tagged
panel/heading-ID review being integrated separately.

Source: `noaa_61592_DS1.pdf`, SHA-256
`1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf`.
All five pages were rendered with MuPDF and visually inspected. Page 50 has a
left map/caption and right prose; page 60 has two prose columns above photographs;
page 63 has left prose/photographs and a right prose column; pages 64 and 78 have
two ordinary prose columns. None justifies interleaving their sentences.

The JSON fixtures separately capture raw native lines, attributed runs, geometry
and paint metadata from the exact current reader. Captured data is extraction
evidence, not a substitute for rendered-source review. Permanent controls compose
those paints, infer actual crops, check selected complete paragraphs and left-
then-right source order, and verify every crop is retained exactly once. The live
`PageReader` path was also run independently for these pages and produced the same
corrected ordering. The diagnostic test and rendered images remain outside the
repository, under `/tmp/pdfreflow-noaa-columns-*` and `/tmp/noaa-audit-*`.

Reverting the ordering allowance and panel range guard reproduces 12 failures
across all five source cases. The new corpus paragraph/order checks also reject
the completed conservative NOAA output on all five pages. They preserve every
existing corpus case and explicitly distinguish visual review from capture.
The root integration run owns the full 1,834-page candidate qualification; this
record does not claim that a focused source test is a whole-publication pass.

The three previously questioned focus summaries on pages 1691, 1712 and 1730
already become ordinary paragraphs under the integrated panel grouping, and their
genuine subheadings remain headings. No heading-size relaxation is part of this
change. The separate contents-page locator losses on 8, 19 and 20 are tracked by
the TOC work, not claimed resolved here.

Commands:

```sh
swift test --build-system native --scratch-path /tmp/pdfreflow-noaa-columns-build
/opt/homebrew/bin/python3 tools/check_corpus_content.py --case noaa-nca5-2023 \
  --evaluation /tmp/pdfreflow-noaa-conservative-evaluation
```

The second command is the expected-failure corpus control, not the final candidate.

Final local validation: all 813 Swift tests pass in 57.59 seconds, including the
existing USDA magazine column controls and all 17 Fed panel continuity source
cases. The five new NOAA source cases and unproved-figure/table controls pass.
`git diff --check` and the measurements policy gate pass. Base: `4bde22f1`.
