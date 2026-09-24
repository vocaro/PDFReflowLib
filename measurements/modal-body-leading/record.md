# Corroborated modal-body line spacing

Fed Explained (2021), physical page 95, sets its ordinary 10 pt body on 16 pt
leading beside a smaller sidebar and figure notes. Its modal font size remains
10 pt, but the smaller notes make the page-wide leading estimate 10 pt. The
secondary-body rule previously supplied the correct spacing only when the
ordinary body was larger than the page's modal size, leaving this page's body
split into one paragraph per row.

The correction allows the existing strict, document-corroborated native prose
run to supply its own leading when its size equals the modal size too. No
paragraph-width or heading threshold is relaxed. The second full-width paragraph
provides six rows of ordinary prose, so the first paragraph's narrowing around a
sidebar need not become a new inference rule. Geometry and modal estimates stay
unchanged. Native size evidence, document corroboration and all quote, caption,
bold, tagged-heading and sentence exclusions remain required.

The pinned source fixture is from `the-fed-explained.pdf`, SHA-256
`8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60`.
The test restores its native attributed styles, composes its real painted regions,
infers actual crops and reconstructs blocks. It checks the entire second
paragraph, its last continuation, and the 16 pt leading associated only with the
proven 10 pt run. Controls remove the 10 pt prose or native-size evidence and
ensure no 10 pt leading override survives. Existing NOAA display-heading and Fed
13/46 source controls cover heading boundaries and smaller-note separation.

The source page was rendered and inspected. The sidebar ordering correction is a
separate integration change; this test does not claim that correction. Root owns
the combined full-publication qualification. Local source rendering and test logs
remain outside the repository at `/tmp/fed95-source.png` and
`/tmp/pdfreflow-fed95-*`.

Validation: all 802 Swift tests pass (24.20 s) on the root integration base
`c14ce835` plus this correction. Replacing only `documentBody >= body` with the
previous strict `>` reproduces four failures: missing spacing evidence and three
missing continuations from the second paragraph. The restored candidate passes
the focused source control. No runtime file from another agent is changed.

```sh
swift test --build-system native --scratch-path /tmp/pdfreflow-fed-variable-build
swift test --build-system native --scratch-path /tmp/pdfreflow-fed-variable-build --filter modalFedBody
```
