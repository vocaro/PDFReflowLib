# The scanned-table fallback reaches the book it was built for (#31)

Measured under [#31](https://github.com/vocaro/PDFReflowLib/issues/31) on `main` at `8faeaab`,
2026-09-23, macOS 27 / Xcode 27, arm64, release CLI at library defaults through
`tools/evaluate_real_document.py --case cia-blue-book-14-1955`. Source: `cia-blue-book-14-1955`,
SHA-256 `90e05e77…52ee3`, 312 pages. No runtime file changes with this record; it measures what
the tree already holds.

## What #31 asked

Detect tabular regions on scanned pages and reconstruct their rows and columns — by fresh OCR,
by layout analysis, or, failing both, by an explicit warned image fallback per cell or region —
with source-derived regressions against the Blue Book's pages 74 and 150, and signaling kept
separate from repair. [scanned-table-cells](../scanned-table-cells/record.md) took the fallback
side on 2026-09-21: `TableCellEvidence` judges a located table by the share of its grid the
recognizer transcribed, a table under half raises `unreadTableCells` beside the picture that
preserves it, and fifteen tests replay a captured reading of both pages. It ended on a wall: under
the default policy the book was never recognized, because page 150's unread handwriting passed
the plausibility test on the strength of its printed labels, so the fallback reached no page of
the book's own conversion. That blocker was #275, fixed by `d4ce045` on 2026-09-22.

## What the book does today

| | count |
| --- | ---: |
| recognized pages | 56 |
| `implausibleTextLayer` | 57 |
| `ocrUsed` | 56 |
| `unreadTableCells` | 65 |
| table crops whose alt text says the cells are not transcribed | 60 |
| `unverifiedTextLayer` | 256 |

Page 150, the hand-written sheet of four ruled grids, reports `implausibleTextLayer` (71 of 157
judged words English), `ocrUsed`, and two `unreadTableCells` — the recognizer located two of its
grids and transcribed 45% and 44% of the 390 cells each returned — and the EPUB carries the two
crops with the alt text *Table from page 150, preserved as an image. Its cells are not
transcribed; read them in this picture.*, beside the *Original page 150* reference. That is the
fallback, on the page it was written for, in the book's own conversion.

Page 74, the typewritten table, reports `unverifiedTextLayer`, `furnitureRemoved` and
`imageRegion` and keeps its layer: 40 of its 89 tokens are numbers, which is #275's numeric
exemption working as intended. Asked to read it, the recognizer transcribes 83% of its grid
(scanned-table-cells §1), above the half rule, and it still loses one value and corrupts two of
forty — so its table is neither replaced by a reading nor preserved under the warning, and its
inherited layer stands with the review notice #19 established.

Gates on this evaluation: structural check passed, EPUBCheck exit 0, peak RSS inside the 768 MiB
ceiling with host pressure normal, `tools/check_corpus_quality.py` passed with no missing warning
page, and the corpus contract's page 74 and 150 checks hold.

## What stays refused, and why nothing tracks it

Reconstructing the cells. On the evidence in scanned-table-cells §2 — page 150's grid returned 26
columns where the page rules 25 and filled them with `CRASSE DR GLONINS CRAVGE` for `ORANGE OR
GLOWING ORANGE`; page 74's clean typescript still loses one value in forty — a transcription the
reading gets wrong is worse than the picture the reader can check. The issue's own acceptance
names the warned fallback as an outcome, so this is the close, not a deferral, and no follow-up
issue is opened for cell transcription.
