# A printed row the extractor split, left to right (#272)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: every gated case, with *The 9/11 Commission Report* (GPO-911REPORT, 2,475,163 bytes,
SHA-256 `657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b`) as the subject.
Build: this branch merged over `main` at `f2a10fd`, Xcode 27.0, macOS 27.0
(Darwin 27.0.0, xnu-13432.1.9~1); release executable SHA-256
`5a037f4ef599182f1ffd2aea231e80d9f5a69241914e6450d8b6d0b0bb834f26`.
Baseline: `f2a10fd` alone, executable SHA-256
`ff26f25fc5645ddc78117f010c67d4dda63d149348282fe1943ea00da6d3544a`.
`main` moved to `f37d1ab` while this was measured, bringing #270's gutter cut, and every number
below was taken again over that merge — this branch's executable
`9e53a40281a32a0a98eb73798dec67b17ddfeb197a0fba010b3cf9457e0c3b36` against `f37d1ab`'s
`21ba851ba9436e6f4e988643511454ddb48dedd7ce40e98d10d248ad165f0509`. Nothing in the table moved
between them: the same twelve books are byte-identical and the same six move by the same counts.

## The question, and the answer

[#41](https://github.com/vocaro/PDFReflowLib/issues/41) made a printed row the extractor split
stand for one line when the next line's column edge is measured, and held that to right-to-left
writing. [#272](https://github.com/vocaro/PDFReflowLib/issues/272) asks whether the one
left-to-right join the rule then makes in the 9/11 report is right, and, if it is, to drop the
guard.

**The join is right.** Page 259 (printed 241) prints one paragraph:

> We have found no evidence that Iran or Hezbollah was aware of the planning for what later
> became the 9/11 attack. At the time of their travel through Iran, the al Qaeda operatives
> themselves were probably not aware of the specific details of their future operation.

PDFKit hands its second printed row back in two pieces — `ning for what later became` at
x 44.70…151.77 and `the 9/11 attack. At the time of their travel through` at x 156.89…356.71, on
one baseline at y 346.60, 5.11 points apart on a 10.2-point body. The pieces join, and `previous`
then held the second of them, so `continuesParagraph` measured 156.89 against the 44.70 of
`Iran, the al Qaeda operatives themselves were probably not aware of the spe=` and closed the
paragraph. The reading ended one paragraph on `…travel through` and opened the next on `Iran,` —
in the middle of the sentence the page prints. Nothing about that is a judgment call.

**The guard could not simply be dropped.** #272 was written from #41's measurement, which found
that removing it moved the 9/11 report's text and nothing else. That is no longer so: `main` has
moved many times since, and dropping the guard as written moves eight books, several of them
wrongly. Measured at `f2a10fd`, over the eighteen gated cases at `--no-ocr` and fixed packaging:

| what the bare guard removal did | where |
| --- | --- |
| joined a sub-heading into the paragraph it heads | FAA handbook page 367, `ATC Instructions—“Hold Short”` |
| joined two paragraphs across a printed break | USGS MCS 2025 page 2, `World Resources:` and `Substitutes:` |
| split a reference entry from the wrap the page hangs under it | census RRS-2002-01 page 17, `[ 12] Lambert, D.:…` |
| split a footnote from its own second line | IRS Publication 596 page 33, the `***` note |
| ran successive rows of a worked example together | *Beginning and Intermediate Algebra* pages 227, 232, 441 and four others |
| ran successive rows of eight-column tables together, thirty of them | Project Blue Book's statistical appendix |

So the rule is right and its statement was incomplete. What follows is what the pages say.

## What the page says about a row the extractor split

PDFKit ends a line wherever the page leaves a gap, and `continuesRow` reads two pieces standing
closer than a gutter (0.75 of a body) as one row. That is true of two different things, and the
width of the gap tells them apart.

**A gap of at least a quarter of a body is a space the page set between two words.** The pieces
are consecutive words of one printed line, and the row's own start is the paragraph's edge. The
9/11 report leaves 5.11 points on a ten-point body; the replay-clocks paper leaves 3.60 on nine
between `…or if 𝑓` and `occurred far later than`; the census leaves 5.10 on nine between `[ 12]`
and its entry; IRS 596 leaves 3.59 on eight after `***`; the CDC graphic novel leaves 5.00 on
eleven inside a speech balloon.

**A narrower gap is no space at all.** It is the seam between two runs the page set beside each
other on one row, and what the page began that row with says nothing about the line beneath it.
USGS MCS 2025 page 2 closes `…contained an estimated 3.5 billion` at x 522.42 with the 6.5-point
note marker `8` at x 522.48 — six hundredths of a point. The FAA handbook sets `ATC Instructions—`
(11 pt) and `“Hold Short”` (10 pt) touching at x 374.17. *Beginning and Intermediate Algebra* cuts
every one of its equations this way: 1.89 points between `72x2` and `− 2 GCF is 2` on a
11.96-point body, 2.01 between `3y(16x2` and `− 8x + 1)`. Each of those rows is still one row and
its pieces still join into one block; only its start is withheld.

**A gap the page repeats is a column, not a space.** Project Blue Book's statistical appendix
breaks row after row at the same x positions, well inside a gutter's width, and those pieces are
cells. Three rows breaking within a quarter of a body of one place is what it takes to say so:
USCIS M-618-A page 47 breaks two of its sentences within a fifth of a point of x 319.7 and a third
4.5 points from them, and all three are prose. `LayoutReconstructor.columnSeams` reads the page's
seams, and the rule stands aside wherever one recurs, whichever way the writing runs.

**Right-to-left writing is the one place a seam is a line's own.** PDFKit splits those rows at the
boundary between two bidirectional runs rather than at a gap: USCIS M-618-A page 21 hands back
`…الولايات المتحدة` and `. ويطلق بعض الأشخاص` with x 343.03 as the end of one and the start of the
other, and page 47's three seams are 1.66 points and twice 0.00. That is why #41's rule worked
with no gap test, and why a gap test alone would undo it.

Three more things the pieces do not agree about, each measured on a page that needed it:

- **The row's rectangle is both pieces'**, so a row split near its end no longer reads as a line
  that stopped short of the measure. This is what #41 needed and what the Arabic guide's
  paragraphs still need.
- **The row ends where the piece that closed it ends**, so its text and its wrap stay that
  piece's. That is what the writing did.
- **The row is set in the size the page set the wider piece in.** USGS MCS 2025's note marker is
  6.48 points against the row's 10.08, and a row that took its measure from the marker would not
  be compared with the 10.08-point line beneath it at all, because `onStatedLeading` only compares
  lines of one size — so the 22.36 points of baseline the page opens between `World Resources:`
  and `Substitutes:`, against its own 10.53 of leading, would say nothing.

And a split row has **two starts**, its own and the piece's, because which of them the paragraph
stands on is exactly what the split took away. Either will do. The census's page 17 hands back
`[ 12]` at x 134.81 and `Lambert, D.: … Journal of Official Statistics,` at x 157.25 as one row
and hangs `9, (1993) 313–331.` under the entry at x 156.17 — two and a half bodies in from the
row's own start. The row's own start counts only where the line beneath does not begin more than
half a body further out than it: Wallace's page 232 sets `2(36x2`, the next step of a worked
example, fifteen points further out than the row `72x2 − 2 GCF is 2` begins, and a wrap stands on
its paragraph's edge or in from it, never further out.

## What moved, book by book

Every gated case was converted with both executables at `--no-ocr` and fixed packaging
(`--package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`) and compared
entry by entry with `tools/epub_identity.py`. Twelve of the eighteen are **byte-identical**: the
FAA handbook, the Fed, the Dietary Guidelines, *Our Flag*, the copper summary, *Loper Bright*, the
census report, IRS Publication 596 in Chinese, the NBS paper, the NASA slides, the Warren excerpt
and *Agricultural Research*. `--no-ocr` is what makes that comparison meaningful: with recognition
on, the scanned books differ between any two builds because Vision does
([#269](https://github.com/vocaro/PDFReflowLib/issues/269)).

No book's **spine document count** changes. The 9/11 report's boundaries do: 14 of its 35
documents now open on a different block, which is the re-pack #272 predicted, and the Blue Book's
6 of 19 and the replay-clocks paper's 1 of 2 move the same way.

| case | blocks | spine documents | what moved |
| --- | ---: | ---: | --- |
| gpo-911-2004 | 5,047 → 5,045 | 35 → 35 | the page-259 paragraph above, and the same join on page 410 (`…Under the terms o…` and `ligence establishment and be clearly accountable…`). 14 of 35 documents re-open. |
| arxiv-replay-clocks-2023 | 261 → 258 | 2 → 2 | three paragraphs the reading broke mid-sentence at a justified space — `…or if 𝑓` / `occurred far later than`, `…𝑂(𝑥)` / `time where 𝑥…`, `…at the same` / `global time…` |
| cdc-zombie-pandemic-2011 | 289 → 287 | 1 → 1 | two speech balloons read as one utterance again: page 6's `AN EMERGENCY PREPAREDNESS KIT, EH? I BETTER PRINT THIS OUT…` and page 9's `…Mrs. CLEMENTS is a sweet old lady…`. The page images were reviewed; each is one balloon. |
| wallace-algebra-2010 | 9,784 → 9,783 | 14 → 14 | one join: page 185's `World View Note: … the first known use of the negative exponent.` The book's worked examples and answer keys are unchanged — their rows are cut at run boundaries under two points wide. |
| cia-blue-book-14-1955 | 22,445 → 22,436 | 19 → 19 | three table captions joined into the sentence the page prints (`Evaluation of Object Sightings … Less Than One Hundred Miles per Hour .`), a two-cell legend row, and **five table rows in the statistical appendix that should not have joined** — see below. |
| uscis-m618-arabic-2015 | 814 → 815 | 5 → 5 | one paragraph **gains** a break: the second `●●` item of the National Terrorism Advisory System's two alert types now opens its own block, which is what the page prints. The outdent bound is what separates it. |

## What is still wrong

Five rows of Project Blue Book's statistical appendix still take the row beneath them — rows whose
pieces are separated by a real space and whose seam recurs on fewer than three rows of the page,
so neither test reaches them. They are cells of an eight-column table of handwriting-quality
OCR (`6-lnsuffic.lnfo. 7 t? 7 1/.J …` taking `I-Psychological £1 I I CUJ …`), in a book whose
tables the reading has already failed at; the same pages' captions improve. That is
[#285](https://github.com/vocaro/PDFReflowLib/issues/285), filed with this work rather than fixed
inside it: separating a table's rows from a paragraph's wraps on such a page is the scanned-table
problem (#31, #137), not this rule's.

*Loper Bright* still breaks `…the F/V Relentless and the F/V Persistence.¹` from
`These vessels use small-mesh bottom-trawl gear…`, because the footnote marker `1` closes that row
with no space before it. The rule is deliberately conservative there: a row cut at a seam lends
nothing, and the paragraph stays as it was rather than being joined on evidence the page does not
give.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. The corpus lane passes 18 of 18
covered cases, every case's `runPassed` and content assessment read from its own `result.json` and
`content-assessment.json`. The Arabic guide's 26-check content contract — #41's standing control —
still passes on this build.

Four tests are added to `Tests/PDFReflowLibTests/ReadingOrderTests.swift`, each citing #272: the
9/11 page from a checksum-pinned layout capture (`911-259-layout.json`), and the copper page, the
census page and a repeated seam from their measured rectangles. With `readsAsOneLine` returning
`rightToLeft` — the rule as #41 left it — the 9/11 test and the repeated-seam control fail, and
the other two pass, which is what a rule that withholds a row's start should do.

## What is not claimed

One page of the 9/11 report, one of the copper summary, two of the FAA handbook, three of Wallace,
two of the CDC novel, two of USCIS M-618-A, one of the census report and one of IRS 596 were read
against their rendered pages or their printed text; the rest of every book is unread and no case's
`qualifiedForFidelity` changes. A quarter of a body is where a word space begins on the pages
measured here (the narrowest space this corpus sets between two words of one row is 0.40 of a
body, the widest run seam 0.17); a book that justified more tightly than that would have rows this
rule declines to read as lines, which costs it nothing it has today.
