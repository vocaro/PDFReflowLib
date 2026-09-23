# Document corroboration and paragraph spacing

Measured on 2026-09-23, refining the earlier `6e01207` experiment. The final implementation is
`57bb475` (document corroboration) plus `b4b2adf` (secondary-body leading).

## A larger display is not the document's ordinary body

Independent full-document comparison found five genuine NOAA headings demoted on physical
pages 1691, 1712 and 1730. Source inspection confirmed that each page prints a long 14 pt
summary above ordinary 10 pt prose and genuine 14 pt headings. The first guard accepted the
summary's repeated measure and raised the heading threshold to 15.4 pt. The exact earlier
implementation fails the new three-page source test with 16 assertions.

The secondary size now requires the document's body estimate to exceed the page's modal
estimate, and must fall within 105% of that document estimate. Without document evidence,
page-local typography is unchanged. The Fed's 10 pt body is corroborated; NOAA's 14 pt
display summary is not. The source tests retain all five reported NOAA headings under both
page-only typography and a 10 pt document body.

The three new captures identify `noaa_61592_DS1.pdf` with SHA-256
`1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf`.
They were captured from the real cached document with `capture-layout-fixture` and retain
the captured source text, geometry and attribution. Source page 1691 was also rendered and
viewed to confirm the summary/body/heading distinction.

## Larger body rows must keep their own spacing

The integrated Fed conversion then exposed a separate failure: page 46's opening was no
longer headings, but each printed row was its own paragraph. The smaller table text supplied
the page's dominant leading, so the ordinary body's 16 pt baseline interval exceeded the
assembler's allowance. The original source assertion only required an opening paragraph;
the strengthened assertion requires the first two rows to occur in one paragraph.

Only the corroborated secondary size now receives its own measured leading. Other sizes
continue to use the original page leading. A negative control confirms that the override
joins 10 pt body rows on 16 pt leading while leaving 8 pt notes separated under their
original 10 pt leading. No initializer caller is required to provide an override.

## Verification

- Four focused tests (seven parameterized executions) pass, including both Fed sources,
  all three NOAA sources, native/display exclusions and the smaller-note spacing control.
- All 767 Swift tests pass in 28.933 seconds after building, including #296 controls.
- An isolated checkout of integrated commit `4e072e4c`, with these refinements, reads the
  actual Fed PDFs through PageReader and reconstructs all seven opening rows on page 46
  into one paragraph. Page 13 also joins correctly. The same actual-source diagnostic
  retains the five NOAA headings. This diagnostic supplied a 10 pt document body; the
  integrating task owns the full-document conversion and document-evidence qualification.

Logs remain outside the repository: `/tmp/pdfreflow-fed-prose-noaa-failed-control.log`,
`/tmp/pdfreflow-fed-prose-leading-controls.log`, `/tmp/pdfreflow-fed-integrated-audit.log`,
and `/tmp/pdfreflow-fed-prose-final-suite.log`. The regular tests use the same `swift test`
commands as the earlier record, with scratch path `/tmp/pdfreflow-fed-prose-build`.
