# A folio is not a title (#290)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: every cached source, with *Our Flag* (`CDOC-108hdoc97`) as the subject.
Build: `main` at `72dc8d4` with this change, Xcode 27.0, macOS 27.0 (Darwin 27.0.0).
Baseline: `72dc8d4` alone.

## The defect

*Our Flag* states no usable table of contents of its own, so its navigation is built from the
headings the reading detects. **Fifteen of its fifty-four navigation entries were page numbers:**

```
… Fifteen Stars and Stripes · Early American Flags · Historical Flags · 9 · The Flag Today …
```

and then `26` through `39`. A reader opening the table of contents met bare folios among the
chapter titles.

Two things had to go wrong together, and both are known:

1. **The folio is not removed.** Page 33 prints `27` at 0.081 of a 652-point sheet, where the
   footer candidate band reaches 0.07. That band is narrow on purpose — `doc/behavior.md` records
   that widening it "would disturb the alphabetical row order of the illustrated entries on Our
   Flag pages 34/42/43 without independent layout work" — so this half is a stated cost.
2. **The folio becomes a heading.** These are picture pages carrying a few lines of 7-point
   caption, so the page's body is 7.00 and the 8.93-point folio clears the quarter-over-body
   heading threshold. Nothing then asked whether a bare number can be a title.

```
pos=0.0809  fs=8.93  '27'          ← the folio
pos=0.1761  fs=7.00  'on the 80th Psalm.'
pos=0.5954  fs=7.00  'CALIFORNIA'
```

The second is the one with no reason behind it, and it is the one fixed here. Refusing to call a
folio a *title* moves nothing in the reading order, so it does not touch what (1) protects: the
line still reflows, as text.

## The rule

`isFolioInTheMargin` refuses the title reading to a line of at most four marks that holds a digit
and no letter, standing in the outer tenth of the page at either edge.

The outer tenth, and a bare number only, because two other things look like this and are not
folios:

- The 9/11 report sets its **chapter numbers above their titles** — `1` over `“WE HAVE`, `2` over
  `THE FOUNDATION OF` — at the head of a chapter-opening page and well inside the type area.
  Thirteen of that book's headings are bare numbers for that reason, and none of them reaches a
  reader's table of contents, because that book states an outline of its own.
- IRS Publication 596's `1.` to `6.` are **numbered section headings**, and a running head that
  carries words beside its folio — `“WE HAVE SOME PLANES” 15` — is a head, not a number.

Counted over every cached book at `--no-ocr`, headings whose whole text is a number: *Our Flag*
15 of 54, the 9/11 report 13 of 73, IRS 596 7 of 85, the cached NASA paper 2 of 16, the FAA
handbook 1 of 635, USCIS M-618-A 1 of 102.

## What moved

**Twenty of the twenty-two cached sources are byte-identical.** Two move, and in both the change
is only the *kind* of a block:

| case | blocks | marks | text |
| --- | ---: | ---: | --- |
| gpo-our-flag-2003 | 684 → 684 | 66,893 → 66,893 | identical, character for character |
| `20200002975` (cached, not in the manifest) | 480 → 480 | 40,005 → 40,005 | identical |

Fifteen `<h2>` become `<p>` in *Our Flag* — `9`, `26`, `27`, `28`, `29`, `30`, `31`, `32`, `33`,
`34`, `35`, `36`, `37`, `38`, `39` — and two in the NASA paper, which are the folios #171 item 3
records. Nothing is added, removed, split or reworded in either book.

Its table of contents goes from 54 entries to 39, and the 15 that go are exactly those numbers.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. The corpus lane passes 18 of 18
covered cases, every case's `runPassed` and content assessment read from its own `result.json` and
`content-assessment.json`. All 685 Swift tests pass.

One test is added to `Tests/PDFReflowLibTests/LayoutEvidenceTests.swift`, citing #290: a bare
number at either margin refused, the same number inside the type area still a title, a numbered
section heading in the margin still a heading, a running head carrying words beside its folio
still a heading, and a figure too long to be a page number left alone. With the guard removed, the
two refusals fail.

## What is not claimed

This fixes the second half only. The folio still reflows as text at the foot of each of those
pages, because the footer band that would remove it is narrow for a reason measured elsewhere, and
nothing here bears on that. Four marks and the outer tenth are where this corpus's folios sit;
a book that set a longer page number, or set it further in, would keep the reading it had.
