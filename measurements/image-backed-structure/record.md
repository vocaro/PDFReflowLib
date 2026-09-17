# Structure tags on pages with a page-sized background (#72)

Tier: deterministic Apple PDF stack, library defaults, macOS 27 arm64 release CLI. Baseline:
`6a5d67f` (#67), built in this worktree before any change (`identity.txt` records both CLI
hashes). Every conversion pins `--package-identifier urn:uuid:00000000-0000-4000-8000-000000000001`
and `--modification-date 2026-01-01T00:00:00Z`, so EPUB bytes compare directly. The baseline Fed
EPUB (`8244e44a…`) equals the #67 record's candidate.

## Diagnosis

`extractPage` treats a page whose painted regions include one covering more than 75% of the page
as image-backed text: it keeps a source-page reference, clears `graphics`/`tints`/`separators`,
reports `unverifiedTextLayer`, and set `structure = nil` on every line. The Fed pages that take
this path (`survey/the-fed-explained.tsv`, `mutool show -b … pages/N/Contents`):

| Page | Page-sized graphic | Text render mode | Tags (applied by `MarkedTextReader`) |
| ---: | --- | --- | --- |
| 3 (cover) | image XObjects, `Im0` 614×612 pt | visible only (no `Tr`) | none |
| 4 (colophon) | `0 0 612 792 re` tint fill | visible only | 13 `P`, all apply |
| 8, 14, 24, 50, 66, 88, 116 (chapter openers) | one image XObject `Im0` ≈612×792 pt inside `/Artifact <</O /Layout>>` | visible only | `H2` title, `P` pull quote (TOC/TOCI/Link unsupported), all apply |

On all nine the unverifiedTextLayer warning and the source reference are emitted (9 warnings);
pages 4 and 8–116 also report `annotationsNotConverted` (their links).

A second step dropped the quote once its tag survived. #67's paragraph-type rule keeps the spatial
reading of a `P` group set entirely in heading type when the next text in its column is ordinary
text starting no further left: a section title tagged as a paragraph. The 14-point quote sits
directly above the chapter's 10-point contents entries at the same left edge, so its tag was
dropped and #55's spatial pull-quote rule rebuilt the same paragraph without provenance.

## Survey: every English page on the image-backed path

`survey-image-backed.swift` (compiled with the library sources except `EPUBWriter` and
`PDFConverter`) mirrors `extractPage`'s signal: a painted region over 75% of the crop box and
non-empty native lines. For each such page it records `GraphicsReader`'s invisible-text flags,
unsupported/rotation (required page image), the structure-tree groups on the page and whether
`validates` + `MarkedTextReader.apply` succeed. Output per book in `survey/`.

| Book | Pages | Image-backed | Text mode on those pages | Pages with tags there | Tags apply |
| --- | ---: | ---: | --- | ---: | --- |
| Fed Explained | 135 | 9 | visible only | 8 | all 8 |
| Blue Book | 312 | 312 | invisible only | 0 | — |
| Warren | 920 | 910 | invisible only | 0 | — |
| NBS | 7 | 7 | 1–6 mixed + unsupported graphics (page image), 7 invisible only | 0 | — |
| CDC comic | 42 | 33 | visible only | 0 | — |
| DGA | 10 | 4 | visible only | 3 (pages 3–5) | none (reader rejects; 0 lines tagged) |
| FAA handbook | 522 | 24 | visible only | 23 | none (0 lines tagged on every page) |
| NOAA NCA5 | 1,834 | 63 | visible only (page 1834 unsupported) | 0 | — |
| Our Flag | 56 | 2 | visible only | 0 | — |
| 9/11, algebra, Loper Bright, Replay Clocks, USGS, Census | 1,352 | 0 | — | — | — |

Two findings settle the rule:

- Every scan case (Blue Book, Warren, NBS page 7) is exclusively invisible mode 3 and untagged. A
  tagged invisible layer could not associate anyway: `MarkedTextReader` rejects any `Tr` outside
  0…2 for the whole page, and a Form XObject (where a nested mode 3 would hide) invalidates it too.
- The only pages where clearing structure discarded applied tags are the Fed's eight. Every other
  visible-text image-backed page is untagged or already rejected by the reader.

## Change

- `GraphicsReader.Result.hasInvisibleText` (internal): some text-showing operator ran in mode 3,
  across saved state and nested forms (the existing tracking; `hasOnlyInvisibleText` unchanged).
- `PDFReflowLibPipeline.extractPage`: on the image-backed path, line structure is cleared only when
  the page has any invisible text. Visible native text over a page-sized image or tint keeps the
  roles `MarkedTextReader` validated. The warning, reference image and graphics clearing are
  unchanged, and OCR policy selection is untouched (`imageBackedText` is computed as before).
- `LayoutReconstructor.blocks`, #67's paragraph-type rule: a `P` group whose lines read as a pull
  quote by #55's own test (`pullQuoteLines`: two or more stacked lines, at least eight words,
  ending in terminal punctuation) keeps its tag even above the text it introduces. A title never
  ends a multi-line sentence.
- Docs: `doc/architecture.md` (tags vs image-backed text) and the README's image-backed paragraph.

No public API or default changed.

### Why the warning stays (out of scope, measured)

A born-digital photo page arguably should not be called an unverified text layer. Dropping the
warning for visible text was measured and rejected here: the survey puts 135 English pages in that
class (CDC 33, DGA 4, FAA 24, NOAA 63, Our Flag 2, Fed 9), and two reviewed contracts
assert the warning on exactly such pages: DGA page 1 ("retain the source image and review
warning") and CDC page 5. Visible mode also does not prove the text is what is painted: Fed page 8
draws its running head *before* the opaque photo (see defects), so visible text can be occluded.
That is a policy change of its own for the coordinator; this change leaves warning counts
identical everywhere.

## Before/after

### The Fed Explained

`fed-page-diff.txt` (all spine files concatenated, page by page) and `fed-tags-*.tsv`
(`probe-tags.swift`: every block on pages 3, 4, 8, 14, 24, 50, 66, 88, 116 with `taggedLevel` and
`structureGroup`):

| | `6a5d67f` | this tree |
| --- | --- | --- |
| Navigation entries | 164 (h1 1, h2 1, h3 9, h4 28, h5 63, h6 62) | 164, identical |
| Chapter titles (7) | h3, spatial (no tag) | h3, `taggedLevel` 2 from `H2` |
| Contents-page sections (28) | h4 | h4, identical |
| Pull quotes (7) | paragraph, spatial | paragraph, `taggedLevel` 0 from `P` |
| Page 4 colophon | 2 paragraphs (11 edition lines fused; ISSN + DOI fused) | 13 paragraphs, one per tagged line |
| Blocks / images / words | 1633 / 262 / 41,650 | 1644 / 262 / 41,650; word multiset identical |
| Warnings | 528 (unverifiedTextLayer 9, structureFallback 60, …) | identical list |

The seven chapter titles keep h3: their `H2` reaches `rankHeadingLevels`, which yields it to the
cover's larger untagged title as #67 designed, so the contents-page nesting is unchanged.
Chapter-opener XHTML is byte-identical; only provenance changes there. Spine files 1–4 differ
because page 4's extra paragraphs move the packing boundary; `compare-pages.py` shows no other page
changes.

Hand review (60–80 DPI `mutool draw` renders, pages 4, 8, 116): page 4 prints each edition, the
ISSN and the DOI on its own line with no prose flow between them, so one paragraph per line is the
faithful reading (the source tags them that way). Pages 8 and 116: title, quote and contents
entries as rendered.

### Controls

`identity.txt`:

| Book | EPUB | Warnings | Images |
| --- | --- | --- | --- |
| Blue Book | byte-identical | identical (312 unverified) | 425 |
| DGA | byte-identical | identical (4) | 28 |
| NBS | byte-identical | identical (1) | 8 |
| Our Flag | byte-identical | identical (2) | 147 |
| FAA handbook | byte-identical | identical (24) | — |
| Loper Bright, Replay Clocks, USGS | byte-identical | identical | — |
| Warren nine-page excerpt | byte-identical | identical (7) | 9 |
| CDC comic | byte-identical in run 1; differs in run 2 | identical (33) | 42 |

The CDC run-2 difference is Vision: pages 17 and 36 are `ocrUsed` pages and the *baseline* binary
itself produced different OCR text in its two runs (`cdc-page-diff-baseline-vs-baseline.txt`:
page 17 `An INOD gseg id` versus three recognized lines). CDC has no tags, so this change cannot
reach it. The Warren excerpt was built with PDFKit (`warren-excerpt.swift`) because pypdf is not
installed; its bytes differ from `measurements/gpo-warren-1964/excerpt-identity.json` but it holds
the same nine source pages (7 image-backed, all invisible only).

## Reproducer and controls

`Tests/PDFReflowLibTests/ImageBackedStructureTests.swift` (6 tests, 9 cases):

- `visibleTaggedTextOverABackgroundImageKeepsItsTags`: a page-sized image behind visible text with
  a body-size `H2` and a two-line `P`; the heading, `taggedLevel` 2/0, the joined paragraph, the
  retained `unverifiedTextLayer` and the one reference asset. **Fails at the baseline rule**
  (structure always cleared): 3 issues.
- `invisibleTextOverABackgroundImageNeverInheritsTags` (mode 3; visible plus one invisible
  fragment): no heading, no tag provenance, warning retained.
- `theSameTaggedPageWithoutABackgroundAppliesItsTags`: positive control that the fixture's tags
  apply on their own, without the warning.
- `graphicsReaderReportsAnyInvisibleText`: invisible, mixed, visible, and `3 Tr` with no show.
- `aTaggedPullQuoteAboveTheTextItIntroducesStaysItsParagraph`: Fed page 8's shape with a tagged
  four-line quote over contents entries. **Fails without the pull-quote exemption.**
- `aParagraphTagInHeadingTypeThatIsNotAPullQuoteStillHeadsTheTextBelow` (a one-line label, a
  two-line title without punctuation, two short sentences under eight words): #67's behaviour is
  kept.

Mutation results (`swift test --filter`, source restored after each): always-clear fails only the
visible reproducer; no-quote-exemption fails only the pull-quote test. Never-clear (dropping the
invisible guard) passes every test, because `MarkedTextReader` already refuses mode 3. The guard
is defence in depth that states the rule where the path lives and stays correct if the reader ever
accepts Form XObjects. No test can make it the sole barrier without changing the reader.

Fed contract (`corpus/regressions.json`, 110 → 126 checks in the case): page 4 three
`distinctParagraphs` (edition lines, ISSN/DOI) and its warning; pages 14 and 116 title heading,
quote paragraph, quote/title-fragment `absentHeadings`, contents entry paragraph, image presence and
(116) the warning. Negative control against the `6a5d67f` CLI
(`lane-summaries/fed-explained-2021-negative-control-6a5d67f.json`): the three page-4 checks fail.
The page-14/116 checks pass there too: their XHTML is byte-identical, so they pin the surroundings.
Tag provenance on the openers is pinned by the synthetic tests and `fed-tags-*.tsv`, not the EPUB.

## Verification

- `swift test`: 333 tests pass (327 at `6a5d67f` plus 6).
- `scripts/check-all.sh --fast`: exit 0 (333 Swift, 166 Python, 6 fixture conversions, 13 policy
  conversions with 22 rejection/cleanup cases).
- `tools/run_corpus_regressions.py --converter <candidate> --epubcheck /opt/homebrew/bin/epubcheck
  --case …` (`lane-summaries/`): PASS fed-explained-2021 (126 content checks),
  cia-blue-book-14-1955 (9), cdc-zombie-pandemic-2011 (11), dga-2025-2030 (14),
  nbs-jres-geltman-1977 (13), gpo-our-flag-2003 (67), with EPUBCheck, progress and memory gates.

## Remaining gaps and defects to file

- Fed page 8 (defect, pre-existing, identical at `6a5d67f`): the running head `vi` / `The Fed
  Explained: What the Central Bank Does` is drawn inside `/Artifact` *before* the full-page photo,
  which hides it, yet it is emitted as two body paragraphs above the chapter title. Expected:
  omitted, as on pages 14–116 where furniture removal takes it. Text painted beneath an opaque
  page-sized image is also a hole in "visible mode means visible" for any future warning policy.
- Whether born-digital photo pages should report `unverifiedTextLayer` is a separate policy
  decision (above); unchanged here.
- DGA pages 3–5 and the FAA's 23 image-backed tagged pages carry tags `MarkedTextReader` rejects
  (0 lines associated), independently of this path; not investigated here.
- CDC OCR pages 17 and 36 are not byte-reproducible run to run (Vision), which can make CDC EPUB
  hashes differ between identical binaries (#68 context).
