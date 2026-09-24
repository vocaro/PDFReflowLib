# Aggregate alpha-mask preflight

The final #191 integration run exceeded the DGA's unchanged 192 MiB process RSS
ceiling: 231,981,056 bytes in the full corpus, then 225,918,976 bytes in an isolated
repeat. The same runtime also converted the cover's 118 native characters into
seven crops, losing the #172 title/label contract. Both failures are retained in
`results.json`; successful later runs do not replace them.

Source: the complete ten-page `dga-2025-2030` document, SHA-256
`c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472`.
The cover was rendered and compared directly with both outputs. Its title, both
ampersand-led labels, Whole Grains and both footer labels are real native text.
The source's newly retained ICC ground legitimately identifies flat paint; its
numeric tuples still do not prove white, and no ICC color classification changes.

That ground made the cover eligible for optional backdrop composition. The cover
has 45 soft-mask placements totaling 164,359,023 decoded 8-bit samples, although no
individual mask exceeds the existing 64-million-sample cap. Each placement opens a
short-lived source document for decoding, including repeated resources. The
per-image lifetime bound did not constrain the aggregate work or transient memory
pressure of this large page pass.

A metadata-only preflight now applies the existing 64-million-sample resource limit
to the complete page before decoding any mask. Each placement is counted according
to the actual decoding strategy. Unknown mask estimates, invalid sizes and an
excessive sum decline composition altogether, preserving the original conservative
page geometry and native/reference behavior. Admitted images continue to use the
existing isolated decoder. No memory ceiling, raster resolution, source ownership
rule or ICC color rule is relaxed.

The source text fixture `dga-cover-alpha-budget.json` records the original native
PageContent, raw paints and mask dimensions' sample counts. It contains no raster
or PDF data. The source control proves the flat-ground admission, rejected total,
retained reference flow and all original title/label paragraphs. Generated PDF
controls exercise the actual PageReader hook with a valid small mask, an unknown
mask estimate and two placements of one declared 64-million-sample mask; the last
case proves reused resources are counted before decoding. Boundary and overflow
controls accompany the existing Earthdata source and isolated small-mask controls.
All five focused tests pass. The existing DGA corpus contract already pins every
native cover label and title; its basis now records this regression rather than
adding duplicate assertions.

The release candidate (exact hash in `results.json`) converts the complete DGA in
121,700,352 bytes RSS (116.1 MiB), below the unchanged 201,326,592-byte ceiling.
All 20 content checks pass and all ten pages reflow. Only page 1's text changes
against the failed runtime: all 118 characters return, identical to the landed
baseline's cover. Pages 2–10 retain the failed runtime's text exactly. EPUBCheck
3.3 was run separately on this candidate and reports zero errors or warnings.

All 21 Earthdata slides also convert with the same binary in 97,337,344 bytes RSS,
passing EPUBCheck and all 68 content checks. Every page's text and every image asset
is unchanged from the final preflight-free runtime. Its largest page mask total
is 1,503,171 samples. This checks the small-alpha behavior that backdrop composition
needs; generated padded-icon and real Cumulus fixtures additionally pin native
label ownership. Root owns the final integrated full-suite and full-corpus rerun.
