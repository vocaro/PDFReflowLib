# Wrapped native prose beside smaller recovered text

Measured on 2026-09-23. Implementation: `6e01207`, based on main `49f85588`.

The magazine composition work released native footnotes and table text that had been kept
inside source crops. In *The Fed Explained*, that smaller text outweighs the ordinary body:
physical page 13 has 921 characters at 7 pt and 633 at 10 pt; page 46 has 2,024 at 8 pt and
1,129 at 10 pt. A modal-size heading threshold then labels the 10 pt paragraph rows as headings.

The new floor requires a sustained native paragraph: at least four rows and 200 characters,
consistent type size, left edge and leading, a filled measure and lowercase continuations.
Quotation openings, caption openings, wholly bold runs, tagged headings and rotated text do
not establish this additional size. Recognized or synthetic typography does not use the floor.
The modal body used for geometry is unchanged; the additional evidence raises only the
heading-body estimate. The smaller text continues to reflow.

## Source and controls

Both committed source-layout captures identify `the-fed-explained.pdf` by SHA-256
`8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60`. They are extraction
captures from physical pages 13 and 46, copied unchanged from the magazine investigation.
The tests replay all captured text as released from decoration crops, check that the body
opening becomes a paragraph, retain the smaller source text, and retain a larger title.

Running those tests with the exact `49f85588` PageTypography implementation produces
29 failed assertions, including 28 in the two real-source cases. Restoring `6e01207`
passes both tests (three parameterized executions). The full 765-test Swift suite passes,
including the source-backed #296 sparse-title and native-versus-recognized controls.

Commands, run in the isolated `/tmp/pdfreflow-fed-prose` worktree:

```sh
swift test --build-system native --scratch-path /tmp/pdfreflow-fed-prose-build --filter wrappedProse
swift test --build-system native --scratch-path /tmp/pdfreflow-fed-prose-build
```

Raw logs remain outside the repository:
`/tmp/pdfreflow-fed-prose-tests.log`, `/tmp/pdfreflow-fed-prose-failed-control.log`, and
`/tmp/pdfreflow-fed-prose-suite.log`. The final full suite took 30.928 seconds after building.
This record establishes the isolated typography fix and its controls; full-document
conversion with the magazine composition changes is verified by the integrating task.
