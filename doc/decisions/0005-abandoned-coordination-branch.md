# 0005 The coordination branch is abandoned; features are hand-ported onto main

## Context

`claude/fable-agents-coordination-d95da7` fanned in parallel work from many GitHub issues at
once: 153 commits, diverged from main at `56e70e2` on 2026-09-16. Its pipeline evolved
independently of main's and became architecturally different in several places: content-stream
font-resource reading (`FontWeightReader.swift`), a sub-heading classification subsystem
(`sectionLabels`, `LabelStyle`, `boxTitles`, document-wide heading ranking, heading tiers),
tinted background-region extraction (`page.tints`), a `layoutComesApart` test that tells a
born-digital page with a full-bleed background paint apart from a scan (#117), list conversion
and reading-order changes. Merging its diffs onto main was no longer possible without carrying
that architecture across.

## Decision

The branch is abandoned. A session on 2026-09-19 (commit `1b0308b`) declared it so and set the
working convention: a feature the branch holds is hand-ported onto main's current code, adapted
to main's simpler pipeline, landed as its own commit with its own tests and corpus review, and
verified against the real, checksum-pinned documents rather than copied from the branch's
records. The branch was closed out with an "ours" merge (`dd160b4`) so it stops being a
diverged, orphaned line without changing main's tree, and its worktree and ref were deleted.
Issues the branch had addressed were closed by comments citing the branch's own commits; a full
audit of its remaining 150 commits found one uncaptured finding (partial progress on #120,
recorded there), and #195's four blocking prerequisites were scoped into #219 from code
investigation against both trees.

## Consequences

What was ported, each as its own commit:

- **#93, #7** (`1b0308b`): `TextLayerPlausibility` and `OCRTextCoverage`, with the new
  `.automaticKeepingImageBackedText` policy. `TextEncodingCheck` was deliberately not ported with
  it; plausibility got its own language check instead.
- **#176** (`32b8cb2`): drawn-text recognition. One adaptation: `GraphicsReader.Result` gained an
  `images` field (placed raster XObjects) so photographs can be excluded from the ink test, which
  the branch's richer graphics model already could. The candidacy gate does not require
  `!imageBackedText` as the branch's did, because main has no `layoutComesApart`; `reflowsNoWords`
  keeps the check out of #93's territory instead.
- **#38** (`5b486f3`): `TextEncodingCheck`, unchanged from the branch, since it depended on
  nothing that had evolved. The branch's Wallace answer-key and USGS controls were not fetched
  for this port.
- **#186**, three of five fixes (`edc162b`): the document-body heading floor, the lowercase
  standalone-heading exclusion, and lexicon-decided hyphens. One genuine bug beyond the literal
  port: the branch's `lexiconVouches` let a half stand as a word if either the vocabulary or the
  lexicon said so, which on main's page-local vocabulary (no `opensBrokenWord`) kept `com-panies`
  hyphenated; main's version consults only the lexicon for a half's standing.
- **#21** (`0e89095`): the gate drain and about forty gated test call sites ([0002](0002-pdfkit-extraction-gate.md)).
- **#218** (`77642a4`), the fifth #186 fix: a bold sub-heading whose paragraph opens past a
  photograph. Tracing the branch's `opens(beneath:)`/`pastFigure(_:)` surfaced at least eight
  prerequisite commits across #43, #55, #63, #73, #76, #90, #97, #100, #102 and #159 building the
  whole sub-heading subsystem. Only the bold, body-adjacent path was ported (`LabelStyle` reads
  main's bold flag; `firstLineIndentRun` from #159; `isThinRule` from #100 unchanged).
- **#217** (`6f0991d`), the remaining two #186 fixes: dingbat fonts read through their own
  encoding and a font's drawn letter case trusted over `ToUnicode`. Initially deferred because
  both needed the branch's `FontWeightReader` and main had no content-stream font reading at all;
  ported once a narrowly scoped `GlyphIdentityReader` in the mold of `NativeSpacingReader` proved
  sufficient, and pinned on the magazine's pages 15 and 24.
- **#4** (`d677ebe`): one PDFKit union request per page, re-verified fresh against main (leak
  counts, FAA byte identity, full suite) rather than copied from the branch's `wip/issue-4` record.

What was not ported, and why: `layoutComesApart` (#117), so an ordinary slide export still reads
as image-backed and reports `unverifiedTextLayer` (#164 open, as it was on the branch); italic
labels (#97), two-line stacked titles (#102), hanging-entry titles (#134), outline labels (#152)
and tinted-box titles (#100, `boxTitles`), because no main-corpus document exercises them and
each would add untested false-positive surface to a function that runs on every page; the
branch's general bold/italic font machinery, replaced by the narrow glyph reader.

Test files that carried the porting narrative were rewritten to a sentence each when the suite
was reorganized by unit; issue linkage is a `.bug()` trait on the tests.

## Evidence

Commits `1b0308b`, `dd160b4` and the porting commits above; the corpus contract's `basis` for
`usda-ars-agresearch-2012-11` in `corpus/regressions.json`, which records the adaptations
against the real magazine; [corpus.md](../corpus.md#agricultural-research-magazine).
