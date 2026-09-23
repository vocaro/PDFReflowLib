# Resume a prose column past its figure

Issue #160, measured 2026-09-23. Parent `4e04c7f`, implementation `3025c9b`,
review hardening `b8bd603`. Source: the corpus-pinned FAA handbook, SHA-256
`247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7`.

The issue's current trace is correct: page 24's FAA Safety Team paragraph has no usable
structure group on either side of the picture. The left column ends `The FAA`; the right
column begins `Safety Team (FAASTeam) exemplifies this commitment.` The image and caption
between them flush the paragraph before ordinary adjacent-line rules could consider it.
A word vocabulary cannot solve that boundary.

`ColumnContinuation` recognizes an unfinished, full-measure prose column followed only
by a figure and its caption, then the top of a matching next column. Both ends must have
nearby same-size prose supporting their column geometry. Completed sentences, heading
roles, incompatible source groups, spanning figures and intervening prose are boundaries.
The assembler suspends the existing paragraph and resumes it through a stable block
handle. Its original text and styles remain before the figure; the figure and its caption
keep separate blocks. Source page 24 was rendered and visually reviewed.

Three tests cover the actual checksum-pinned page, style/image/caption preservation, and
negative boundary cases. Agent review prompted `b8bd603`: the supporting column lines must
also be prose rather than headings, list rows or captions. Its focused tests pass. The full
728-test Swift suite passed on the implementation before that guard was tightened.

The exact `3025c9b` release and its parent each convert all 522 pages and pass EPUBCheck,
structural/progress validation and the 1,280 MiB Mac RSS gate. The source contract passes
all 94 assertions; the parent fails exactly the new paragraph assertion. The release also
matches the initially audited candidate's complete parsed output after an equivalent
short-circuit avoided unnecessary geometry scans.

Across all 522 pages, only 21 pages change text order and paragraph grouping. Each change
is exactly two paragraph fragments becoming their space-joined paragraph; all pages retain
the same word multisets, headings, lists, tables and preformatted blocks. Every join was
read in context and is an unfinished source sentence continuing in the other column;
`comparison.json` records each boundary. No caption is absorbed. All 620 image entries
are byte-identical and all source-page markers match. This is not a claim that unrelated
reading-order defects elsewhere in the book are fixed.

Items 1 and 2 were already resolved as recorded in the issue's comments: the source-based
FAA 341/391 and Blue Book hanging-entry regression tests remain in the full suite, and
FAA 397's accepted column order remains unchanged. This change resolves the remaining
page-24 continuation. The integrated stable-binary corpus lane additionally checks the
final review guard across all registered documents.

Raw books, captures and logs stay under `/tmp/pdfreflow-160-*`. Reproduce with Python3.10+:

```sh
swift test
swift build -c release
python3 tools/evaluate_real_document.py --case faa-phak-8083-25c \
  --pdf corpus/cache/faa-h-8083-25c.pdf --converter .build/release/pdf-reflow \
  --output /tmp/faa-column-continuation --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/check_corpus_content.py --case faa-phak-8083-25c \
  --evaluation /tmp/faa-column-continuation
```

RSS and elapsed time are observations of Mac runs under concurrent agent work, not
physical-device budgets or a performance comparison.
