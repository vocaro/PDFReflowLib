# A bullet the page hangs clear of its item

Measured under [#261](https://github.com/vocaro/PDFReflowLib/issues/261), baseline `main` at
`94a24ad`, 2026-09-22, macOS 27.0 / Xcode 27, arm64, release CLIs at library defaults, sources from
the pinned corpus cache.

| Binary | SHA-256 |
| --- | --- |
| baseline, `swift build -c release` at `94a24ad` | `f9d610309b54837131b5546cf7a77f34b47fa2911af8152f822115d3bc735c67` |
| candidate, this change on `94a24ad` | `e752d13a349c51796a377bb2fd72c5e153be1f313a014dc9c00180a7d7efc52b` |

## The mechanism

PDFKit ends a line wherever the page leaves a gap. The FAA handbook hangs every bullet 18 points
from its item's own edge on a ten-point body, so page 29 comes back as

```
 38 [ 36.00 212.67 219.67 11.47] | Aeronautical charts depicting permanent baseline data:
 39 [ 45.00 193.67   3.50 11.47] | •
 40 [ 63.00 193.67 210.01 11.47] | IFR Charts—Enroute High Altitude Conterminous U.S.,
```

Two pieces of one printed row are one block within the three quarters of a body a column's gutter
needs (#57), and 14.5 points is 1.45 bodies, so nothing joined them. The marker then reached the
reader either as a block of its own or, where the page set the list's introduction directly above
it, glued to the end of that sentence — `…permanent baseline data: •` — while the item it marks
carried no marker at all and was read as prose.

The gutter bound is the right rule for two pieces of **prose**, which could genuinely be two
columns. A bullet cannot be a column of its own, so for it the bound is the indent a page hangs a
marker in: `LayoutReconstructor.opensAloneAsBullet` reads a line whose whole text is one glyph of
`opensWithBullet`'s set as the marker it is, where the page set the item beside it on its own row,
and `BlockAssembler.marksItem` joins that piece to it across the same indent. The bound is the
marker's alone — once the item has joined, the block is an item like any other and what stands
further along its row is judged by the ordinary gutter again, so the second of page 29's two
columns of items opens its own block as it always did.

This is [#172](https://github.com/vocaro/PDFReflowLib/issues/172)'s rule reaching one glyph
further, and it asks less than #172 does, because a bullet is a marker and nothing else: no list
has to vouch for it, as #254 already reads a bulleted line as an item on the page's word alone. A
number alone on its line still needs its list, because a number with a point is also how a citation
ends.

Two things the page must still state, and both are rules the library already keeps:

- **the item is beside the marker.** A bullet with nothing on its row marks something the reader
  cannot reflow — a key in a legend, an item the page set as a picture — and is left exactly as it
  was. Nothing beneath it is ever taken, because only a piece of the marker's own printed row can
  join it;
- **the marker opens that row.** A piece to its left within the gutter means the extractor cut the
  line out of the middle of a row, so what stands there is whatever the page was printing — the
  minus between two terms of Wallace's derivations, not a marker (#203).

### Where the bounds are

A survey compiled against the library's own extraction read every line of the twenty pinned
sources whose whole text is one marker glyph, with what the page set beside it on its row, each gap
measured in that page's own body (`LayoutReconstructor.bodySize`, the measure every gutter bound in
the library is taken in). It is a single Swift file built from the capture probes' library list and
it was not committed ([decision 0006](../../doc/decisions/0006-measurements-are-records.md)); it
reads nothing the committed capture probes do not already read.

| | lines |
| --- | ---: |
| lines holding one marker glyph and nothing else | 897 |
| …with nothing beside them on their row | 40 |
| …with a piece within the gutter to their left (#203) | 57 |
| …with the piece beside them within the gutter | 204 |
| **…with it between 0.75 and 2 bodies away — what this rule takes** | **556** |
| …with it 2 bodies or more away | 40 |

The corpus leaves a gap exactly where the rule puts its bound. The widest indent taken is 1.89
bodies and the narrowest refused is 2.09; every one of the 40 beyond it is a column of the page or
a cell of a row — the Blue Book sets one 12.2 bodies from its marker and one 50.4, the Warren
Commission 5.2 and 8.1. The 556 are the FAA handbook's 499 (all but four of them `•`, the four a
`-` marking the sub-items of page 30's aircraft classes), NOAA's 47 and ten of the Blue Book's
chart furniture.

**Below the gutter nothing changes**, and the measurement is why. Those 204 lines are already one
block with the piece beside them by the row rule, and a glyph a hair from its neighbor is as often
a fraction's rule or a mark in a scan as a marker: 179 are NOAA's bullets, 16 the Blue Book's axis
ticks, and 9 are Wallace's — page 269 stacks `−` over `3` a quarter of a body apart, the rule of
the fraction `−4/3` and no bullet at all. Reading those as markers would put a formula's own
operators into `<pre>` items, which is the defect #203 was closed for.

## What moved

Both binaries converted every case of `tools/run_corpus_regressions.py --jobs 4` with EPUBCheck.
Each run's EPUBs were read back spine by spine, split into top-level blocks and attributed to the
source page whose marker precedes them.

| Book | non-whitespace characters | blocks | bare markers | blocks ending in a marker | `<pre>` | `<p>` | pages moved |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `faa-phak-8083-25c` | 1,429,886 → 1,429,886 | 8,994 → 9,010 | 54 → 10 | 14 → 1 | 1,316 → 1,391 | 6,423 → 6,364 | 19 |
| `cia-blue-book-14-1955` | 616,207 → 616,207 | 25,330 → 25,328 | 73 → 71 | 84 → 84 | 711 → 722 | 24,198 → 24,185 | 4 |
| the other 16 cases | unchanged | unchanged | unchanged | unchanged | unchanged | unchanged | 0 |

**Not one word of either book changed**: the two runs' word counts are equal for every case, not
one character is lost or gained, and the sixteen other books are identical on every count above.
The handbook's blocks that open with a marker and carry its item rise from 736 to 801, all 65 of
them preformatted items.

The FAA change is the issue's own class, on 19 pages. Page 29 is the reproducer:

```
main       <p>•</p>
           <p>IFR Charts—Enroute High Altitude Conterminous U.S., Enroute Low Altitude …</p>
candidate  <pre>• IFR Charts—Enroute High Altitude Conterminous U.S.,</pre>
           <p>Enroute Low Altitude Conterminous U.S., Alaska Charts, and Pacific Charts</p>
```

The item's wrapped lines stay a paragraph beneath it, which is what "no list model" in
`doc/behavior.md` means and what every other wrapped item in the corpus already does (#266). On
pages 34, 64, 98, 141, 236, 268, 272, 273, 408 and 414 the marker is no longer glued to the
sentence that introduces the list: `…the important factors of takeoff or landing performance are:`
ends where the page ends it.

The Blue Book's are its scanned charts, where the inherited text layer prints an axis tick as a
line of its own. Page 67 sets `-` beside `200`, `175` and `125` and page 133 sets one beside `=`;
they move from a paragraph to a preformatted block and take the fragment beside them —
`<p>-</p><p>=</p>` becomes `<pre>- =</pre>`. The text is identical and the page is noise either
way, which is what #172's record found for the same book; its content contract passes in both runs.
The other two entries in that count of four are one block, `I 2 159 39 37 o. 10` from the
chi-square table on page 73, crossing a spine document's boundary: it stands in the same place in
the reading order, between the same two blocks, as the first block of the next document rather than
the last block of the one before. That is the spine re-packing around the two blocks the change
merged earlier in the book, not a change on page 73.

## What is left, and what it is

Ten bare-bullet blocks remain in the handbook, six on page 31 and four on page 239. They are not
this rule's to fix: `LayoutReconstructor.ordered` hands all six of page 31's markers over before
any of their items, because `columnRuns` (#174) reads the hanging bullets as a column of the page,
so by the time a marker reaches the assembler its row is gone. Run over the twelve marker and item
lines alone, `ordered` returns them interleaved as the page prints them; it is the chaining onto
the introduction's run that makes the marker column. That is
[#279](https://github.com/vocaro/PDFReflowLib/issues/279), filed with the reproducer.

One block still ends in a marker, page 440's `…pilots should also consider the following –`, whose
en dash the page set with nothing beside it on its row: the rule refuses it, as it refuses every
marker whose item the reader cannot find.

## Tests

`Tests/PDFReflowLibTests/LayoutEvidenceTests.swift`, two tests carrying `.bug()` traits for #261,
on hand-made lines with page 29's and page 30's own geometry:

- `aBulletAloneOnItsLineIsTheMarkerItsPageDrew`: the reproducer and page 30's `-` sub-item, then
  the page's evidence taken away one piece at a time — a bullet with nothing beside it, a bullet
  with only the paragraph beneath it, a piece two bodies away, Wallace's fraction rule within the
  gutter, and a piece to the left within the gutter — plus the glyph reader itself, and that
  `isBulletGlyph` and `opensWithBullet` hold the same glyphs and refuse the same non-markers.
- `theItemHangingBesideABulletJoinsIt`: the marker and its item are one preformatted block; the
  introduction keeps its own block; the second column of page 29's row opens its own block; the
  line beneath the item is not taken; and once the item has joined, a piece two bodies along the
  row is judged by the ordinary gutter.

Both fail on the baseline's behavior: `role` returns `.prose` for every bullet above, and the
assembler leaves the marker and its item two blocks.

## Gates

- `scripts/check-all.sh --fast`, foreground, **exit 0**: python-tool-tests, measurements-policy,
  swift-tests, release-build, pdfkit-concurrency, documented-builds, doc-counts, issue-citations,
  fixture-epubs and conversion-policies all PASS. 601 Swift tests, two of them new.
- The corpus lane, `--jobs 4` with EPUBCheck, foreground, **exit 0** on the candidate and on the
  baseline binary. Every case's `result.json` and `content-assessment.json` was opened
  individually: 18 of 18 `runPassed: true`, `structuralCheck: passed`, `epubcheckExitCode: 0`, the
  memory gate `passed`, and an empty `errors` list in every content assessment, on both sides.
  Warren and NOAA remain the two documented exclusions, so what moves in them — the survey says 47
  of NOAA's bullets and none of Warren's — is unmeasured.

## After the merge

`main` moved to `ecee3eb` while this was measured, bringing
[#264](https://github.com/vocaro/PDFReflowLib/issues/264)'s margin-rule reading and
[#273](https://github.com/vocaro/PDFReflowLib/issues/273)'s whitespace-only inline scripts. Merged
at this branch's merge commit, the fast lane passes every gate again and the corpus lane passes
all 18 of its cases, with every `result.json` and `content-assessment.json` read individually:
`runPassed` true, `structuralCheck` passed, EPUBCheck 0, the memory gate passed and an empty
`errors` list throughout.

`gpo-warren-1964-suspect-text-excerpt` is the one case whose verdict moved about while this was
checked, and it is [#269](https://github.com/vocaro/PDFReflowLib/issues/269) rather than anything
here. Two consecutive runs of the merged binary failed it with #269's four page-4 errors — `missing
text 'and he told me about the things at'`, `missing text 'At 6:00 PM I instructed the officers to
bring'`, `unwanted text 'ftboot'` and `missing quality warning` — and a release binary built from
`ecee3eb` itself, with none of this change in it, failed the same case with the same four errors in
the same conditions. Three later runs of that same merged binary, byte for byte the one that had
failed (`5fd26d2675ae268771a056ce3cfe06cea10f6c3bbdbc907a0900e5070e7bfc6e`), pass it: the whole
lane green, then the case twice on its own. The case also passes on the baseline `94a24ad` and on
this change measured against it.

So that page's verdict is not stable **within** one binary either, which is one step past what #269
records — it measured two binaries each stable at a different Vision reading. Nothing here reaches
it: page 4 is a carbon typescript whose inherited layer `RecognitionPolicy` weighs against the
recognition, and the extraction pass that decides it runs before any block is reconstructed. The
observation is added to #269.

The per-book table above is measured against `94a24ad` as it says, on the two binaries named there.

`main` moved once more, to `2511584`, bringing #245's rule for a numbered item the page breaks
mid-word — a change in the same `.prose` branch of `BlockAssembler.append` this one adds to. Merged
again: the fast lane passes every gate, the corpus lane passes all 18 cases with both files read
for each, and the handbook still holds 10 bare markers, one block ending in a marker and 1,391
preformatted blocks, exactly as the table above records. The two books that differ from the
previous merge differ by that merge's own work and not by this one — one character in the handbook
and two blocks in the Fed book, neither of them a marker.
