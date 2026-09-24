# Preserve independently proved body columns

The final v2 corpus used converter SHA-256
`c7639db60d9498dcb33133acca3d9588855ffa63a03c99e4b1db9ef285ea6d9b`.
Its USDA output preserved every native letter and every image byte relative to the first
qualified candidate, but physical pages 8, 10, 13 and 15 regressed to rowwise column
interleaving. The existing page-8 insecticide assertion caught only one symptom: automatic
`pyre-`/`throids` and `neonic-`/`otinoids` breaks no longer reached one paragraph.

All four source pages have wide photograph captions that are valid floating units above or
below the body columns. Adding their rows to the column evidence changes the body-column
vertical range to include that same caption; the subsequent floating-unit check then rejects
the whole plan. On page 8 the caption rectangle is [62.64, 72.74, 254.66, 40.65], extending
the left-column bottom to 72.74. On pages 10, 13 and 15 the captions extend the inferred
column tops to 417.58, 332.55 and 408.98. This is a self-created obstruction, not ambiguous
source column geometry. Restricting the small-caption detector to raster proximity alone
still reproduced all four failures.

`PrintedColumns` now tries its existing body/quotation-only proof first. Only if that plan
fails does it add the independently proved caption rows. Caption units, native content,
figure crops and both plans' admission conditions stay unchanged. The fallback still
supports the NOAA caption measures for which the additional evidence was introduced.

The four new schema-3 fixtures contain original native lines, attributed styles, paint
operations and geometry from the checksum-pinned `November-December2012.pdf`, SHA-256
`2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761`.
They contain no raster references or generated output. Tests replay the production structural
page-reference preparation for the page-sized photograph on page 13. They require an intact
source body paragraph, a separate caption and each local figure exactly once. The corpus
contract adds the same four whole-paragraph assertions, preserving the existing strong-font
hyphen policy assertions and all prior source checks.

Validation: all four final source controls fail on the unchanged parent planner. With the
fix, all four source pages and the existing NOAA 56/58/67 and FAA 45/216 caption controls
pass, along with incomplete-tag, remote-art, changed-row, caption-margin and short-terminal
continuation controls (five parameterized Swift tests, nine source pages). The 33 corpus
content Python tests pass. The coordinator owns the final integrated full conversion and
resource qualification; this record does not claim a completed full-corpus run for this fix.
