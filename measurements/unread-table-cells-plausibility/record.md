# What lets a page of unread handwriting pass for a transcription

Measured under [#275](https://github.com/vocaro/PDFReflowLib/issues/275), baseline `ecee3eb` (the
`main` this branch is merged onto), 2026-09-22, macOS 27 / Xcode 27, arm64, release CLI and probes
at library defaults. Source: `cia-blue-book-14-1955`, SHA-256 `90e05e77…52ee3`, 312 pages, plus
the nineteen other cached corpus sources as controls.

[#31](https://github.com/vocaro/PDFReflowLib/issues/31)'s record
([scanned-table-cells](../scanned-table-cells/record.md) §5) ended on a wall: the Blue Book
recognizes almost no page under the default policy, so the warned per-table image fallback #31
added never reaches the very pages it was built for. #275 is that wall. This is what was holding
it up, what was changed, and what moved.

## 1. The page, and the three ways it escapes

Physical page 150 (printed 141) is `TABLE A63 EVALUATION OF ALL SIGHTINGS FOR ALL YEARS BY COLORS
REPORTED`: four ruled grids 25 columns wide whose every value is written in ink. Its layer
transcribes the printed labels (`Evaluation`, `Balloon`, `Astronomical`, `Certain Doubtful Total`,
`Total`) and returns the hand-written body as `II 'i "J.7 "·' r,_3 ,_q 5 I I, ~..l Al 1·3 s 7`.

`EnglishText.wordCounts` over the extracted layer of the two pages #31 names, at `ecee3eb`:

| Page | Tokens | Holding a digit | **Are numbers** | Judged | English | **Bare `a`/`I`** | **… alone on their line** | Misread | Words |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 74 | 89 | 42 (47%) | 40 (45%) | 43 | 39 | 0 | 0 | 1 | 50 |
| 150 | 591 | 150 (25%) | **99 (17%)** | 232 | 146 | 79 | **75** | 23 | 424 |

The issue's own table reads 613 tokens and 168 English for page 150, at `9dfbd4b`. The difference
is [#274](https://github.com/vocaro/PDFReflowLib/issues/274), which landed on `main` in the
meantime and keeps the punched margin's rule out of the line beside it: twenty-two of the page's
bare `I`s were that margin. What is left is what a margin rule cannot reach — the ruled columns
inside the grids themselves — and it is still most of the page's English.

Three separate safe harbors, not one, carry page 150 past the word tests, and each of them is fed
by the noise itself:

1. **The digit exemption is bought with the noise.** `wordFinding` exempted a layer in which a
   fifth or more of the tokens *hold a digit*. Page 150's hand-written cells come back as `l6`,
   `0,3`, `A.Di`, `t).J` — misreadings that hold digits without being numbers. They push the share
   to 25% and the page is never judged. Counting only tokens that **are** numbers puts it at 17%.
2. **The ruled columns are counted as English words.** Of the 146 English words the layer is
   credited with, **79 are a bare letter** — one per ruled column of the grid — and 75 of those
   stand on a line that holds no other English word at all. `EnglishText.readsAsWords` already
   refuses a lone `a`/`I` as evidence on a line ("A lone `a` or `I` is no evidence: `a0 0.0` and
   `24:5i2` are digits misread"); `wordFinding` did not.
3. **What is left counts against nothing.** The rest of the cell noise is symbols and one- and
   two-character tokens, which are damaged fragments rather than misread *words*, so the misread
   test sees 23 of 424 (5%) against a floor of 10%. The ink test never runs either: it is gated at
   32 English words and this layer is credited with 146.

Remove the first two and the page reads **71 of 157** judged words English — 45%, below the 50%
floor — and fails.

Page 74, the typewritten table on the same scan, is the control that shows what the exemption is
actually for: **40 of its 89 tokens are numbers**, because the figures it states really are
figures. It is exempt on both sides of this change and keeps its text either way.

`measurements/scanned-table-cells/record.md` §5 already ruled out the obvious guess, and this
confirms it from the other side: the digit exemption is **not** what saves page 150 on its own.
With only the exemption narrowed the layer is judged and still passes at 146/232 (63%). With only
the lonely letters discounted it stays exempt at 25%. Both are needed, and neither alone moves any
other page of the corpus into failure.

## 2. Why "lonely", and not "bare"

The first rule tried discounted **every** bare `a`/`I`. It works on page 150 and it costs a page
the library deliberately protects.

Warren report page 636 — the carbon typescript `tcld t» ftboot` for "told me about" that
[#7](https://github.com/vocaro/PDFReflowLib/issues/7) is built on, and the fourth page of the
pinned `gpo-warren-1964-suspect-text-excerpt` — reads 96 of 191 judged words English, 50.26%, a
quarter of a point above the floor. It fails on the *misread* test instead, and a `.misreadWords`
finding puts the page in `RecognitionPlan.Mode.compare`, where the damaged layer is kept unless a
fresh reading beats it. Discount its fifteen bare letters and it reads 81 of 176 (46.0%), fails
the English test first, and is planned `.replace` — the layer discarded outright. That is the
failure mode #275 warns about: a rule that fires too readily.

Asking the letter what company it keeps separates the two exactly. Page 636's `I`s stand in
sentences, so none of them is lonely and the page's finding does not move. Page 150's stand on
lines that hold no other English word — 75 of its 79 — because a row of ruled cells has no words
on it to keep them company.

Reordering the two tests instead, so that a misreading is always reported before a shortage of
English, was measured and rejected: it moves nine CDC comic pages from `.replace` to `.compare`,
which would keep `sreANee v/eus` in place of a good reading on the pages
[#93](https://github.com/vocaro/PDFReflowLib/issues/93) was filed for.

## 3. The cross-corpus survey

Every page of all twenty cached sources, read with the library's own extraction and gated as
`PageDiagnosis.assess` gates plausibility (a non-empty layer over a page-sized graphic). 1,335 of
the corpus's 5,262 pages qualify. Verdicts, present rule against the rule this change makes:

| Case | Image-backed with text | Fails now | Fails after | Pages whose plausibility moves |
| --- | ---: | ---: | ---: | ---: |
| `cia-blue-book-14-1955` | 312 | 0 | **56** | **56** |
| `gpo-warren-1964` | 910 | 29 | 29 | 0 |
| `cdc-zombie-pandemic-2011` | 33 | 26 | 26 | 0 |
| `faa-phak-8083-25c` | 18 | 0 | 0 | 0 |
| `ntrs-…-earthdata-slides-2018` | 21 | 0 | 0 | 0 |
| `noaa-nca5-2023` | 14 | 0 | 0 | 0 |
| `fed-explained-2021` | 8 | 0 | 0 | 0 |
| `nbs-jres-geltman-1977` | 7 | 0 | 0 | 0 |
| `gpo-warren-1964-suspect-text-excerpt` | 5 | 5 | 5 | 0 |
| `dga-2025-2030` | 4 | 0 | 0 | 0 |
| `gpo-our-flag-2003` | 2 | 0 | 0 | 0 |
| `usda-ars-agresearch-2012-11` | 1 | 0 | 0 | 0 |
| the other eight cases | 0 | — | — | 0 |

Three Warren pages change *verdict* without changing plausibility: page 551 stops being exempt and
passes on its merits, and pages 62 and 339 keep too few judged words to be judged at all once
their lonely letters are set aside. A layer that is not judged is plausible, exactly as a layer
that passes is, so nothing about those pages moves.

The survey judges each layer in isolation and does not reproduce every exclusion `assess` applies
(a damaged encoding, a page that already requires its image), so its Blue Book count of 56 differs
slightly from the 57 findings the conversion itself reports. The lane below is authoritative.

## 4. What the corpus lane says

The lane was run on this tree at four jobs, against release binaries built from it and from
`ecee3eb`, `epubcheck` 5.x — ten whole-lane runs in all, three of the baseline and seven of this
branch. Every case's `runPassed` was read from its own `result.json` and is true on both sides;
every `content-assessment.json` holds zero errors and `passed` true, in nine of the ten runs (the
tenth is below). Warren and NOAA remain the two documented exclusions.

**Seventeen of the eighteen covered books do not move.** Converted text characters, image counts,
recognized-page counts, reflowed-page counts and every warning code's count are identical between
the two binaries, and reading both runs' EPUBs back page by page across the spine, every one of
their 2,195 source pages holds a text of exactly the same length.

The eighteenth is the book the issue is about:

| `cia-blue-book-14-1955` | `ecee3eb` | this tree |
| --- | ---: | ---: |
| Recognized pages | 3 | **56** |
| Reflowed pages | 312 | 308 |
| Pages preserved as an image | 0 | 0 |
| Converted text characters | 786,704 | 704,463 |
| Images | 423 | 448 |
| `unverifiedTextLayer` | 309 | 256 |
| `implausibleTextLayer` | 3 | 57 |
| `ocrUsed` | 3 | 56 |
| **`unreadTableCells`** | **2** | **65** |
| `incompleteRecognition` | 0 | 1 |
| `imageRegion` | 396 | 412 |
| `furnitureRemoved` | 219 | 210 |
| Peak RSS | 368 MiB | 499 MiB |

Fifty-seven layers fail; fifty-six of those pages are recognized and replaced. The one that is not
fails on the misread test, is compared with a fresh reading, and **keeps its own text**, which is
what `.compare` is for. No page is preserved as an image: no page raises `ocrFailed`,
`pageImageFallback` or `implausibleRecognition` on either side, and every one of the book's 312
source pages still holds text. The reflowed count falls by four because four pages — 148, 175, 188
and 192 — come back as their table pictures and captions with no prose block left, one of which
(148) already did at `ecee3eb`; page 148's whole reflowed text was
`4•Bmls IS-Clouds. Oust, etc. j6-lnsuff1c.klfo. 7-Psyctmloaic:al 11-Unkno• ~Other`.
No page of any other book loses a character.

Two lane runs did fail, and not on this book: `gpo-warren-1964-suspect-text-excerpt` page 4 is
Warren 636, the `.compare` page of §2, and its contract pins the fresh reading winning that
comparison. Alternating the two binaries showed what actually decides it, which is how busy the
Mac is:

| Host load average | Binary | Lane runs | Excerpt failures |
| ---: | --- | ---: | ---: |
| ~2 | `ecee3eb` | 3 | 0 |
| ~2 | this branch | 7 | 1 |
| ~16–19 | `18c8cc3` (`main` itself) | 3 | **3** |
| ~16–19 | this branch on `18c8cc3` | 1 | 1 |

`main` reproduces it on its own once other work is running on the host, three times out of three,
with the same four errors. In a loaded run `census-rrs2002-01` converts in 298 seconds instead of
4, raises `incompleteRecognition` on seven pages and comes back 11,000 characters shorter, its
recognition having read less of each page; the excerpt takes 294 seconds instead of 6, and page
4's comparison — a five-point margin between the reading's misread share, 42 of 224, and the
layer's 58 of 244 — goes the other way. It cannot be this change in any case: page 4's own counts
are identical under both binaries (§2), and the recognition it is compared against reads 76%
English with **zero** lonely letters, so neither narrowing can reach it. Filed as
[#281](https://github.com/vocaro/PDFReflowLib/issues/281). The figures below are from runs taken
while the host was quiet — though this book's own are the same either way: its recognized-page
count, and every one of its warning-code counts in the table below, reproduce exactly in the
loaded runs as well, because a layer's word counts are read from the page's own text and only the
books whose output depends on how well Vision read wobble.

Seventy-five of the book's 312 pages hold a different length of text; 19 are longer and 56 are
shorter, for a net 82,240 characters. What the shorter pages gave up is the ink the layer could
not read. Page 168, which falls from 6,277 characters to 650, is the change in one page:

> **`ecee3eb`:** `,--$,£CP,..-P.) ANP LJ;SS £-/t!J S£CIJNPS Preserved region from page 168 lllmber
> PerC01I … 0-Balloon Ill ., ;., ftJ.~ ,, .,,, 17,,,,P I ,, .3 //,J '!1,, ~tJ.J I 0 J s:o /1,t, S,I)`
>
> **this tree:** `Table from page 168, preserved as an image. Its cells are not transcribed; read
> them in this picture. 6/ SECONDS - 5 MINUTES 6-30 MINUTES OVER 30 MINUTES NOT STATED Number Per
> Cent … Evaluation Certaia Doubtfol Total Certain Doobtful Total`

Page 150 itself now reports `implausibleTextLayer` ("only 71 of 157 words are English words … the
existing text was discarded and replaced by OCR of the page image") and, beside each of the two
grids Vision locates, `unreadTableCells` ("OCR found the table but transcribed only 45% of the 390
cells in the grid it returned"). Page 74 is untouched: its layer stands, with the same
`unverifiedTextLayer` notice it has always carried. #31's fallback has reached the book.

Page 33's chart is the other shape the rule catches, and is worth stating because it is not a
table. `FIGURE 7`'s layer is the month initials of six year-long axes and the ticks between them:

> **`ecee3eb`:** `5001 400 ., sot 1so ~ o ~ … I J F M A M J J A s O N 01 J F M A M J J A s O N O
> IJ F M A M J J A s O N O … FIGURE 7 FREQUENCY OF OBJECT SIGHTINGS AND UNKNOWN OBJECT EVALUATIONS
> BY MONTHS, 1947-1952 C-7485`
>
> **this tree:** `£Z 60 Number of Object Sightings 40 30 40 30 20 20 10 object sightings 10
> Unknown object sightings 1950 195| FIGURE 7 FREQUENCY OF OBJECT SIGHTINGS AND UNKNOWN OBJECT
> EVALUATIONS BY MONTHS, 1947-1952 C-7485`

The caption survives on both sides; the axis titles are recovered and the tick soup is gone.

## 5. The contracts that had to move

Recognizing 56 pages of a 312-page scan costs memory the book did not spend before, and the old
ceiling could not hold it. Peak RSS over five measured conversions of this branch — four before
the `ecee3eb` merge and one after — reads **538, 531** (`--jobs 1`, three memory attempts)**, 455,
512 and 499 MiB**, against 276 MiB at `a1bbea8`, 368 MiB at `ecee3eb`, and a manifest ceiling of
**512 MiB**. Two of the five are over it and a third sits exactly on it, so the number is raised
to **768 MiB** — in line with `fed-explained-2021` (768), below the Warren excerpt's 1,024 — and
`doc/corpus.md`'s table and this book's `reviewStatus` say so. No other case's peak moved: the
largest differences anywhere else in the lane are the FAA handbook's 857 to 854 MiB and Our Flag's
103 to 96, run-to-run noise on books whose output is identical page for page.

Two contracts also had to be told what page 150 now says. Its accepted warning codes, in the
manifest's `qualityExpectation` (read by `tools/check_corpus_quality.py`, which is run by hand)
and in `corpus/regressions.json` (read by the lane's content check), were `unverifiedTextLayer`,
`complexLayout` and `pageImageFallback`, and page 150 raises none of them any more — the lane
reported `Page 150: missing quality warning` until both lists gained `implausibleTextLayer` and
`unreadTableCells`. Page 74's list is untouched, which is now what tells the two pages apart. Both
new codes are stronger signals than the one they replace, and they are what the book's own review
contract asks for on that page: *"Do not present damaged handwriting and numeric OCR as reliable
prose. Preserve readable original appearance and issue an actionable quality warning."*

## 6. What this does not do

The recognition of page 150's cells is still not published, and this change does not make it
publishable: §2 of the #31 record is why. The reader is given the grids as pictures and a warning
that says so. Nor does the rule reach a born-digital statistical table: plausibility is judged only
on a page whose text stands over a page-sized image, so the census report, the USGS copper tables
and Our Flag's flag-size tables are never asked.

## Reproducing

```sh
ln -s "$PWD/../corpus/cache" corpus/cache   # from a fresh worktree
swiftc $(python3 tools/pdfreflow_tools/swift_sources.py capture-layout-fixture.swift) \
  -o /tmp/capture-layout-fixture
/tmp/capture-layout-fixture cia-blue-book-14-1955 150 \
  Tests/PDFReflowLibTests/fixtures/blue-150-layout.json
/tmp/capture-layout-fixture cia-blue-book-14-1955 74 \
  Tests/PDFReflowLibTests/fixtures/blue-74-layout.json
/tmp/capture-layout-fixture cia-blue-book-14-1955 33 \
  Tests/PDFReflowLibTests/fixtures/blue-33-layout.json
swift build -c release
python3 tools/run_corpus_regressions.py \
  --converter "$(swift build -c release --show-bin-path)/pdf-reflow" \
  --epubcheck "$(command -v epubcheck)" --output /tmp/corpus-275 --jobs 4
```

The three captures are committed as fixtures and replayed by
`Tests/PDFReflowLibTests/TextLayerPlausibilityTests.swift`, with the census report, Our Flag, the
Warren report's prose and index, and Warren page 636 as controls.
