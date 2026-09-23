# The Fed's opener summaries are asides

This addresses only the Fed display-summary item of #214. The owner approved `<aside>`
semantics and exclusion from navigation on 2026-09-23 in
https://github.com/vocaro/PDFReflowLib/issues/214#issuecomment-5797549469.
The magazine continuation, footer and hyphen items remain separate work; this is not a
closure claim for the umbrella issue.

Source: *The Fed Explained* (2021), SHA-256
`8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60`.
The seven physical opener pages are 8, 14, 24, 50, 66, 88 and 116. All seven were freshly
captured with native text geometry and rendered with Poppler for visual review. Each sets
one complete, unquoted summary in three to five 14 pt lines below its 24 pt title, with a
large blank gap before the smaller 10 pt dotted chapter contents. The chapter numeral is
70 pt and PDFKit sometimes joins it to a title line; the union's height is not the title's
actual leading. The captures preserve this source behavior. No expected aside was injected
into a fixture.

The baseline is `a1af5d3` (the column continuation and backdrop prerequisites). The shared
aside/quotation model is `ae54844` (applied here as `9814824`). The new `DisplaySummary`
helper requires a complete sentence of at least twelve words across three or more stacked,
aligned display lines, a larger title immediately above, and a separated smaller contents
list with at least two dotted rows below. It claims only those display lines. Recognized
or synthetic-style pages do not use this native-typography rule. An opening quotation mark
is excluded; attributed quotations keep their own semantics. The rule uses no source name,
page number or particular summary text.

Reconstruction emits the claimed run as one aside while preserving inline content, the title,
and contents. The existing shared encoder writes `<aside><p>...</p></aside>` without a
navigation heading. The corpus reader separately records complete asides and quotations,
including inline styles and page ownership. A paragraph, a wrong-page block, or separate
fragments cannot satisfy these semantic assertions. Shared checker commits are `1bf80d2`
and `33288f0`; the second keeps literal field names visible to the existing count-source gate.

Validation on macOS 27 arm64:

- All 733 Swift tests pass, including the parameterized source test covering all seven openers.
  Negative controls remove the larger title, remove contents, close the gap, demote display
  type to body size, remove sentence punctuation, introduce an opening quotation mark, or mark
  the page as recognized/synthetic. The shared model test checks actual aside/blockquote markup
  and absence of navigation headings.
- All 38 focused corpus/count-source Python tests pass. The complete 252-test Python suite
  leaves only the two generated-document-count checks failing; counts are deferred to final
  integration, not changed on this branch. One unrelated test is skipped.
- Both full 135-page conversions pass EPUBCheck, structure, progress and memory checks. The
  final Fed corpus contract passes 67 checks; the baseline fails exactly the seven new aside
  checks. The existing title assertions and navigation behavior remain valid.
- `comparison.json` compares every page's text, headings, paragraphs, asides, quotations,
  lists, tables, images and preformatted blocks. Only the seven opener pages change, and only
  their heading/paragraph/aside roles. All page text and markers are identical; all 237 image
  files are byte-identical. Navigation text is identical and contains none of the summaries.
  Each newly emitted aside is the complete source summary, with no title or contents included.

Reproduction from the repository root (Python 3.10 or later):

```sh
swift test
swift build -c release
python3 tools/evaluate_real_document.py --case fed-explained-2021 \
  --pdf corpus/cache/the-fed-explained.pdf --converter .build/release/pdf-reflow \
  --output /tmp/fed-display-summaries --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/check_corpus_content.py --case fed-explained-2021 \
  --evaluation /tmp/fed-display-summaries
python3 -m unittest discover -s tools -p test_corpus_content.py
pdftoppm -f 8 -l 8 -scale-to 1000 -singlefile -png \
  corpus/cache/the-fed-explained.pdf /tmp/fed-opener-8
```

| Measurement | Baseline | Candidate |
| --- | --- | --- |
| Converter SHA-256 | `a42f8947575f6df3cb9512cf6f2bcd2e4c3119760fb416e75192a95b09bfa36a` | `2dbddc1c5b4820a1e15f121c172236d98da54784ea0cbf026e7ad95fc1772e72` |
| EPUB SHA-256 | `7cdce02594858ee6639c44b0d646e1a8851c21fc92ec9e078b3d8314101e0ed3` | `a7bf3a3fab6191f49f400a80af4d7a929fb067ad9c34d2a0f1fe11490e5a0e16` |
| EPUB bytes | 22,717,065 | 22,716,972 |
| Text characters | 207,348 | 207,348 |
| Conversion seconds | 42.56 | 11.35 |
| Peak RSS bytes | 305,233,920 | 294,322,176 |
| Sampled peak physical footprint bytes | 209,454,112 | 199,050,224 |

Both receipts recorded one concurrent evaluation. Timings include differing cache conditions
and are not a performance comparison. No mobile budget or whole-book visual qualification is
asserted; `qualifiedForFidelity` remains false. Raw source captures, renders, logs, EPUBs and the
comparison script remain outside the repository under `/tmp/pdfreflow-214-evidence` and
`/tmp/pdfreflow-214-audit`; only the record, small summary and regression fixtures are committed.
