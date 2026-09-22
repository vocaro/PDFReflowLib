# 0011 A picture a cross-page join steps over keeps its side of the page marker

## Context

`LayoutReconstructor.appendPage` joins a paragraph the previous page left open to the paragraph
the next page opens with, and records the boundary as a `.sourcePage` element *inside* the joined
paragraph. Where no join happens, the boundary is a standalone marker block instead. That is the
contract the streamed blocks carry to the writer ([decision
0008](0008-streamed-blocks-to-the-writer.md)): every block before a marker is content of the pages
up to it, and every block after it is content of the pages from it.

The join required the two paragraphs to be adjacent blocks. A page that prints a box or a figure
at its foot puts an image block between the paragraph and the page boundary, and a page that opens
with one puts an image block between the boundary and the paragraph, so the two halves were never
adjacent and the join never ran. The Fed sets Box 3.5 at the foot of page 47 and the paragraph
that names it — `…(See box 3.5 for more details…) The vast major-` — runs on to page 48, where
`ity of the Federal Reserve's assets…` opened a paragraph of its own with the word broken between
them ([#177](https://github.com/vocaro/PDFReflowLib/issues/177), item 1, whose fix lives only on
the abandoned coordination branch, [decision
0005](0005-abandoned-coordination-branch.md); [#203](https://github.com/vocaro/PDFReflowLib/issues/203),
item 1).

Joining means moving those images, because a paragraph is one block and nothing can stand inside
it. Where they go is the decision: it is a statement about where content sits relative to a source
page's marker, which is what a reader jumps to, what the page-list names and what an internal link
aims at.

## Decision

A cross-page join steps over the image blocks between its two halves, and **each image it steps
over keeps the side of the page boundary its own page is on**. The earlier page's images are
placed before the joined paragraph; the later page's after it. Boxes and figures are the same
block kind and take the same rule — there is one placement rule, not two.

The marker is inside the paragraph, so this is the only placement that keeps every block on the
page it came from. Placing page 47's box after the joined paragraph would carry page-47 content
past the page-48 marker; placing page 48's rule before it would carry page-48 content back before
its own marker.

The join's own conditions do not change: a paragraph on each side, the band test, the lowercase
opening, the unterminated ending and the tagged-identity test. An image stops being a barrier only
where two paragraphs already ask to be joined, so nothing is reordered on a page whose paragraph
simply ends.

One condition is added, because reaching past a picture asks more than standing beside the
boundary did. A block reached past a picture is being called a paragraph the page interrupted, so
it must read as the page's prose — `readsAsSentence`, the four-word test the crop rules already
use. A folio, a figure number or a stray mark is not one: the 9/11 report prints `145` under page
163's column and page 164 opens with a crop, and that folio would otherwise take page 164's
opening words. The block directly before a boundary is reached whatever it holds, exactly as
before, so [#45](https://github.com/vocaro/PDFReflowLib/issues/45)'s own defect — a join anchored
on a folio that is simply the last block — is untouched, and this decision does not pretend to
fix it.

Reconstruction's held-back tail grows to match. `LayoutReconstructor.amendableTail` is the
trailing block as before, or — where images stand at the tail — the paragraph beneath them
together with those images, because all of them are still open. It cannot grow past one page's
pictures: a page that opens no paragraph appends its own marker, and a marker is not a paragraph,
so the walk stops there and the tail is one block again.

## Consequences

- The box reads before the sentence that refers to it, which is where a reader wants it, and the
  broken word closes. Thirty paragraphs join across a page boundary that did not before: the Fed
  12, the 9/11 report 7, the Census paper 5, Wallace 4, the magazine 1 and the CIA report 1.
  Twelve of the eighteen corpus books are unchanged.
- Four of Wallace's joins are a known cost. On that book a crop has often already taken the lines
  that actually continue the sentence — page 288 loses `The trick in this` into a display — so the
  two halves the join now brings together were never consecutive. No word moves and none is lost:
  what changes is that two already-garbled fragments read as one paragraph rather than two blocks.
  The reading-order anchor #45 describes is what would fix those, and it is not this decision.
  **Closed since, without that anchor.** All four are boundaries where the crop took what the
  *later* page printed before its first reflowed line, and a join now reaches only a block the
  page's own text begins at, so none of the four is made
  ([#267](https://github.com/vocaro/PDFReflowLib/issues/267),
  [cross-page-crop-anchors](../../measurements/cross-page-crop-anchors/record.md)). The earlier
  page is read no differently — asking the same of it is the variant this record rejected — so a
  paragraph whose own last line a crop took is still #45's defect.
- A figure that stood at the foot of a page now stands before that page's last paragraph. That is
  a change in reading order within one page, taken only when the paragraph demonstrably continues
  overleaf, and it is the cost of the join.
- `amendableTail` is a second place that knows what a join can reach. It is derived from the same
  walk `appendPage` performs, and the test pins the two together.
- Decision 0008's promise is unchanged in kind: reconstruction still holds a bounded tail and
  never the block list.
- Twelve of the Fed's inline markers showed a physical page number where a standalone marker
  would have shown the number the page prints, because `EPUBWriter` passed its labels only to the
  standalone path. That is corrected here rather than shipped
  ([#248](https://github.com/vocaro/PDFReflowLib/issues/248)).

## Evidence

[measurements/box-placement-and-split-rows](../../measurements/box-placement-and-split-rows/record.md).
