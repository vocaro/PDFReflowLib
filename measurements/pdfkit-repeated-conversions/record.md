# PDFKit attributed-text growth across repeated conversions (#4)

2026-09-19, macOS 27.0 (26A428), Xcode 27, Apple silicon, release builds. Baseline is main at
`dd160b4`; candidate is `dd160b4` plus this change.

This is a hand-port of the union-request optimization first explored on the abandoned
`claude/fable-agents-coordination-d95da7` branch (see its own
[record](https://github.com/vocaro/PDFReflowLib/blob/wip/issue-4-pdfkit-growth/measurements/pdfkit-repeated-conversions/record.md)
for the original diagnostic campaign: content-stream evidence for what leaks, FAA/Fed/TechPort+
magazine leak counts, iOS Simulator numbers, and NOAA/Warren byte identity). That branch's
`extractLines` carried other, since-superseded machinery (`FontWeightReader`, index-glyph
carry/repair, split-show joining) that main never adopted; merging it directly would have
reintroduced that abandoned pipeline. This port applies only the union-request change itself to
main's current, simpler `NativeTextReader.extractLines`.

## What grows

Every leaked root PDFKit's `leaks` finds after repeated conversions is an
`NSConcreteMutableAttributedString` allocated under `PDFSelection.attributedString`, called from
`NativeTextReader.extractLines` once per line. This is the same root cause diagnosed on the
original branch (FB24783799): PDFKit leaks every attributed string it returns, so a request per
line leaves that whole object graph (the string, its runs, a font and attribute dictionary per
run) behind for every line.

## Change

`NativeTextReader.extractLines` reads a page's styled lines with one attributed request on the
union of their selections and slices each line out of it, instead of one request per line.
`attributedTexts` (private: every PDFKit call it makes must stay inside the extraction gate, #21,
which only its caller `extractLines` is verified to run inside) fetches the union's plain and
attributed text. `sliceUnion` (internal, pure — no PDFKit call, needs no gate) does the alignment
check and slicing: each line's text must appear in order in the union's plain and attributed text
(`lineRanges`), directly or after one newline, otherwise the page falls back to requests per line;
so does a page with a single styled line. `AttributedExtractionTests.swift` checks `sliceUnion`
and `lineRanges` directly, and that every slice is `isEqual` to the line's own per-line request on
a synthetic multi-font PDF (bold heading, italic phrase, a two-piece row PDFKit reads as one
line).

## Results, leaked per conversion (Mac, `leaks`, `tools/check_repeated_conversions.py`)

Three Fed (135-page) conversions in one process, pinned packaging:

| | Baseline (before #4) | Candidate (this change) |
| --- | ---: | ---: |
| Leaked objects per conversion | 22,919 | ~1,758 (two runs: 1,756 and 1,758.5) |
| Ceiling (30/page × 135 pages) | fails (764% over) | passes |

About a twelfth of the leaked objects. What is left is the page text itself, which only Apple can
release (FB24783799); leaked bytes are reported by the gate but not bounded, since they vary by a
few percent from run to run (candidate: ~1.15–1.16 MB per conversion).

## Output identity

Pinned-packaging CLI output (`--package-identifier`/`--modification-date`) is byte-identical
between the baseline and candidate release binaries on the FAA corpus source (522 pages, two
columns, tables, equations, tagged PDF — the library's primary regression document): both
conversions produced SHA-256 `12463b3e499664711ea60d17d3b4bbfdd6754abb375410788e882dd97a027efd`.

`swift test` (254 tests) and `python3 -m unittest discover -s tools -p 'test_*.py'` pass, as does
`scripts/check-all.sh --fast` (six fixture conversions, EPUBCheck, policy and rejection cases,
concurrency harness). The full corpus lane (`--corpus`) was not run for this port; the FAA
byte-identity check above and the unit-level `isEqual` check in
`AttributedExtractionTests.swift` are the correctness evidence for this change specifically. A
fresh-process peak-RSS comparison, the remaining `probe-pdfkit-memory.swift` `union` sweep across
more corpus documents, and a physical-iPhone repeated-conversion run were part of the original
branch's campaign and were not repeated here; nothing about this port changes those open
questions, which stay tracked on
[issue #4](https://github.com/vocaro/PDFReflowLib/issues/4).

## Gate

`tools/check_repeated_conversions.py` runs three Fed conversions in one process with `leaks` and
fails above 30 leaked objects per page per conversion or on differing EPUBs; wired into
`scripts/check-all.sh --corpus`. `tools/probe-pdfkit-memory.swift` gained `text-line` and `union`
diagnostic modes (ported, unchanged from the original branch) for isolating this growth outside
the library.
