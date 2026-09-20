# Streaming logical blocks to the writer

Work on [#33](https://github.com/vocaro/PDFReflowLib/issues/33), on top of `b080571`,
2026-09-19, macOS 27 / Xcode 27, arm64. The change makes reconstruction hand each page's assets
and blocks to `EPUBWriter` as it finishes them instead of returning one whole `ReflowDocument`,
so the logical block list is never resident. This records the identity gate that holds the
refactor to no behaviour change, and what the change does and does not do to measured memory.

## What changed

`PDFReflowLibPipeline.reconstruct` emits `ReflowPart`s — the document-wide facts once, then each
asset and block in production order — and `EPUBWriter` is an actor that consumes them,
serializing each block on arrival and closing spine documents as the packer fills them.
Navigation, package metadata and the archive are built in `finish`. Only the trailing block is
held back during reconstruction, because `LayoutReconstructor.appendPage` can still join a
continued paragraph to it; everything before it is final. A caller that takes no stream gets the
document collected from the same stream, which is how the tests still read a whole document, so
the streamed and collected forms cannot diverge.

Model validation moved with it: `ReflowDocument.Validation` accepts one part at a time, and
`ReflowDocument.validate()` runs it over `parts`, so the whole-document and streamed checks are
one implementation. Progress composition follows the work: serializing a block is now
reconstruction, and the writing stage is navigation, package metadata and the archive.

## Identity gate

Both binaries were built `swift build -c release` in this worktree, the baseline from `b080571`
before the change. Each book was converted by both with
`--package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`, with
`--reference-images automatic` except Warren (`never`, so it completes under the default budget)
and with NOAA's established explicit 4 GiB entry and final caps, and compared with
`tools/epub_identity.py` (archive entries and the conversion report). Each pair of EPUBs was
deleted as soon as its result was recorded.

**All ten complete corpus books are byte-identical, with identical conversion reports**: zero
differences reported for dga-2025-2030, cdc-zombie-pandemic-2011, gpo-our-flag-2003,
fed-explained-2021, cia-blue-book-14-1955, wallace-algebra-2010, gpo-911-2004,
faa-phak-8083-25c, gpo-warren-1964 and noaa-nca5-2023. Both builds produced the same EPUB byte
count on every book, from 7,848,652 bytes (DGA) to 1,466,261,389 bytes (NOAA).

## Memory

Measured through `tools/evaluate_real_document.py`, which records the kernel's lifetime peak RSS
from `wait4`'s `ru_maxrss` — the measure the memory gate uses — and samples physical footprint
every 100 ms; `measurements/page-retention/profile.py` renders the per-stage profile from those
samples. Each pair ran baseline then candidate back to back. **The machine was shared with five
other agents' builds and conversions throughout**, and the run-to-run spread of the sampled
footprint is larger than the effect being measured, so the pairs are reported individually and
no single pair should be read as the number.

NOAA, three pairs, MiB:

| Pair | Build | Peak RSS | Sampled peak | Extraction end | Reconstruction peak | Writing peak |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | baseline | 844.2 | 392.1 | 346.9 | 378.0 | 233.2 |
| 1 | candidate | 848.4 | 385.2 | 333.6 | 377.1 | 132.4 |
| 2 | baseline | 952.7 | 283.3 | 220.5 | 283.3 | 103.7 |
| 2 | candidate | 946.1 | 291.2 | 254.9 | 286.1 | 98.2 |
| 3 | baseline | 948.0 | 298.8 | 259.6 | 298.8 | 118.6 |
| 3 | candidate | 956.2 | 314.5 | 241.3 | 309.5 | 101.1 |

Warren, one pair, MiB: peak RSS 1139.4 against 1113.5, sampled peak 526.3 against 525.7,
reconstruction peak 245.5 against 259.0, writing peak 151.5 against 145.9. Warren's archive is
19 MB, so its writing stage is only four 100 ms samples long.

Pair 1's candidate run reached memory-pressure level 2, and the evaluator marks its peak RSS
untrustworthy for that reason; its absolute footprints are the highest of the three pairs on
both builds. Pairs 2 and 3 ran at pressure level 1 and passed the memory gate.

**The writing phase is lower on the candidate in every pair**, by 5.5 to 101 MiB on NOAA and by
5.6 MiB on Warren. **The lifetime peak does not move**: it is set during extraction, hundreds of
mebibytes above anything the writing phase reaches, by PDFKit and rasterization transients that
this change does not touch. Pairs 2 and 3 put the block list NOAA retained at roughly 6 to
18 MiB — much less than the 113 to 170 MiB writing-phase footprint that
[page-retention](../page-retention/record.md) recorded, which is mostly the 11,245-asset
registry, the ZIP machinery and framework residue rather than blocks.

Conversion time is unchanged within the same noise: NOAA 203.5/148.9/138.9 s baseline against
215.8/140.9/135.5 s candidate.

## Progress and cancellation

The evaluator's progress check passed on every run recorded here: each conversion's CLI
fractions start at 0, never step backward, stay in range, name pages within the book and end at
`100% completed`. The writing stage's first event is now the first archive entry at 0.82, the
value the pipeline's clamped end already reported, so the sequence stays monotonic with no
backward step and with no event between the last block and the archive.

Cancellation is unchanged in scope and gains one path: `SpineWriterTests` cancels a streamed
document between blocks and requires the error, no `publication.epub` and no `nav.xhtml`, and
cancels at the writer's first progress report and requires no archive. The converter-level
cancellation tests, which cancel during extraction and at the first writing event, still leave
an empty destination directory.

## Not measured

No physical-device measurement. #33's acceptance also names a peak footprint on a physical
iPhone through the retained device host in `measurements/page-retention/device/host/`; that was
not run here and remains open.

## Reproduce

```sh
swift build -c release
# baseline binary: the same command at b080571, before this change
pdf-reflow BOOK.pdf out.epub --package-identifier urn:uuid:identity \
  --modification-date 2026-01-01T00:00:00Z --reference-images automatic
python3 tools/epub_identity.py --baseline-epub a.epub --candidate-epub b.epub \
  --baseline-report a.json --candidate-report b.json
python3 tools/evaluate_real_document.py --case noaa-nca5-2023 --pdf corpus/cache/noaa_61592_DS1.pdf \
  --converter LAUNCHER --output OUT --max-peak-rss-mib 1000000
python3 -c "import sys; sys.path.insert(0, 'measurements/page-retention'); import profile; \
print(profile.profile(profile.load_samples('OUT/memory-samples.json')))"
```

`LAUNCHER` is a shell script that appends the case's options to the binary, because the
evaluator runs the converter with its two positional arguments only.
