# Chapter-scoped note links and return navigation (#11)

Tier: deterministic Apple PDF stack, library defaults, macOS 27.0 arm64 release CLI.
Baseline: branch tip `162cf60` (release binary SHA-256 `027ac000…`); candidate: this working
tree on `162cf60` (release binary SHA-256 `4b2d63fe…`). The same figures were measured on
the earlier tips `417edc7` and `dd4c326` (1,444 of 1,549 markers before #54's reflowed sidebar
boxes added 15 markers). Sources: the 9/11 report `corpus/cache/GPO-911REPORT.pdf`, SHA-256
`657d41475eb3a9a5e3e87a6c7c51ac1dfbe1af7566d1abff7bf7286e7e1c0e1b`, 585 pages, and *Loper
Bright* `corpus/cache/22-451_7m58.pdf`, SHA-256
`12f5ea075004886774c25e7831ea1608fd0f831f0113e83bb0e85811c0a4bb6e`, 114 pages. Pages 20, 469
and 484 of the 9/11 report were rendered with Poppler and read; the Loper pages were reviewed
under #40.

## What was wrong

Raised reference markers survived as `<sup>4</sup>` and the 9/11 endnotes as numbered
paragraphs on 48 accepted pages, but nothing connected them: no marker linked to its note, no
note returned to its reference, and the note paragraphs carried no identity beyond their text.
Chapter 1's notes 1–9 (page 469) were refused because note 1 has a second indented paragraph;
pages ending one chapter's notes and opening the next (484, 489, 497, 506, 531, 543, 551, 559,
580, 583) were refused at the sequence break; wrapped citation lines opening with `p. 11` or an
initial (`E. Booker`) refused ten more pages; notes such as `40. Ibid.` (under ten letters)
refused theirs; a dedented year or `5.This` ahead of the run set the wrong indent (508, 546);
and the outline's `1 “WE HAVE SOME PLANES”` entries named no chapter to the reader, so no body
page had a chapter.

## What changed

- **Note model.** `NoteKey` (number + `.chapter(n)` or `.page(n)` scope, identifier `c1-4` /
  `p60-2`) on `ReflowBlock.note`: `NumberedNoteDetector.layout` returns each paragraph's start
  and, for a note's first paragraph, its number and chapter; `FootnoteDetector` notes get page
  scope. `InlineText.Element.noteReference(digits, styles, key)` represents a linked marker.
- **Detector.** The running head's chapter (`chapter(on:)`), an unnumbered line at the indent
  as a further paragraph of the current note, a larger `N+1 Title` line followed by note 1 as a
  mid-page chapter switch, `p. 11`/initial continuations, four-letter note starts, numbers of
  at most three digits, and the first start on the edge most numbered lines share.
- **Chapter evidence.** `ChapterBoundaryReader.read(_:scheme: .numbered)` reads `N Title`
  outline entries, matched on the page by a bare numeral line plus the title without spaces
  (`AIMS ATTHE` in the outline versus `AIMS AT THE` on page 163). It never adds a spine
  boundary; the labelled scheme is untouched.
- **Linker.** `NoteLinker.link` runs after every join: a body paragraph's superscript run of one
  to three digits links to the page footnote of that number on its page (the block's page
  advanced by inline boundaries), else to the chapter endnote of that number in the page's
  chapter (last matched opening at or before the page; `NOTES TO CHAPTER N` pages are not
  body). Unknown chapter, no note in scope, or a number two notes claim in one scope leaves
  the marker plain. Markers inside notes are never linked. The pipeline result carries a
  `NoteLinker.Summary` (markers, linked, unscoped, missing, ambiguous).
- **Writer.** `<sup><a epub:type="noteref" role="doc-noteref" href="chapter-24.xhtml#note-c1-4">4</a></sup>`
  (first reference `id="noteref-c1-4"`); referenced notes get `<p id="note-c1-4"
  epub:type="endnote">` or `id` on `div.footnote`, the printed number wrapped in `<a href="…#noteref-c1-4"
  role="doc-backlink" epub:type="backlink">`. Links are written as fragments, packing reserves
  the longest file name per link, and cross-file hrefs are qualified once every spine document
  is packed. Unreferenced notes and unlinked markers are unchanged.
- **Tools.** `check-epubs.py` pairs every noteref with a note holding one backlink that
  resolves to a reference to that note; `check_corpus_content.py` supports `noteLinks`.

## Results: 9/11 report

Per-chapter body markers (superscript digit runs on pages 19–468, chapter from the matched
outline openings 19, 65, 89, 126, 163, 192, 233, 272, 296, 343, 357, 379, 417):

| Chapter | Markers | Linked | Unlinked (no note in scope) | Linked note ids |
| --- | --- | --- | --- | --- |
| 1 | 241 | 241 | 0 | 1–241 |
| 2 | 93 | 93 | 0 | 1–93 |
| 3 | 111 | 94 | 17 | 94 of 114 |
| 4 | 189 | 174 | 15 | 174 of 194 |
| 5 | 109 | 109 | 0 | 109 of 131 |
| 6 | 210 | 209 | 1 | 209 of 261 |
| 7 | 165 | 156 | 9 | 156 of 192 |
| 8 | 98 | 98 | 0 | 98 of 113 |
| 9 | 173 | 159 | 14 | 159 of 193 |
| 10 | 78 | 67 | 11 | 67 of 75 |
| 11 | 34 | 28 | 6 | 28 of 42 |
| 12 | 42 | 13 | 29 | 13 of 42 |
| 13 | 21 | 18 | 3 | 18 of 22 |
| **Total** | **1,564** | **1,459 (93%)** | **105** | **1,459** |

Zero markers link outside their chapter (every href's `c<n>` equals the marker page's
chapter); zero are unscoped (every body page has a matched chapter); zero are ambiguous. The
105 unlinked markers cite notes on the nine notes pages the pipeline still refuses: 496, 543,
571, 575, 581, 582, 583 hold preserved image regions (the detector's image barrier), 572 and
578 carry `NOTES TO CHAPTERS 9-10` / `10-11` heads, and 543/583 also hold nested numbered or
bulleted lists inside notes. Of 118 notes pages (468–585), 113 pass the detector (48 before).
Notes without any surviving body marker (chapter 5 has 131 notes but 109 superscript runs
survive extraction) remain plain paragraphs without ids.

Hand-reviewed samples: page 20 `7:45.<sup><a … id="noteref-c1-4" href="chapter-24.xhtml#note-c1-4">4</a></sup>`
→ `<p id="note-c1-4" epub:type="endnote"><a href="chapter-1.xhtml#noteref-c1-4" …>4.</a> Flight 11
pushed back from Gate 32 in Terminal B at 7:40 …` (page 469, read on the render); page 19's 1 →
`1.</a> No physical, documentary, or analytical evidence …` with `Like the other two airports …`
kept as its own paragraph; page 64's 241 → `241.</a> NEADS audio file …` and page 65's 1 →
`1.</a>“Text of World Islamic Front’s Statement …`, both on page 484, on either side of the
`2 The Foundation of the New Terrorism` heading read on the render; page 66's 4 →
`4.</a>“Hunting Bin Ladin,” PBS Frontline broadcast, May 1998.` (chapter 2), not chapter 1's note 4.

Against the `162cf60` baseline: every body page's text is identical; 55 notes pages change,
all by note lines joining into paragraphs (identical once whitespace and hyphens are ignored)
except that on 484, 490, 495 and 573 the page's `Original page N` reference figure now precedes
the last note, which continues onto the next page, as #45 places images ahead of a joined
paragraph. 520 of 520 images byte-identical; page, reflowed, recognized and image counts
unchanged; three `uncertainHyphen` warnings added (484, 526, 574) by the newly joined notes.

## Results: Loper Bright and controls

Loper Bright: 22 footnote markers, 22 linked, 22 backlinks; page text identical on all 114
pages; markup changes on 30 pages (the links); no images; warnings identical. Page 13's
`Persistence.<sup>…1…</sup>` reaches `note-p13-1` after the joined paragraph under the page-14
anchor; page 60's `Ibid.2`, 97's `respect it”).2` and 98's `Vermeule 207.3` reach their page
notes. Two markers extracted as `4 ` now write their trailing space as plain text rather than
an empty raised run.

FAA, Wallace algebra (1,132 math superscripts untouched) and The Fed Explained are byte-identical
to their baselines in every page's markup, text and image (599, 2,047 and 262 images).

## Validation

- `swift test`: 299 tests pass (`NoteLinkTests` adds 11); one full run on the `417edc7` merge
  aborted with signal 6 during a parallel run and did not recur in any later full run.
- `python3 -m unittest discover -s tools -p 'test_*.py'`: 165 tests pass.
- `scripts/check-all.sh --fast`: passes (6 fixture and 13 policy conversions with EPUBCheck).
- Corpus lane, candidate binary: `gpo-911-2004` 90 checks, `scotus-loper-bright-2024` 69,
  `faa-phak-8083-25c` 61, `wallace-algebra-2010` 63, `fed-explained-2021` 92, all passing;
  EPUBCheck `0 fatals / 0 errors / 0 warnings` on all five; memory gates pass. The baseline
  binary fails the eight new `noteLinks` checks and the page 469/484 paragraph checks.
- `git diff --check` clean.

## Remaining gaps

- Notes pages with preserved image regions, nested lists, or heads naming two chapters stay
  refused (nine 9/11 pages, 105 markers).
- Cross-page numbered notes rely on the existing lowercase continuation join; a note whose
  next-page continuation opens with a capital or a number stays split (text preserved).
- Notes without a surviving body marker get no id; markers lost at extraction (in images,
  tables or non-raised runs) are not recovered.
- The summary counts are internal (`PDFReflowLibPipeline.Result.noteLinks`); no report field or
  warning was added.

## Reproduction

```sh
swift build -c release
.build/out/Products/Release/pdf-reflow corpus/cache/GPO-911REPORT.pdf 911.epub
python3 tools/run_corpus_regressions.py --converter .build/out/Products/Release/pdf-reflow \
  --epubcheck /opt/homebrew/bin/epubcheck --output <new-dir> --case gpo-911-2004 --case scotus-loper-bright-2024
```
Count links per chapter by scanning the unzipped spine for `role="doc-noteref"` hrefs and
`id="note-…"` anchors against the page markers.
