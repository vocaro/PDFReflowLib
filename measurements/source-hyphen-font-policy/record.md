# Owner-approved strong source-font evidence

Refs #214. On 2026-09-23 the owner chose: “Allow joins using strong font evidence.”
This follow-up implements that scoped choice. The ordinary dictionary rule still
retains a break between two independently valid words; only the exact joined word
identified by the strict source-font census can override that ambiguity. English
context remains required. A hyphenated compound actually attested in the document
retains its hyphen even when the closed word is also attested.

The census itself is unchanged from [the initial source-font measurement](../source-hyphen-fonts/record.md):
complete bounded resources and Form traversal, a hyphen-only same-family font,
at least four fully owned native wrapped breaks, at least three distinct known
joined-word calibrations, and a genuine body-font hard compound at a native wrap
also attested unbroken. Literal source glyphs and styles remain intact until an
actual join with the exact expected continuation. No issue-specific word list,
font-name exception or general dictionary relaxation is added.

The original page-11 operators show `as` in the body font, a separate hyphen-only
resource's `-`, then `say to test how well uniforms protect the` in the body font
on the next native row. The full page census has ten isolated break hyphens and
independent body-font `fire-` / `resistant` plus `fire-resistant` evidence. Under
the approved policy, this evidence now joins `bite-protection assay to test`.
A source-derived test uses the captured attributed rows through the real census,
metadata and join functions. Controls distinguish ordinary unannotated
`camera-man` / `by-law` / `as-say` from strongly evidenced breaks and retain every
source-attested compound, including when the vocabulary also contains its closed
form. Existing exact-continuation, styles, unsupported-state, Form, resource-limit
and cancellation controls remain.

Source identity, rights and attribution are unchanged: *Agricultural Research*,
November/December 2012, USDA Agricultural Research Service, SHA-256
`2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761`.
Only the existing owner-approved text derivatives are used; no rasters or crops
are committed.

Validation:

- All 790 Swift tests pass with the coordinator's already committed page-17
  expectation correction (`5f83cc2`). That prerequisite was applied only for the
  test run and is not repeated in this follow-up commit.
- All 33 Python corpus-content tests pass.
- The exact prior `41b77bf` runtime and its previously validated full 24-page output
  serve as the comparison parent. Its binary was preserved before rebuilding;
  SHA-256 matches the prior measurement. The new normal-basename release binary
  converts the complete original PDF and passes EPUBCheck and the 512 MiB RSS gate.
- Exactly one source text change occurs: page 11 `as-say` becomes `assay`. All three
  XHTML documents are byte-identical after that single substitution. All 85 image
  assets and all 24 source page markers are identical. Every other page is unchanged.
- All 67 magazine content assertions pass. The exact parent fails only the two new
  page-11 assertions requiring `bite-protection assay to test` and excluding `as-say`.

`results.json` records binary/output hashes and both validation results. The parent
output remains in `/tmp/pdfreflow-214-hyphen-candidate`, its preserved binary in
`/tmp/pdfreflow-214-font-policy-parent-bin`, and the candidate output in
`/tmp/pdfreflow-214-font-policy-candidate`. Root owns integration, broader corpus
qualification and issue closure; this commit does not push or close the issue.
