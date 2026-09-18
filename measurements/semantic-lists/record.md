# Semantic lists: what the corpus's `preformatted` blocks actually are

Survey for [#29](https://github.com/vocaro/PDFReflowLib/issues/29) part (b). This is a
measurement, not a change: nothing under `Sources/` was touched and no conversion behaviour
was altered. The owner approves the classes before anything is implemented.

*Since implemented for the two safe classes (#194): see the [real-list record](../real-lists/record.md).*

Today every list item is a `ReflowBlock.Content.preformatted` that keeps its printed marker
(`1)`, `•`, `a.`) and is written as `<pre>…</pre>`
(`EPUBWriter.swift:168`). The question is which of those blocks are really lists, what markup
each wants, and what changes if they move.

## What was measured

Every English corpus document was converted with the release converter built from this
branch's HEAD (`1a7b008` merged), and every `<pre>` element in the resulting EPUB spine was
recorded with its source page, its position among the chapter's top-level blocks, its own
line breaks, and the marker its first line opens with.

```sh
swift build -c release
.build/release/pdf-reflow corpus/cache/<file>.pdf /tmp/<case>.epub \
  --package-identifier urn:uuid:00000000-0000-4000-8000-000000000000 \
  --modification-date 2026-01-01T00:00:00Z
python3 measurements/semantic-lists/survey_pre_blocks.py /tmp/<case>.epub \
  --case <case> --output /tmp/<case>.json      # extract the blocks
python3 measurements/semantic-lists/classify_pre_blocks.py /tmp/*.json [--samples 5]
python3 measurements/semantic-lists/list_shape_stats.py /tmp/*.json
```

`classify_pre_blocks.py` assigns a class to each block and writes it back into the survey;
`list_shape_stats.py` then reports run-level shape — how many lists, where numbering restarts,
where it is not consecutive, where another block interrupts a run. Both are idempotent. The
classification rules are a measurement aid, not proposed converter behaviour: they are
documented in the scripts, and any block no rule reaches is reported rather than guessed at.
Delete each EPUB as soon as its survey is written; NOAA alone is 502 MB and Warren 333 MB.

**Coverage.** All 22 gated cases except the two non-English ones
(`uscis-m618-arabic-2015`, `irs-p596-zhs-2025`), which the brief excludes, plus
`gpo-warren-1964`, which is excluded from the corpus lane by #5. Warren does not convert at
the default 512 MiB image-output budget; it was converted once with
`--full-page-image-encoding smallest:0.6 --region-image-encoding smallest:0.6
--maximum-output-bytes 2147483648` purely to obtain its text. **Warren's numbers therefore
come from a non-default option set** — image encoding does not affect layout reconstruction,
so the text blocks should be identical, but that was not independently verified, and Warren
is reported separately below rather than folded into the gated totals.

Three gated cases emit no `<pre>` at all: `usgs-mcs2025-copper`,
`usda-ars-agresearch-2012-11`, `ntrs-20210020887-techport-thm-2021`.

**Totals.** 22,100 `<pre>` blocks. 15,020 of them in the 20 gated English cases; 7,080 in
Warren.

## The classes

| Class | Blocks | Books (blocks/pages) | Becomes a list? |
|---|---:|---|---|
| bibliography-entry | 9,251 | noaa 9,251 / 599p | Not yet — see risk |
| endnote-entry | 6,469 | warren 6,469 / 63p | Not yet — see risk |
| answer-key-entry | 1,615 | wallace 1,615 / 47p | No |
| bulleted-list-item | 1,304 | faa 813/115p, 911 179/50p, noaa 167/30p, fed 78/19p, dga 18/4p, cia 15/12p, wallace 11/3p, dasc 9/2p, gwl 5/1p, scotus 5/1p, warren 4/3p | **Yes — `<ul>`** |
| exercise-item | 1,123 | wallace 1,123 / 66p | No |
| display-math-row | 426 | wallace 426 / 65p | No — stays `<pre>` |
| ocr-debris | 421 | cia 341/132p, warren 64/19p, 911 10/1p, dasc 3/2p, gwl 3/1p | No |
| numbered-list-item | 399 | faa 216/55p, warren 98/16p, fed 24/8p, 911 17/5p, census 16/1p, earthdata 14/3p, our-flag 7/1p, dasc 4/1p, noaa 2/2p, cia 1/1p | **Yes — `<ol>`** |
| entry-continuation | 393 | noaa 304/175p, warren 89/46p | No — a defect |
| questionnaire-item | 237 | cia 237 / 23p | Ambiguous |
| testimony-turn | 228 | warren 228 / 37p | No |
| singleton-marked-line | 82 | cia 32/31p, warren 28/26p, 911 9/3p, faa 4/3p, + 8 books 1 each | Ambiguous |
| elision | 69 | warren 68/57p, scotus 1/1p | No |
| lettered-sub-item | 39 | warren 28/9p, cia 7/5p, 911 2/1p, earthdata 2/1p | **Yes — nested** |
| contents-or-section-title | 18 | nbs 6/4p, 911 9/3p, gwl 3/1p | No — a defect |
| note-asterisk | 14 | fed 5/5p, warren 4/4p, cia 3/3p, 911 1/1p, noaa 1/1p | No |
| form-section-title | 7 | uscourts 7 / 4p | No — a defect |
| coded-report | 4 | faa 4 / 4p | No — stays `<pre>` |
| unmarked-preformatted | 1 | 911 1 / 1p | No |

Per book, counting only the eight classes that are list-shaped
(`numbered`, `bulleted`, `lettered`, `exercise`, `answer-key`, `bibliography`, `endnote`,
`questionnaire`):

| Book | `<pre>` blocks | list-shaped | would stay `<pre>` | pages with `<pre>` | pages with a list-shaped `<pre>` |
|---|---:|---:|---:|---:|---:|
| noaa-nca5-2023 | 9,727 | 9,420 | 307 | 641 | 631 |
| gpo-warren-1964 | 7,080 | 6,599 | 481 | 206 | 89 |
| wallace-algebra-2010 | 3,175 | 2,749 | 426 | 156 | 116 |
| faa-phak-8083-25c | 1,037 | 1,029 | 8 | 162 | 160 |
| cia-blue-book-14-1955 | 636 | 260 | 376 | 163 | 36 |
| gpo-911-2004 | 228 | 198 | 30 | 60 | 56 |
| fed-explained-2021 | 108 | 102 | 6 | 32 | 27 |
| dga-2025-2030 | 18 | 18 | 0 | 4 | 4 |
| census-rrs2002-01 | 17 | 16 | 1 | 2 | 1 |
| ntrs-20190030725-dasc-2019 | 17 | 13 | 4 | 5 | 3 |
| ntrs-20180003024-earthdata-slides-2018 | 16 | 16 | 0 | 3 | 3 |
| ntrs-20200002975-gwl-2020 | 11 | 5 | 6 | 2 | 1 |
| gpo-our-flag-2003 | 7 | 7 | 0 | 1 | 1 |
| scotus-loper-bright-2024 | 7 | 5 | 2 | 3 | 1 |
| uscourts-pro-se-1-2016 | 7 | 0 | 7 | 4 | 0 |
| nbs-jres-geltman-1977 | 7 | 0 | 7 | 4 | 0 |
| arxiv-replay-clocks-2023 | 1 | 0 | 1 | 1 | 0 |
| cdc-zombie-pandemic-2011 | 1 | 0 | 1 | 1 | 0 |

## Run shape

A *run* is a chain of sibling markers using the library's own rule
(`LayoutReconstructor.ListMarker.isSibling`: same kind, same punctuation, value one or two
apart) over `<pre>` blocks that are adjacent in the spine and on the same page or the next.
A *contiguous piece* is a run with no other block (a paragraph, a figure, a heading) sitting
between two of its items — that is what a writer could wrap in one `<ul>`/`<ol>` without
moving anything.

| Class | items | runs | contiguous pieces | pieces of one item | pieces crossing a page | pieces crossing a spine file |
|---|---:|---:|---:|---:|---:|---:|
| bibliography-entry | 9,251 | 571 | 2,446 | 818 | 369 | 28 |
| endnote-entry | 6,469 | 366 | 2,302 | 1,151 | 0 | 1 |
| answer-key-entry | 1,615 | 413 | 480 | 326 | 15 | 0 |
| bulleted-list-item | 1,304 | 159 | 345 | 68 | 20 | 2 |
| exercise-item | 1,123 | 241 | 312 | 141 | 9 | 2 |
| numbered-list-item | 399 | 81 | 167 | 77 | 4 | 0 |
| questionnaire-item | 237 | 116 | 153 | 106 | 0 | 0 |
| lettered-sub-item | 39 | 16 | 28 | 21 | 0 | 0 |

The gap between `runs` and `contiguous pieces` is the whole difficulty. For NOAA's
bibliography the gap is almost entirely one intervening block — the wrapped continuation of
the previous reference, which became a `<p>` — so the "list" fragments into 2,446 pieces,
818 of them a single entry. For the FAA handbook the gaps are larger (3 to 20 blocks) because
a bulleted list in the left column is interrupted by the right column's prose and by
preserved figures.

---

## Class by class

### 1. bulleted-list-item — 1,304 blocks, 11 books, 240 book-pages → `<ul>`

**Evidence.** The line opens with `•` (1,270), `-` (33, mostly DGA) or `*` (1); the run is
several such lines at one indent; text reads as prose. No numbering to preserve.

> `• Alternator/generator switch` — FAA p190
> `• Best rate-of-climb speed (VY)—the airspeed that provides the most altitude gain in a given period of time.` — FAA p212
> `• activating a special court to enable the use of classified evidence in immigration-related national security cases;` — 9/11 p205
> `• Planning relocation from high-risk coastal areas {9.3}` — NOAA p42
> `- Ages 9–13: less than 1,800 mg per day` — DGA p6

**Should it become a list?** Yes. This is the safest class in the corpus: unordered, so no
renumbering risk, and the bullet glyph carries no information a `<ul>` marker does not.

**Risk of getting it wrong: low.** The only real hazard is the run boundary. 78 of 159 runs
are interrupted by another block, and 9/11 pages 204–205 show why the interruption matters:
two separate lists, each with its own lead-in paragraph (`They included` … `Clarke's working
group compiled new proposals as well, such as`), are one run under the sibling rule. A
grouping that ignores intervening blocks would merge them or, worse, reorder them.

**Markup.** `<ul><li>…</li>…</ul>`, bullet glyph removed from the item text.

**Caveat found while measuring.** `LayoutReconstructor.isList` accepts only `[•*−-]` as a
bullet. DGA's *top-level* bullets are `+`, which it does not accept, so all 68 of them are
`<p>` while their `-` children are `<pre>`. On DGA page 7 the parent items are paragraphs and
the child items are preformatted — the nesting is inverted in the output. Any nesting work has
to widen the bullet set first, and that is itself a behaviour change with its own blast radius.

### 2. numbered-list-item — 399 blocks, 10 books, 93 book-pages → `<ol>`

**Evidence.** `N.` or `N)` opening a prose line, in a run of consecutive values, at one
indent, usually under a lead-in sentence.

> `1. Two persons, facing each other, hold the flag waist high and horizontally between them.` — Our Flag p26 (a clean 1–7)
> `3. ascertain the extent of the bank's compliance with banking laws and regulations;` — Fed p75
> `1. Enter pattern in level flight, abeam the midpoint of the runway, at pattern altitude.` — FAA p355
> `1. Total income` … `16. Schedule F flag` — Census p3
> `3. Date and time of origin—time and date (081125Z) of TAF origination is given in the six-number code…` — FAA p319

**Should it become a list?** Yes.

**Risk: low to moderate.** 11 of 81 runs do not start at 1 (a list continued from the previous
page, or split by a column cut), 13 have a gap, 6 descend. Rendering such a run as a plain
`<ol>` would print numbers the source does not have.

**Markup.** `<ol start="N"><li>…</li>…</ol>` with the printed marker removed **only** where
the run's values are verified consecutive and ascending; otherwise keep the marker and use
`<ul>` styled without a marker, or leave the block preformatted.

### 3. lettered-sub-item — 39 blocks, 4 books, 16 book-pages → nested `<ol type="a">`

**Evidence.** `a.`/`b.`/`c.` or `A.`/`B.` following a numbered item at a deeper indent.

> Earthdata slides p7, verbatim from the EPUB:
> ```
> <pre>1. Enable big compute next to big data</pre>
> <pre>2. Encourage user adoption of cloud for analytics</pre>
> <pre>3. Maximum analytics capability at minimum cost</pre>
> <pre>a. Use capabilities within NASA more effectively and efficiently</pre>
> <pre>b. Leverage analytics capabilities of external partners</pre>
> ```
> `b. From the margin of the laceration in the corpus callosum.` — Warren p572 (b–e under one item)
> `B. Such sworn depositions may be taken only from witnesses designated in writing…` — Warren p529

**Should it become a list?** Yes, as a nested list inside the preceding `<li>`.

**Risk: moderate.** The count is small (39 blocks, 28 contiguous pieces) but the *evidence for
nesting is not in the document model at all* — see the sketch. A lettered run that is not
actually subordinate (Warren page 529's Commission rules `A.`–`E.` are top-level) would be
nested wrongly. Depth must come from measured indentation, not from marker kind.

### 4. exercise-item — 1,123 blocks, Wallace pages 2–423 (66 pages) → **stay preformatted**

**Evidence.** `N)` opening a short mathematical expression or a word problem, in the exercise
sets of *Beginning and Intermediate Algebra*.

> Wallace page 10, first fourteen blocks in emitted order:
> `1) 1− 3`, `3) (− 6)− (− 8)`, `5) (− 3)− 3`, `7) 3− (− 5)`, `9) (− 7)− (− 5)`, `11) 3− (− 1)`,
> `13) 6− 3`, … `43) (− 5)(4)`, then `2) 4− (− 1)`, `4) (− 6) +8`, `6) (− 8)− (− 3)`, …

**Should it become a list? No.** The blocks are emitted **column-major**: the whole left
column (odd numbers) precedes the whole right column (even numbers). 101 of 241 runs step by
exactly 2. An `<ol>` renders 1, 2, 3, 4 …, which would print *wrong exercise numbers* against
the source on essentially every exercise page. 204 of 241 runs do not start at 1 and 116 have
a gap. An `<ol>` here trades a correct-but-flat rendering for an incorrect one.

**Risk of getting it wrong: high.** This is the class the issue names, and it is the one class
that must not move until column-major ordering is fixed (#178 covers the answer-key case).

**Markup.** Stays `<pre>`. If it must become a list later, the prerequisite is row-major
emission; only then can `<ol start>` be trusted.

### 5. answer-key-entry — 1,615 blocks, Wallace pages 438–489 (47 pages) → **stay preformatted**

**Evidence.** The same `N)` marker in the book's answers section, with a terse value.

> `1)− 2`, `2) 5`, `3) 2`, `4) 2`, `5)− 6`, `6)− 5` — p438
> `d. no e. yes f. no` — p484 (three answers merged into one block)
> `a. 740.12; 745.91` — p487

Page 463's markers arrive as `7, 17, 27, 8, 18, 28, 9, 19, 29, …` — a three-column key read
down each column (#178). 364 of 413 runs do not start at 1; 326 of the 480 contiguous pieces
hold a single entry.

**Should it become a list? No**, for the same reason as the exercises, more strongly: the
numbering here *is* the link to the exercise it answers, and a renumbering would silently
break that link. Some pages print only the odd exercises.

**Risk: high.**

### 6. bibliography-entry — 9,251 blocks, NOAA, 599 pages → not yet

**Evidence.** `N.` followed by an author list, a year and colon, a title and usually a DOI or
URL; runs restart at 1 in each chapter's References section.

> `1. IPCC, 2021: Climate Change 2021: The Physical Science Basis. Contribution of Working Group I to the Sixth Assessment Report…` — p243
> `5. NCEH, 2022: Climate Effects on Health. Centers for Disease Control and Prevention… https://www.cdc.gov/climateandhealth/effects/default.htm` — p243
> `341. Becker, W.S. and B. McKibben, 2021: The Creeks Will Rise: People Coexisting with Floods. Chicago Review Press, 368 pp.` — p1045

**Should it become a list?** In principle yes — a numbered reference list is an `<ol>`, and it
is the largest single class in the corpus. **But not yet.** Each entry wraps over several
source lines, and the wrapped lines do not stay with the entry: 304 of them became separate
`<pre>` blocks (class `entry-continuation`, below) and many more became paragraphs. The
measured consequence is that the 571 runs shatter into **2,446 contiguous pieces, 818 of them
a single entry**, and 369 pieces cross a page boundary. Wrapping that as it stands would
produce thousands of one-item `<ol>`s, each restarting or needing its own `start`, with the
rest of the entry outside the list.

**Risk: high, and the risk is in the prerequisite, not the markup.** Fix the wrapped-entry
join first; then this class is a clean `<ol start="N">` — or, better, a `<ul>` with
`list-style: none` keeping the printed number, since the numbers are cross-reference targets.

### 7. endnote-entry — 6,469 blocks, Warren pages ~845–905 (63 pages) → not yet

**Evidence.** `N.` followed by a hearing-volume or exhibit citation, in the report's
back-matter notes.

> `4. 3 H 142 (Brennan).`, `5. See id. at 142-143.`, `6. Id. at 143.`, `7. Ibid.` — p848
> `875. 15 H 75-76 (Kantor): CE 2301.` — p870
> `500. Ibid; CE 1974, pp. 24-25, 28, 37.` — p854

**Should it become a list?** These are notes, not a generic list. The library already has
`ReflowBlock.Content.footnote` and a `NoteKey`, and a back-matter endnote apparatus is what
that case is for. Treating them as a bare `<ol>` would lose the link to the reference.

**Risk: high, mostly from OCR.** Warren is a 1964 scan and the numbering is damaged:
page 848 opens `I. 3 H 142-143`, `a. 3 H 149`, `8. CE 479`, `4. …` where the source prints
1, 2, 3, 4, and then runs `9., 10., 12.` with 11 missing. 352 of 366 runs do not start at 1,
71 have a gap, and 1,151 of the 2,302 contiguous pieces hold one entry. Any renumbering would
print numbers the page does not have; any note linking would mislink. Warren is also outside
the gated lane (#5), so nothing here is protected by a passing check today.

**Recommendation.** Out of scope for #29. File separately as endnote-apparatus recognition.

### 8. questionnaire-item — 237 blocks, CIA Blue Book, 23 pages → **ambiguous**

**Evidence.** Numbered questions with lettered options, from the Air Force UFO sighting
questionnaire reproduced in the appendices.

> `21. How did the object disappear from View?` — p276
> `a. Certain` / `c. Not very sure` / `d. Just a guess` — pp272–275
> `a. Appear to stand still at any time? Yes No Don't Know` — p282
> `d. Southeast h. Northwest` — p273 (two options merged into one block)

**Should it become a list?** Genuinely unclear, and I am not guessing. The material *is* a
nested numbered/lettered list, but it is a scanned reproduction of a printed form whose
option columns the reflow already merges (`d. Southeast h. Northwest`), whose markers OCR
damages (`c. Wot very sure`), and whose page layout is the point. 30 of 116 runs do not start
at 1, 18 have gaps, 11 descend, and 106 of the 153 contiguous pieces hold one item. It sits
next to 341 blocks of OCR debris on the same pages.

**Recommendation.** Leave preformatted for now and revisit with a page-level review of the
CIA appendices. If it does move, `<ol>` with the printed marker retained.

### 9. display-math-row — 426 blocks, Wallace, 65 pages → **stays `<pre>`**

**Evidence.** A row of a worked derivation whose first glyph is a minus sign, which
`isList` reads as a bullet.

> `− 7ab− 2ab + 14b2` and `− 7 and− 2, split the middle term` — p222
> `− 2x− 3 Our Solution` — p193

Alignment is the meaning here: these are the continuation rows of a multi-line derivation.
Correctly preformatted today. The library already tracks `mathMinusRows` so that the list
rules pass over them (`LayoutReconstructor.swift:559`, `:2952`); this class confirms that is working.

### 10. coded-report — 4 blocks, FAA pages 316–319 → **stays `<pre>`**

> ```
> TAF
> KPIR 111130Z 1112/1212
> TEMPO 1112/1114 5SM BR
> FM1500 16015G25KT P6SM SCT040 BKN250
> …
> ```
> — FAA p319, one block, seven lines

The only genuinely preformatted text in the corpus where line structure carries meaning, and
the only thing `preformattedLines` pins. Must not move.

### 11. ocr-debris — 421 blocks, 5 books → **no**

Scanned data tables and handwriting that OCR turned into strings which happen to open with
something `isList` accepts.

> `I) () 0 0.0 0.0 0.0` — CIA p123
> `L) AA P.o n.P " 0 /) /),() /I.I) ,,,,` — CIA p238
> `z. .:z..` — CIA p134
> `2. " 2. JI,/ /JJ J/./` — CIA p124

Wrapping these in `<ol>` would announce "list, 341 items" to a screen reader over
untranscribable noise. They are already a defect; a list would make it a louder one.

### 12. entry-continuation — 393 blocks, NOAA + Warren → **a defect, not a class**

The wrapped second line of a reference or a note, emitted as its own block, often with a
false marker because an author initial reads as a lettered marker.

> `N. Viovy, A. Voulgarakis, T.S. Weber, M. van Weele, G.R. van der Werf, R.F. Weiss, D. Worthy, …` — NOAA p122
> `R. Mathur, and H. Winkler, 2014: A new scenario framework for climate change research: Scenario matrix` — NOAA p188
> `p. 5.` and `K. Carroll); 7 H 59-60 (Gerald Hill) ;` — Warren pp885, 857

These should be joined to the entry above them. They are the reason classes 6 and 7 cannot
become lists yet.

### 13. testimony-turn — 228 blocks, Warren, 37 pages → **no**

> `Q. Did you have a gun with you when you went to the Friday` — p839
> `A. I understand the gun was advertised for $12.78, I believe.` — p262

Speaker turns in deposition transcripts. `Q.`/`A.` are speaker labels, not list markers. If
anything they want a `<dl>` or paragraphs with a `<strong>` label; an `<ol>` would renumber
them 1, 2, 3.

### 14. elision — 69 blocks, Warren + SCOTUS → **no**

> `* * * he asked me what were the people gathering around on the corner for…` — Warren p211
> `* * *` — SCOTUS p43

The printer's mark for omitted text inside a quotation. `isList` reads the leading `*` as a
bullet. These are prose, not items.

### 15. note-asterisk — 14 blocks, 5 books → **no; wants `footnote`**

> `* The Reserve Banks transferred to the Treasury $19.3 billion from their capital surplus on December 28, 2015…` — Fed p13
> `* Leverage ratio is the ratio of tier 1 capital to total assets.` — Fed p55

Table and figure source notes. They belong in `ReflowBlock.Content.footnote`, not in a list.

### 16. contents-or-section-title — 18 blocks, 3 books → **no; a heading defect**

> `1. Introduction`, `2. Classical Picture`, `3. Quantum Description` — NBS Geltman pp1, 3, 6
> `2. TEST DESCRIPTION ................................................. 2` — NTRS GWL p1
> `5. AL QAEDA AIMS AT THE AMERICAN HOMELAND 145 5.1 Terrorist Entrepreneurs 145 …` — 9/11 p5

NBS's are the article's own section titles on the pages where those sections begin — they
should be headings. The GWL and 9/11 ones are contents entries with folios. Turning these
into `<ol>` items would entrench a heading/navigation defect as list semantics.

### 17. form-section-title — 7 blocks, uscourts pro-se complaint → **no**

> `A. The Plaintiff(s)`, `B. The Defendant(s)`, `V. Certification and Closing`

Section headings of a court form. `V.` is a roman numeral, not the letter V in a sequence.

### 18. singleton-marked-line — 82 blocks, 12 books → **ambiguous**

One marked line with no sibling anywhere near it. Some are genuine one-item lists
(`1) Get a Kit` — CDC p6), some are references (`D. L. Mills. Network time protocol (ntp). RFC
958…` — arXiv p10), some are names (`J. Cofer Black` — 9/11 p449, `T. Graham Giusti` — 9/11
p14), some are OCR noise. **I am not classifying these; they need page-level review.** A
one-item `<ol>` is almost never right, so the default should be to leave them preformatted.

---

## Blast radius

### If only the two safe classes move (`bulleted-list-item` + `numbered-list-item`)

1,703 blocks change markup, on 323 pages across 14 books (1,601 blocks on 304 pages if Warren,
which is outside the gated lane, is set aside).

| Book | blocks | pages |
|---|---:|---:|
| faa-phak-8083-25c | 1,029 | 160 |
| gpo-911-2004 | 196 | 55 |
| noaa-nca5-2023 | 169 | 32 |
| fed-explained-2021 | 102 | 27 |
| gpo-warren-1964 | 102 | 19 |
| dga-2025-2030 | 18 | 4 |
| census-rrs2002-01 | 16 | 1 |
| cia-blue-book-14-1955 | 16 | 13 |
| ntrs-20180003024-earthdata-slides-2018 | 14 | 3 |
| ntrs-20190030725-dasc-2019 | 13 | 3 |
| wallace-algebra-2010 | 11 | 3 |
| gpo-our-flag-2003 | 7 | 1 |
| ntrs-20200002975-gwl-2020 | 5 | 1 |
| scotus-loper-bright-2024 | 5 | 1 |

Those 1,703 items would form roughly 512 contiguous list elements (345 `<ul>` + 167 `<ol>`),
of which 145 hold a single item, 24 cross a source-page marker and 2 cross a spine file.

### If everything list-shaped moves

13,838 blocks on 1,040 pages in the gated cases, plus 6,599 in Warren — that is, most of NOAA
and most of Wallace. The recommendation above is explicitly against that.

### Checks that would need review

**Directly, because they read `<pre>` identity** (`tools/check_corpus_content.py:200` assigns
an item id on `<pre>` only; `li` is already in `BLOCKS` and `SEQUENCE_BLOCKS` but never gets
an id):

| Check | Count | Cases and pages |
|---|---:|---|
| `listItems` | 89 | faa 24 (pp27×3, 73, 191×4, 211, 251×2, 302×4, 316, 317, 318, 365×2, 372×3, 397); wallace 16 (pp2×8, 9, 40, 64×2, 101×3, 120); earthdata 16 (p7×5, p8×6, p9×5); fed 10 (p9×5, p22, p58×4); 911 7 (pp146, 147, 205, 365×2, 374×2); gwl 5 (p13×5); dga 4 (pp6×2, 7, 8); dasc 4 (p5×4); scotus 3 (p86, p87×2) |
| `continuedListItems` | 1 | fed p21 |
| `preformattedLines` | 1 | faa p319 (the TAF) — must keep passing unchanged; the block must stay one `<pre>` |

All 91 sit in `corpus/regressions.json`. Every one of the 89 `listItems` phrases whose class
is `bulleted-list-item` or `numbered-list-item` moves out of `<pre>`; the wallace 16 and the
faa TAF/METAR ones do not.

**Indirectly, because the phrase includes the printed marker** — these break only if the
marker text is removed from the item:

| Check type | Phrases opening with a marker | Where |
|---|---:|---|
| `orderedText` | 76 of 1,083 | wallace 31 (pp10, 40, 438, 471, 487), earthdata 16, dasc 14, 911 4, faa 3 (p317), census 3, dga 2, nbs 2, scotus 1 |
| `listItems` | 68 of 89 | as above |
| `paragraphs` | 24 of 395 | 911 23, faa 1 |
| `headings` | 16 of 256 | dasc 10, gwl 6 |
| `text` | 15 of 209 | wallace 6, scotus 5, 911 4 |
| `absentText` | 8 of 244 | wallace 5, scotus 2, fed 1 |
| `distinctParagraphs` | 6 of 162 | 911 6 |
| `scripts` | 4 of 112 | wallace 2, dasc 2 |
| `absentScripts` | 1 of 14 | wallace 1 |
| `continuedParagraphs` | 1 of 122 | 911 1 |

**Swift tests.** 23 test files construct or match `ReflowBlock.Content.preformatted` directly
and would stop compiling or stop matching if a `.listItem` case is added (131 mentions of
`preformatted`/`<pre>` in total across `Tests/` and `tools/`):

`AcademicFrontMatterTests`, `AcademicSectionTitleTests`, `BulletItemSizeAndSplitReferencesTests`,
`CitationContinuationTests`, `ContinuedNotePageTests`, `DocumentModelTests`,
`ExerciseNumberingTests`, `FAAHeadingLeftoversTests`, `InvisibleTextTests`,
`LineEndCompoundTests`, `ListBulletsAndCodedReportsTests`, `ListContinuationTests`,
`MarkerPieceTests`, `NoteLinkTests`, `NumberLedParagraphTests`, `NumberedNoteTests`,
`PreformattedStyleTests`, `RowPiecesAndSpacedParagraphTests`, `ShiftedScriptBaseTests`,
`TaggedMarkerPieceTests`, `TaggedSplitsAndTitlesTests`, `TallRowsAndMinusTests`,
`UnclaimedNotePageTests`.

Of these, `ListContinuationTests`, `ListBulletsAndCodedReportsTests`,
`BulletItemSizeAndSplitReferencesTests`, `MarkerPieceTests`, `TaggedMarkerPieceTests`,
`NumberLedParagraphTests` and `ExerciseNumberingTests` are about list handling itself and
need their expectations rewritten rather than mechanically retyped; `PreformattedStyleTests`,
`ListBulletsAndCodedReportsTests` (its TAF half) and `LineEndCompoundTests` protect the code
and coded-report side and must keep passing unchanged.

**Fast-lane fixture checks.** `Tests/PDFReflowLibTests/fixtures/lists-code.pdf` carries both a
numbered list and a Courier code block. `tools/check-epubs.py:26` pins the exact strings
`"1. Keep the first item."` and `"2. Keep the second item."`, and
`ConversionTests.sourceMarkupIsEscapedAndCodeBreaksRemain` asserts
`html.contains("<pre>if value &lt; 3:\n    print(value)\nreturn value</pre>")` alongside the
same two list strings. The code assertion must keep passing; the two list assertions change if
markers are stripped. `check_reproducibility.py --fixtures` converts this fixture twice in
every lane, and five corpus books have checksum-pinned repeat-run identity
(Fed Explained, Our Flag, the CDC comic, Replay Clocks, plus the six fixtures) — those compare
markup byte for byte, so any change to Fed Explained's 102 items shows up there too.

**Documentation counts.** `doc/regression-testing.md` has generated counts between
`<!-- counts:… -->` markers (89 list-item, 1 list-item-continuation, 1 preformatted-lines);
`tools/update_doc_counts.py` regenerates them, and `check-all.sh --fast` fails while stale.

---

## Implementation sketch

### Document model

`ReflowBlock.Content.preformatted` currently carries two unrelated things: monospaced code and
coded reports (joined into one multi-line block with explicit indentation,
`LayoutReconstructor.swift:3897–3908`) and list items (one block per item, continuations
joined in, `LayoutReconstructor.swift:3909–3918`). Those should separate:

```swift
case preformatted(InlineText)        // monospaced / coded report only
case listItem(ListItem)              // a single item
```

```swift
struct ListItem: Sendable, Equatable {
    var text: InlineText              // the item body, marker removed
    var marker: String?               // the printed marker, kept for provenance
    var ordinal: Int?                 // the printed number, when the marker is numeric
    var kind: Kind                    // .unordered, .ordered(style)
    var level: Int                    // 0-based nesting depth, from measured indent
    var opensList: Bool               // first item of its list (the writer needs no lookahead)
}
```

Keeping the item as a *flat* block with a `level`, rather than a tree, matters: the writer
already streams blocks one at a time into chapter files and splits the spine wherever it
likes. A tree would have to be re-split at every chapter boundary. A flat sequence with a
depth lets the writer open and close elements as the depth changes, and lets a list that
crosses a spine file close and reopen with `start`.

`ReflowBlock.text`, `sourcePages` and `hasReflowedText` each need the new case. So does
`NoteLinker.swift:43`, which today finds list items by testing
`LayoutReconstructor.isList(value.text)` on a `.preformatted` — it would match on the case
instead, which is both cheaper and more accurate (a code line that happens to open with `-`
stops being scanned for note markers).

### Where the decision is made

`LayoutReconstructor` already computes everything needed and throws it away:

- `listLine(line)` / `isTightMarker(line)` decide that a line opens an item
  (`LayoutReconstructor.swift:3909`).
- `ListMarker` parses kind, punctuation and value (`:4992`), and `isSibling` already encodes
  the "next or next-but-one" rule the answer keys need (`:5011`).
- `listMarkers(on:)` records a page's markers with their type size so the *neighbouring* pages
  can see a list continuing across the boundary (`:5019`) — exactly what an `<ol start>` needs.
- The per-page loop tracks `listItem = (marker:, last:, indent:, index:)`, so each item's
  left edge is known at the moment it is built; `indent` is what a `level` would be derived
  from, relative to the page's body left margin and the parent item's edge.

So the work is to carry these through rather than to compute them.

**Grouping rule.** Wrap only a *contiguous* run: items adjacent in the emitted block sequence,
same marker kind and punctuation, consistent indent, with no paragraph, heading, figure or
table between them. The measurement above gives the resulting element counts directly
(345 `<ul>` and 167 `<ol>` for the two safe classes). Do not bridge an intervening block: 9/11
pages 204–205 prove that two lists with a lead-in paragraph between them are one run under the
sibling rule alone.

**Tagged sources.** `StructureTreeReader` already parses `L`, `LI`, `Lbl` and `LBody` into its
standard role set (`StructureTreeReader.swift:72`) and then discards them — only `P` and
`H1`–`H6` create groups (`:120–126`), and everything else calls `reject`. `doc/architecture.md`
says so: "Supported roles are P and H1–H6". Consuming `L`/`LI`/`Lbl`/`LBody` would give
*validated* list structure, including nesting depth and the label/body split, for tagged
documents, instead of heuristics — and the label/body split solves the marker problem outright.
The FAA handbook already tags each bullet item as one `P` (#81), so its tags help less, but DGA
and the NASA papers are worth probing. This is the highest-value single change in the sketch.

### EPUB writer

`EPUBWriter.swift:168` emits one element per block. For a flat item sequence with depth:

- opening a list at depth *d*: emit `<ul>` or `<ol …>` for each level from the current depth
  up to *d*, each nested inside the currently open `<li>`;
- closing: emit `</li></ul>` / `</li></ol>` down to the new depth;
- at the end of a chapter file, close every open list; at the start of the next, reopen with
  `start` set to the next ordinal. 2 of the 512 safe-class pieces cross a spine file, so this
  path is exercised but rare.

`<ol>` and `<ul>` may contain only `<li>` (plus `<script>`/`<template>`). **The source-page
marker is a problem.** `EPUBTextEncoder.swift:21` emits
`<span epub:type="pagebreak" role="doc-pagebreak" id="page-N" aria-label="N"/>` as a sibling
before the first block of the page, and today it sits between two `<pre>` elements. Inside a
list it would be a direct child of `<ul>` — invalid, and EPUBCheck runs on every gated
conversion. 24 of the 512 safe-class pieces cross a page (20 bulleted, 4 numbered), so this is
not a corner case. Two options:

1. Move the marker inside the following `<li>`, as its first child. Page anchors stay complete
   and ordered (the contract requires that), and `read_pages` keeps working because it looks
   for the `epub:type`, not the position.
2. Close the list at the page boundary and reopen with `start`. Simpler markup, but it breaks
   `continuedListItems` semantics and makes a two-item list out of one.

Option 1 is the right one, and it is worth writing a negative control for: a page marker that
ends up *outside* any element, or duplicated, must fail.

CSS: `EPUBWriter.swift:223` currently styles only `pre { white-space: pre-wrap; overflow-wrap:
anywhere; }`. A list needs nothing, but a class that keeps its printed marker (the references,
if they move later) needs `list-style: none`.

### The marker text

An `<ol>` renders its own numbers. Keeping `1.` in the item body double-numbers it. Three
handlings, and the class decides which:

- **Strip** — for `bulleted-list-item` always (the glyph carries nothing), and for
  `numbered-list-item` only where the run's values are consecutive, ascending and the run's
  first value sets `start`. This is what breaks the 68 `listItems` and 76 `orderedText`
  contract phrases that open with a marker; each has to be re-reviewed against the source page
  and rewritten without its marker, or the check has to compare the rendered ordinal.
- **Keep, with `list-style: none`** — for anything whose printed number is a cross-reference
  target (NOAA's references, Warren's endnotes) or whose sequence is not trustworthy. The item
  is still semantically a list — a screen reader still announces "list, N items" — but the
  page's own number is what the reader sees. No contract phrase changes.
- **Leave preformatted** — Wallace's exercises and answer keys, until column order is fixed.

Recommendation: strip for `<ul>`, and for `<ol>` strip only behind a verified-sequence gate,
keeping the printed marker otherwise. That keeps the change reviewable page by page.

### Where numbering does not start at 1 or is not consecutive

Measured, so a `start` attribute and a fallback are both required:

| Class | runs | not starting at 1 | with a gap | descending |
|---|---:|---:|---:|---:|
| numbered-list-item | 81 | 11 | 13 | 6 |
| lettered-sub-item | 16 | 0 (letters) | 3 | 2 |
| exercise-item | 241 | 204 | 116 | 3 (101 step by 2) |
| answer-key-entry | 413 | 364 | 31 | 1 |
| bibliography-entry | 571 | 531 | 194 | 1 |
| endnote-entry | 366 | 352 | 71 | 1 |
| questionnaire-item | 116 | 30 | 18 | 11 |

Concrete cases: FAA page 319's TAF decoder runs 1–10 across a column cut; Fed page 38's `1.`–`4.`
open a run that starts mid-page; Wallace page 25 starts at 14 and page 62 at 19 because the
exercise set continues from the previous page; Wallace page 439 runs
`21, 29, 33, 52, 56, 57, 67, 81`; Warren page 848 runs `9, 10, 12` with 11 lost to OCR; NOAA
has 13 runs whose "first marker" is the value `2023` — a year at the start of a wrapped
reference line read as a marker.

The rule that falls out: emit `<ol start="N">` only when the run is strictly ascending by 1
from a value the page actually prints; otherwise keep the printed marker and do not let the
reading system number anything.

---

## Summary of recommendations

| Move now | Move after a prerequisite | Do not move |
|---|---|---|
| `bulleted-list-item` → `<ul>` (1,304) | `bibliography-entry` → `<ol>` after wrapped entries rejoin (9,251) | `exercise-item`, `answer-key-entry`, `display-math-row`, `coded-report`, `ocr-debris`, `elision`, `testimony-turn`, `note-asterisk`, `contents-or-section-title`, `form-section-title` |
| `numbered-list-item` → `<ol start>` behind a verified-sequence gate (399) | `lettered-sub-item` → nested, after indent reaches the model (39) | |
| | `endnote-entry` → `footnote`/note apparatus, separate issue (6,469) | |
| | `questionnaire-item` — ambiguous, needs a page review (237) | |

Staged this way, the first change touches 1,703 blocks on 323 pages and 91 contract checks,
with 145 one-item lists and 24 page-crossing lists as the cases to review by hand — rather
than 21,619 blocks and most of two books at once.
