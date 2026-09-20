# Vision determinism: two reported defects that no longer reproduce

Two of the Apple-attributed defects in this tracker are about Vision giving different text for the
same page: #173 item 1 (which pages the OCR retry recovers is a property of the compiled Vision
models — 11 fresh compiles read Blue Book page 6 five different ways) and #94 (the identical
converter binary produces noisier OCR on Census pages 2–20 when run from `.build/release/`). Both
were going to be filed with Apple. Neither reproduces here, so neither was filed.

Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max, 36 GB. Measured 2026-09-20 with
`probe.swift` in this directory, which rasterizes one page with PDFKit and reads it with
`RecognizeDocumentsRequest` — the same Vision API `OCRReader` uses — and prints the SHA-256 of the
rasterized pixels beside the SHA-256 of the transcription, so a difference in the reading cannot
be a difference in the pixels.

## Fresh compiles agree (#173 item 1)

Six compiles of the same source with `xcrun swiftc -O`, each producing a different binary, reading
Blue Book page 6:

| Compile | Binary SHA-256 | Image SHA-256 | Text SHA-256 | Lines |
| --- | --- | --- | --- | ---: |
| 1 | `9ae1198ebb86…` | `20a2276a63a4…` | `94a12d87af95…` | 62 |
| 2 | `5befe7715042…` | `20a2276a63a4…` | `94a12d87af95…` | 62 |
| 3 | `86876f026011…` | `20a2276a63a4…` | `94a12d87af95…` | 62 |
| 4 | `4c92579cef57…` | `20a2276a63a4…` | `94a12d87af95…` | 62 |
| 5 | `26a4672a07e0…` | `20a2276a63a4…` | `94a12d87af95…` | 62 |
| 6 | `a7d788b68ffd…` | `20a2276a63a4…` | `94a12d87af95…` | 62 |

Six distinct program hashes, one transcription.

## The binary's location does not change the reading (#94)

One binary, copied to `…/locA/.build/release/probe` and `…/locB/somewhere/else/probe`, reading
Census page 2:

| Location | Binary SHA-256 | Image SHA-256 | Text SHA-256 | Lines |
| --- | --- | --- | --- | ---: |
| `locA/.build/release/` | `26a7cd4b716e…` | `11684e3992e8…` | `dda23e7e884a…` | 33 |
| `locB/somewhere/else/` | `26a7cd4b716e…` | `11684e3992e8…` | `dda23e7e884a…` | 33 |

## What this does and does not establish

It establishes that this Vision API, on this OS build, returns the same text for the same pixels
regardless of the program hash or where the binary lives. It does not establish that the original
observations were wrong. Both were made on the abandoned coordination branch, against an earlier
OS build, and #94 predates the move to `RecognizeDocumentsRequest`; either the framework changed
or the variance came from somewhere other than Vision.

The consequence for this repository is that the variance should be re-measured in the library
before it is attributed to Apple again. `OCRReader` does more than one recognition pass — the
band retry of #116 crops the page and reads it twice — and the rasterization it feeds Vision is
`PageRasterizer`'s, not this probe's. Both are library behavior that this probe holds constant.
