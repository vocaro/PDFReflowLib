# Comic panel order: why no text-only rule reaches it

Investigation of [#18](https://github.com/vocaro/PDFReflowLib/issues/18) on 2026-09-21,
`main` at `96c00a8`, macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max, release CLI at
library defaults. Source `corpus/cache/cdc_6023_DS1.pdf`, SHA-256
`d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3`, 42 pages.
Release executable SHA-256 `fc901ab8041992387475bea575176e616fa77f3cf9968d8856269c89437c9465`.

**No runtime change is proposed or retained, and the issue is not closed.** The owner parked #18
on 2026-09-17 ("Comic panel order is an edge case and not worth the time now. Don't assign work on
this issue"), having asked for an owner decision between raster panel detection, a reviewed
per-book transcription and a documented limitation. This record adds the evidence that decision
needs, measured on today's `main` rather than on the `6992fb3`-era baselines the earlier notes
were written against. It does not take the decision.

## What page 13 does today

`AND SEE WHAT'S HAPPENING...` is still an `h2` and the lower-left balloon is still read first:

```
<p>OKAY, OKAY... I'M COMING.</p>
<p>LET'S TAKE A PEEK OUTSIDE</p>
<h2 id="heading-13-2">AND SEE WHAT'S HAPPENING...</h2>
<p>UH? WHД?</p>
<p>(WHINE!)</p>
<p>WHAT IS IT MAX?</p>
<p>IT'S STILL DARK OUT.</p>
<p>WHAT THE... ?!!</p>
```

Part of what #18 describes has moved since it was filed. [#130](https://github.com/vocaro/PDFReflowLib/issues/130)
measures a recognized line's type size across its own baseline and joins centered lines the
reading says wrap, so the page now has **one** heading where #18 records two: `OKAY, OKAY... I'M
COMING.` has joined `LET'S TAKE A PEEK OUTSIDE` as a paragraph. Vision reads the awakening cry as
`UН? WHД?`; the Cyrillic look-alike rule (#168) rewrites the first token, whose every Cyrillic
character is a Latin look-alike, and leaves the second, where `Д` stands for a drawn `A` that no
substitution can know, so the page emits `UH? WHД?`. The narrative order and the speaker
ownership are unchanged: the lower-left
response precedes the upper-right awakening exchange, so the page still fails its acceptance
target in `corpus/cdc-zombie-pandemic-2011-review.json`.

## Mechanism

`LayoutReconstructor.ordered` tries `gap(horizontal: true)` — the column cut — before
`gap(horizontal: false)`, the row cut. Page 13's eight recognized lines fall into a left group
(x 44.4…189.8) and a right group (x 344.7…562.5). The gutter between them is **154.9 points**,
15.6 times the page's 9.9-point body, so the cut fires and is far wider than the 1.5 bodies below
which the existing prose-columns guard would have asked for substantial text on both sides. The
left group is then emitted whole, before anything on the right.

A plain row-major sort would read page 13 correctly: 709.5 `(WHINE!)`, 654.8 `UН? WHД?`, 498.3
`WHAT IS IT MAX?`, 486.7 `IT'S STILL DARK OUT.`, 346.5 `OKAY, OKAY…`, 326.7 `LET'S TAKE A PEEK
OUTSIDE`, 313.4 `AND SEE WHAT'S HAPPENING…`, 94.1 `WHAT THE… ?!!`. That the right answer happens to
be reachable on this one page is not evidence that it is reachable on the book.

## The measurement that settles it

`gutters.json` records, for every recognized CDC page, the page's own body size, the widest
vertical gap between its recognized lines in points and in bodies, and — where that gap is wide
enough to cut at — how far down the block each side of the cut actually stands.
`signature.json` records, for the same pages, which side of the cut the first emitted line sits on
and whether text standing higher on the page was emitted after it.

The column cut fires on **20 of the 42 pages** (4, 7, 8, 9, 10, 11, 12, 13, 14, 16, 18, 19, 21,
24, 26, 27, 29, 30, 33, 34). The obvious repair — decline a vertical cut whose two sides do not
run down comparable parts of the block, because a short cluster beside a tall one is a caption or
a balloon and not a column — dies on this table. The shorter side's share of the taller:

| Page | Shorter side's share | Left / right line counts |
| --- | --- | --- |
| 30 | 0.028 | 20 / 1 |
| 13 | 0.054 | 3 / 5 |
| 16 | 0.124 | 1 / 4 |
| 14 | 0.297 | 13 / 4 |
| 26 | 0.323 | 8 / 5 |
| 19 | 0.449 | 7 / 6 |
| 24 | 0.586 | 13 / 19 |
| 21 | 0.884 | 17 / 33 |
| 27 | 0.906 | 11 / 24 |
| 33 | 0.962 | 16 / 24 |
| 29 | 0.972 | 7 / 17 |
| 9 | 0.992 | 15 / 7 |

Pages 9, 29, 33, 27 and 21 set two stacks of balloons that each run down almost the whole page.
Geometrically they are a two-column page, and no extent test can tell them from one. A threshold
low enough to spare genuine columns in the other seven books leaves them exactly as they are; a
threshold high enough to reach them declines real columns elsewhere. The same argument disposes of
the earlier audit's observation, recorded in #18's own comments, that
page 24 (wrong) and page 26 (correct) share a balloon layout: that pair shows a text-only rule
cannot separate two pages, and this table shows the separation the whole book would need does not
exist in the geometry at all.

On six of the twenty pages (11, 13, 14, 21, 24, 33) the signature is visible in one line: the
first thing emitted is on the left of the cut while text standing higher on the page is on the
right. The signature is conservative — it catches only the first line, so page 29, whose left
column is read entire before its right, does not appear in it — and it is a description of the
mechanism, not a count of wrong pages.

## What this means for both sides of #18's acceptance

#18 accepts either panel/balloon-aware grouping **or** preserving the affected pages as readable
images with clear limited-reflow signaling.

- **Grouping** needs the panels. No CDC page contains a single path operator; each is one
  full-page scan, so the panel borders exist only in the raster. The recognized text carries no
  signal that separates a balloon stack from a prose column, as the table above shows.
- **Signaling** needs to know *which* pages to signal, and it has the same problem. Page 29's
  geometry is a two-column page's geometry. A per-page trigger built from the recognized text
  would either miss the pages whose two balloon stacks span the page, or fire on genuine columns
  in the other seven books. The only text-only trigger that reaches every affected CDC page is
  the blanket one — every page whose text is fresh OCR of a full-page image — and that fires on
  the scanned pages of the Blue Book, the Warren report, the Arabic USCIS guide and the Chinese
  IRS publication, which reflow correctly. Degrading four correct books to signal one is not the
  honest reading of "when ordering cannot be reconstructed reliably".

So both sides of the acceptance run through the same missing evidence: the panels. That is the
raster route the earlier audit prototyped and rejected — seven thresholds tuned on this one book,
and a dependence on decoded image bytes that differ between launch environments, which is the same
instability recorded for Vision itself in #173. Nothing here reopens that; it establishes that the
second, cheaper-looking side of the acceptance is not in fact cheaper, and that a warning bolted
onto the present output would be the thing #18 explicitly forbids — a claim of correct comic
reading order, or a limited-reflow signal fired on evidence that does not support it.

## Reproduction

```sh
swift build -c release
./.build/out/Products/Release/pdf-reflow corpus/cache/cdc_6023_DS1.pdf /tmp/cdc.epub \
  --package-identifier urn:uuid:00000000-0000-0000-0000-000000000018 \
  --modification-date 2026-01-01T00:00:00Z
swiftc -O $(python3 tools/pdfreflow_tools/swift_sources.py capture-ocr-layout-fixture.swift) \
  -o /tmp/capture-ocr
for p in $(seq 1 42); do /tmp/capture-ocr cdc-zombie-pandemic-2011 $p /tmp/geom/p$p.json; done
```

The two JSONs beside this record are derived from those geometry captures and the converted
book's `EPUB/chapter-1.xhtml`. The captures and the EPUB stay out of the tree
([decision 0006](../../doc/decisions/0006-measurements-are-records.md)). Vision's
reading is not stable across runs (#173): page 35 read `STORM`/`ALL` in the capture and
`STOPM`/`4 L L` in the conversion, and the geometry above is a single run's.

## Related

[#2](https://github.com/vocaro/PDFReflowLib/issues/2) spatial reading order,
[#3](https://github.com/vocaro/PDFReflowLib/issues/3) fallback image readability,
[#7](https://github.com/vocaro/PDFReflowLib/issues/7) suspect inherited text,
[#263](https://github.com/vocaro/PDFReflowLib/issues/263) sideways lettering read across its own
direction — page 17's caption, a separate fault in the same `ordered` reading, still reversed here.
[ocr-headings](../ocr-headings/record.md) holds the rejected heading prototype;
[cdc-zombie-pandemic-2011](../cdc-zombie-pandemic-2011/record.md) holds the book's baseline.
