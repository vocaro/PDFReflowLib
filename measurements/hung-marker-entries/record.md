# A reference list hung under an outdented marker column is one entry per paragraph (#282)

Tier: deterministic Apple PDF stack; source-derived extraction fixtures for the two pages, and an
isolated macOS arm64 release CLI at `--no-ocr` with fixed packaging for the corpus comparison.
Corpus: `arxiv-replay-clocks-2023` page 10 and `census-rrs2002-01` page 17, with all 23 cached
sources converted for the comparison.
Build: this change over `main` at `2001391`, Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0 (26A428,
Darwin 27.0.0, xnu-13432.1.9~1); release executable SHA-256
`78416ee97cbbf61a04fe7142e5cabe40552d5611ea5d7c3d407f23b208c70b67`, against `2001391`'s
`ff3bbc7e4070a4df9ec44c89918000729c129b8f138d669316933a97c4f72aca`.

## What the two pages were reading

Both pages set a reference list with the citation number outdented into the margin and the entry
hung at an indent. Three things kept the entries apart, and none of them is about this shape in
particular:

- **The hang is wider than the column test allows.** `BlockAssembler.continuesParagraph` joins two
  lines of one column within one and a half bodies. Replay Clocks hangs 12.19 points on a
  9-point body (1.35) and 15.26 on entry 11 (1.70); the Census paper hangs 21.35 (2.37). So every
  wrap opened a paragraph of its own wherever the ordinary test refused it.
- **`hangingEntries` (#160) asks the wrap to stop a body short of the entry's right edge.** A
  justified reference list never does: both lines reach the margin. Replay Clocks' entry 11 passes
  every other condition of that rule and is refused by this one, and by the rule's own requirement
  of three candidates on one wrap edge — only one entry of the twelve hangs that wide.
- **A marker the extractor kept apart joined the paragraph above it.** `[8]` arrives at x=321.20
  with its entry at x=333.39, 12.19 points away, past the three quarters of a body two pieces of
  one printed row are joined within. So page 10 read `… Univ., Department of Computer Science,
  1988. [8]` and opened the next paragraph on `D. L. Mills. …`. Six of Replay Clocks' twelve
  entries and eight of the Census's fourteen arrive that way.

## What the page states

The marker column. A page that outdents three or more bracketed numbers from one edge, each with
an entry of at least twelve bodies beside it on its own row, and hangs at least one further line
on that edge, has told the reader where every entry begins. `LayoutReconstructor.hangingMarkerList`
reads exactly that and returns the lines that open an entry and the edge the entries stand on.
From it the assembler takes three things: a line that opens an entry never continues the paragraph
above it; the entry beside a marker is that marker's own text, however far the page hung it, for
the same reason a bullet's item is (#261); and a line standing on the entry edge that opens no
entry carries on the one above it, whatever its measure.

On such a page — and only on such a page — two pieces of one printed row are read as one line
before anything is decided from how far the piece before them ran. Replay Clocks breaks entry 4
after `…with physical clocks.` and sets `In Proceedings of the 23rd International Conference on`
5.4 points along that same row. Asked of every page, that same reading moves seven of the
twenty-two cached books and takes characters out of two of them, so it is asked only where the
page has said where its entries begin and end.

Only a bracketed number is read. The marker shapes `isList` also accepts — `8.`, `a)` — open the
numbered items, headings and worked steps this library reads other ways, and what they would
settle is #171's own reference lists, measured there.

## Before and after

Page 10 of the Replay Clocks paper: twelve references, twelve paragraphs, each opening on its own
number. Before, entries 1–7 stood in two paragraphs with `[8]` stranded at the end of one of them,
entry 4 was three paragraphs, and entry 11 was two.

```
-<p>REFERENCES [1] Ivan Beschastnikh, … 2016. [2] Colin J Fidge, … 1988.</p>
-<p>[11] Mukesh Singhal and Ajay D. Kshemkalyani. An efficient implementation of</p>
-<p>vector clocks. Inf. Process. Lett., 43(1):47–52, 1992.</p>
+<p>[1] Ivan Beschastnikh, … 2016.</p>
+<p>[2] Colin J Fidge. … 1988.</p>
+<p>[11] Mukesh Singhal and Ajay D. Kshemkalyani. An efficient implementation of vector clocks.
+    Inf. Process. Lett., 43(1):47–52, 1992.</p>
```

Page 17 of the Census paper: fourteen references, fourteen paragraphs. Before, eight of them had
their number in a paragraph of its own and the entry in the next, and entry 13 broke `Public Use
Mi-` from `crodata` across the two — the single word #268 recorded as its own corpus cost, which
was this issue's to settle.

## Corpus

All 23 cached sources converted with the executable before this change and with it, at `--no-ocr`
with fixed packaging, so two books differ only where the reading does. The full Warren report and
the NOAA assessment are excluded, as the corpus lane excludes them: both exceed the default output
budget and write no book (#242, #5).

This change and #277's share one measurement run, because they are in one tree; each book below
is named by the rule that moved it. **Eighteen of the twenty-two are byte-identical.** Two move
here:

| book | documents | what moved |
| --- | --- | --- |
| `arxiv-replay-clocks-2023` | 1 of 3 | the references page: 22 blocks become 25, and the letter stream is unchanged |
| `census-rrs2002-01` | 1 of 2 | the references page: 400 blocks become 387, and one word is repaired |

The Replay Clocks paper's reference page gains three blocks because entries that were running
together are now one entry each; nothing in the book's letters moves. The Census paper's page
loses thirteen blocks for the same reason — eight stranded citation numbers rejoin their entries —
and its only text change in the whole book is the one word #268 recorded as its cost:

```
-for Masking Public Use Mi- crodata, U.S. Bureau of the
+for Masking Public Use Microdata, U.S. Bureau of the
```

The other two books that move in this run, Project Blue Book and the civil-complaint form, are
#277's and are measured there.

## Gates

`swift test` passes with the four new tests. The five tests that exercise Vision fail and pass on
this host by the hour, independently of this change, for the reason recorded in
measurements/warren-excerpt-recognition-comparison/record.md; they passed on this tree earlier in
the same session and were failing again when it was committed.
