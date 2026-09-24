# Chinese IRS underline ownership controls

The raw native layout from physical pages 4 and 16 of IRS Publication 596
(Simplified Chinese, 2025) pins a regression introduced by separating painted
regions before table inference. A linked phrase paints its underline as adjacent
pieces. Keeping each piece as an independent table rule creates a large crop
across both text columns and suppresses native prose. Joining collinear pieces
before inference restores the source's single rule.

Source: `p596zhs--2025.pdf`, 36 pages, SHA-256
`7d1cff45bc567f1257ea1aa1e2ce67945aafb12708b2e22901ce6392436590c2`.
The two JSON fixtures retain native text, geometry, styles and paint operations;
they contain no page images. The source pages were rendered and inspected to
confirm that the linked phrases are prose, not table cells.

The parameterized control checks absence of a giant cross-column crop and
retention/order of real source sentences, including the address and feedback
paragraph on page 4, and the examples, income limits and embedded English
`Clergy filing Schedule SE` instruction on page 16. Disabling only `joinedRules`
reproduces four failures across these two pages, including the lost sentences.
The restored repair passes both cases. The complete Swift suite passes all 795
tests (47.24 seconds). This commit adds controls for the repair
in `af2c126`; it does not duplicate that runtime change.

The complete 36-page Chinese corpus lane passed all 17 content checks, structural
checks, progress, EPUBCheck and the 256 MiB RSS ceiling. Conversion took 8.23 s
with peak process RSS 179,404,800 bytes, 33 reflowed pages, no recognized pages and
187 images. These are one-run macOS process measurements, not mobile or latency
claims. Existing fidelity limitations outside these contracts remain.

Validation tree: `790ad778` plus the `af2c126` repair (locally cherry-picked as
`cccb5a4`) and these source controls. Release executable SHA-256:
`ba02748bbf5e7b77848c4acfb63ceeb7054f8448c2f1ea917449cf00ec9d62ab`.

Commands:

```sh
swift test --build-system native --scratch-path /tmp/pdfreflow-irs-build
swift build -c release --build-system native --scratch-path /tmp/pdfreflow-irs-build
/opt/homebrew/bin/python3 tools/run_corpus_regressions.py \
  --converter /tmp/pdfreflow-irs-build/release/pdf-reflow \
  --epubcheck /opt/homebrew/bin/epubcheck \
  --output /tmp/pdfreflow-irs-corpus --case irs-p596-zhs-2025 --settle-seconds 0
```

Local diagnostics and rendered source pages remain outside the repository under
`/tmp/pdfreflow-irs-*` and `/tmp/irs-joined-rule-*`.
