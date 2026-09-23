# An item carries the whole block that holds the rest of its word (#280)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: every cached source, with *The 9/11 Commission Report* as the subject.
Build: `main` at `0c8ff59` with this change, Xcode 27.0, macOS 27.0 (Darwin 27.0.0).
Baseline: `0c8ff59` alone.

## The three shapes #266 left

[#266](https://github.com/vocaro/PDFReflowLib/issues/266) gives a numbered item the rest of a word
its page broke over the block boundary. It reads one printed line, and only one that opens in
lowercase, so three shapes are left over —
[#280](https://github.com/vocaro/PDFReflowLib/issues/280) names all three, and all three reproduce
on `0c8ff59`:

```
Fed   [128] <pre> …clearing checks, operating the Fed-
      [129] <p>   Wire and automated clearinghouse (ACH) systems, …   ← opens on a capital
9/11 [4004] <pre> 81. …serial 1928; 265A-NY-
     [4005] <p>   280350-302, serial 16379; …                        ← opens on a digit
9/11 [2931] <pre> 22. …For the 1998–2001 num-
     [2932] <p>   bers, see DOJ Inspector General report, …          ← on the next page
```

## What a line-level repair costs, and why this one is not

Relaxing `continuesBrokenItem`'s opening test was tried first and measured. It repairs all three
shapes and introduces two defects of its own, both recorded on the issue:

- **Orphans.** The item join takes *one printed line*. Where the rest of the word is a wrapped
  paragraph of more than one line, the item takes the first and the others are left standing: the
  Fed's item 3 came out followed by a block whose whole text is `and`. Five of the 9/11 report's
  twelve sites did the same.
- **A space in the middle of a serial.** `HyphenRepair.joinOperation` read a line-end hyphen as a
  break only before a lowercase letter, so the repaired text spelled `265A-NY- 280350-302`. That
  was the larger finding and is fixed separately, as [#288](../compounds-broken-at-their-hyphen/record.md).

So the repair here is made over the page's **blocks** rather than its lines, after everything else
has decided what they are, which is how the cross-page join has always worked. A block that ends
where the page broke a word takes the whole of the block beneath it when that block opens the rest
of that word — the whole of it, so nothing is orphaned — and keeps its own kind, because an item
that was holding half a word is still an item. `BlockAssembler.carryBrokenItems` does it within a
page; `LayoutReconstructor.appendPage` now admits a `.preformatted` anchor that ends broken, which
is the only route across one.

## What opens the rest of a word

A lowercase letter, as before. **A line that opens with no letter at all opens no sentence**, so a
serial, a citation or a measure crosses a break the way a word does — unless it opens with a
marker of its own, because that marker opens an item: `82. Ibid.` beneath a hyphen is the next
note. **A capital opens a sentence unless the two halves make a word the book itself writes**, read
from the same `hyphens.vocabulary` that `HyphenRepair` consults, with two letters asked either
side. *The Fed Explained* writes `Fedwire` whole twenty times; `square-` and `Two persons hold the
folded flag` make no word anywhere, which is what keeps #266's contract.

And **a word is what is broken**, so a letter or a digit has to stand in front of the break.
Without that, Project Blue Book moved: its inherited OCR reads the rules its pages are ruled with
as runs of dashes, and blocks whose whole text is `-`, `- -` or `f. Other ------` end in one. That
was fourteen joins of nothing to nothing, and the condition refuses every one.

## What moved, book by book

Every cached source converted with both executables at `--no-ocr` and fixed packaging, one book at
a time. **Eighteen of the twenty-two are byte-identical**, every document of every one — including
Project Blue Book, the FAA handbook, the USCIS Arabic guide and the census paper. Three move:

| case | blocks | joins |
| --- | ---: | ---: |
| gpo-911-2004 | 4,992 → 4,980 | 12 |
| fed-explained-2021 | 842 → 841 | 1 |
| wallace-algebra-2010 | 7,014 → 7,013 | 1 |

All fourteen join sites were read, and every one is a word or a serial the page broke:

```
…operating the Fed-            + Wire and automated clearinghouse (   → FedWire
…varies inversely as the pres- + sure. If the pressure of a certain   → pressure
…Crew Who Fought Back (Harper- + Collins, 2002), p. 107; …            → HarperCollins
…Bin Ladin All Suspects,” CTC 96- + 30015, July 5, 1996; …            → CTC 96-30015
…For the 1998–2001 num-        + bers, see DOJ Inspector General …    → numbers
…“Summary of Penttbom Investi- + gation,” Feb. 29, 2004, …            → Investigation
…Al Qaeda Operative, CTC 2002- + 30060CH, June 27, 2002.              → CTC 2002-30060CH
…Al-Qa’ida Financiers, CTC 2002- + 30138H, Jan. 3, 2003. …            → CTC 2002-30138H
…serial 1928; 265A-NY-         + 280350-302, serial 16379; …          → 265A-NY-280350-302
…Oct. 21, 2003. KSM does acknowl- + edge that the commander …         → acknowledge
…serial 2812; 315N-NY-         + 280350-302, serial 21529; …          → 315N-NY-280350-302
…serial 27063; 315N-NY-        + 280350-DL, serial 2245); …           → 315N-NY-280350-DL
…serial 7228; 315N-NY-         + 280350-F, serial 99; …               → 315N-NY-280350-F
…serial 2268; 315N-NY-280350-  + 302, serials 32036, 9873; …          → 315N-NY-280350-302
```

Four hyphens come out, where the book's own words vouch: `numbers`, `Investigation`,
`acknowledge`, `HarperCollins`. The rest keep the hyphen the page drew, which is what the serials
print. Nothing else in any book's text changes, and **no block is orphaned**: every join removes
exactly one block and adds no other.

Blocks that still end mid-word, counted as a block whose text ends in a hyphen after a letter or
a digit:

| case | before | after |
| --- | ---: | ---: |
| gpo-911-2004 | 32 | 20 |
| fed-explained-2021 | 11 | 10 |
| wallace-algebra-2010 | 8 | 7 |
| cia-blue-book-14-1955 | 83 | 83 |
| faa-phak-8083-25c | 6 | 6 |

What remains in the first three, and all of the Blue Book's and the FAA's, are blocks whose
continuation is not the block beneath them — a crop, a column or a page's furniture stands
between — which is the reading-order question rather than this one.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. The corpus lane passes 18 of 18
covered cases, every case's `runPassed` and content assessment read from its own `result.json` and
`content-assessment.json`. All 679 Swift tests pass, including every #266 contract test unchanged.

One test is added to `Tests/PDFReflowLibTests/BrokenNumberedItemTests.swift`, citing #280: the
capital and the digit, each taking the whole of a multi-line continuation with nothing left over;
#266's own refusal of a new sentence; a line that opens with the next item's marker; and a block
whose whole text is a rule of dashes.

## What is not claimed

The fourteen join sites were read; the rest of every book only through per-document hashes and the
block-end counts above. This says nothing about an item whose remainder the reading puts somewhere
other than the block beneath it, which is what the counts that do not move are, and it does not
give the library a list model: the joined block is still one `<pre>`, which is what #172 and #265
are about.
