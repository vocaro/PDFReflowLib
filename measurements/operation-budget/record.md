# What the graphics operation budget costs (#13)

`GraphicsReader` gave up after 100,000 charged content-stream operations and marked the page
unsupported, which makes it a full-page image. The budget exists to bound the work one page can
ask for, so the question is not whether to have one but where a real page stops and adversarial
content begins. This record measures that instead of asserting it.

## Method

The reader itself was compiled with its budget raised to 100,000,000 and its operation count
returned on `Result`, and run over every page of all 24 cached corpus PDFs — 5,302 pages —
recording the operations each page charges, the wall time of a complete scan and the change in
the process's physical footprint across it (`tools/survey-budget.swift`, `tools/analyze-budget.py`;
the patched reader is `Sources/PDFReflowLib/GraphicsReader.swift` with those two lines changed,
kept out of the repository because a second copy of a source file rots). macOS 27 arm64, `swiftc
-O`, one process, serial.

Counting inside the reader rather than beside it matters: a page can hide most of its work in a
Form XObject, and the reader charges what it finds there. An independent operator count over the
page's own content stream alone reports FAA pages 286 and 302 at 99,978 and 97,748 operations,
under the old budget, although the reader charges them 105,105 and 101,478 and refused them.

## The distribution

| charged operations | pages |
| --- | --- |
| under 10,000 | 5,229 |
| 10,000–50,000 | 63 |
| 50,000–100,000 | 4 |
| 100,000–150,000 | 2 |
| 150,000–200,000 | 3 |
| 200,000–1,900,000 | 0 |
| over 1,900,000 | 1 |

Five pages in the whole corpus sit between the old budget and 250,000: FAA 286 (105,105), FAA 302
(101,478), FAA 288 (166,035), FAA 226 (183,297) and NOAA 1834 (191,548). Then nothing at all for
an order of magnitude, until FAA page 448 at 1,954,644.

## What a full scan costs

| page | operations | scan | footprint |
| --- | --- | --- | --- |
| FAA 448 | 1,954,644 | 476.2 ms | +11.0 MiB |
| NOAA 1834 | 191,548 | 42.3 ms | +32 KiB |
| FAA 226 | 183,297 | 46.0 ms | +96 KiB |
| FAA 288 | 166,035 | 26.7 ms | +128 KiB |
| FAA 286 | 105,105 | 17.9 ms | +96 KiB |
| FAA 302 | 101,478 | 19.6 ms | +96 KiB |

Time is about 0.25 µs per operation and memory is flat: the reader keeps rectangles, not paths, and
the 10,000-painted-region cap already bounds that at a few hundred kilobytes. FAA 448's 11 MiB is
Core Graphics parsing a 1.95-million-operator stream, not the reader's own state.

## What the budget does not bound

The budget is worth less than it looks, and this is the measurement that decides the number.
Exhausting it makes every later callback return immediately, but `CGPDFScannerScan` still parses
the content stream to its end: the reader stops working, the parser does not stop reading. So the
cap does not bound a page's time. FAA page 448, timed through `GraphicsReader.read` itself:

| | budget 100,000 | budget 250,000 |
| --- | --- | --- |
| FAA 448 (1.95 M operations) | 284.5 ms | 230.1 ms |

The two are the same measurement to within run-to-run noise, and both are dominated by parsing a
2.5 MB stream. The arithmetic agrees: 150,000 more charged operations at 0.25 µs is 40 ms at
most, against a floor of roughly a quarter of a second that no budget touches. Raising the budget
therefore costs nothing measurable even on the worst page in the corpus, and lowering it would
save nothing either.

What the budget really bounds is the reader's own accumulated state and the confidence it claims:
a page that exhausts it is preserved whole rather than half read. That is a correctness guarantee,
not a performance one, and it should not be quoted as a time limit.

## The number

**250,000.** It is the smallest round number comfortably above the heaviest real page in the
corpus (191,548, so 1.3× headroom) and an order of magnitude below the one page that looks
adversarial. Any budget between 192,000 and 1,954,000 admits exactly the same pages, so the choice
is not finely balanced — which is the argument for taking the low end of that range rather than a
larger number that would buy nothing and weaken the guarantee. So 250,000 is the branch's number,
but the reasoning above is why it is also the right one.

The bound that survives is: **at most 250,000 charged operations, 10,000 painted regions, 128
saved graphics states and 12 nested Form XObjects per page**, after which the page is preserved
whole. The reader's own work is then bounded at roughly 60 ms and a few hundred kilobytes, but the
page's total cost is not: parsing the stream and rasterizing the fallback are both outside this
budget, and on FAA page 448 they are all of it. A time bound on a whole page would have to be a
different mechanism — a deadline checked in the callbacks and a way to abandon the scan — and
none exists today. FAA 448 still exceeds the budget and still becomes a page image.

## Whole-book effect

Measured on top of the clip change ([clipped-footprints](../clipped-footprints/record.md)), so
this column is the budget alone. Only `faa-phak-8083-25c` changes at all; the other seventeen
corpus documents are identical in words, images and pages with no reflowed text.

| | before | after |
| --- | --- | --- |
| reflowed words | 245,116 | 246,850 |
| images | 617 | 619 |
| pages with no reflowed text | 6 | 2 |

Page by page, all four are pages that were whole-page images and now reflow; no page loses a word:

| page | before | after |
| --- | --- | --- |
| 226 | 0 words, 1 image | 462 words, 1 image |
| 286 | 0, 1 | 311, 2 |
| 288 | 0, 1 | 557, 2 |
| 302 | 0, 1 | 404, 1 |

Pages 226 and 302 were read against the source: each is two columns of prose around a dense
isogonic or air-mass drawing, and the complete left column now precedes the right. Page 448 is
still preserved whole, which is the control.

## Cost in the real conversion

One serial FAA conversion with each binary, `/usr/bin/time -l`, both changes together against
`12225ab`:

| | before | after |
| --- | --- | --- |
| wall time | 47.35 s | 42.91 s |
| peak resident size | 934.8 MB | 861.3 MB |
| EPUB bytes | 264,737,733 | 258,130,382 |

Reading four dense pages costs about 0.2 s of extra scanning and saves more than that by not
rasterizing them at full page size, so the book converts faster, in less memory and smaller. The
`faa-phak-8083-25c` manifest memory ceiling passes unchanged.

The DGA claim in #13 — eight of ten pages rasterized on this cap — is stale: every DGA page is
under 10,000 operations today and none falls back on `main`. Whatever caused that in 2026-09 was
fixed by other work; the budget's effect today is these four FAA pages.

## Tests

`OperationBudgetTests` holds four tests over original one-page PDFs whose content streams are
generated to a chosen operator count. One fails on the old budget: a 150,000-operation drawing is
read rather than rasterized. Three are positive controls that hold either way: a 260,000-operation
page is still preserved whole, the same page is still refused when its operators are hidden inside
a Form XObject, and an ordinary page spends almost none of the budget. The source-derived targets
are corpus contracts requiring FAA pages 226 and 302 to reflow their reviewed text with no
`pageImageFallback`, and FAA page 448 to keep that warning; the first two fail on a converter
built without this change.

## Gates

`scripts/check-all.sh --fast` passes, and all 18 `corpus/regressions.json` cases pass
(`tools/run_corpus_regressions.py`, EPUBCheck 5.x from Homebrew).

## Limits

The survey covers the 24 cached corpus PDFs, which are the documents this project qualifies
against; it says nothing about the distribution in the wild, and a budget chosen from a corpus is
a claim about that corpus. Timing is one run per page on an otherwise loaded developer machine, so
the per-operation figure is an order of magnitude, not a benchmark. The footprint deltas are
sampled around one call and include Core Graphics' own parsing, which is why the heaviest page
shows megabytes where the reader's own state is kilobytes.
