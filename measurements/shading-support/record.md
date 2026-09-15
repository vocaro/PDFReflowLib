# Bounded shading support

Tier: deterministic Apple PDF/OCR stack, release CLI defaults, macOS 27.0 (26A428) arm64,
Xcode 27. Corpus identities and limits are retained in each result. Build: base `178ccf0` plus
source identities in `implementation.json`; executable SHA-256
`9fed7af9cb6872ef13a596f1df9512fb9236e66a67e43db96e3637a9eeb4a0e8`.

## Behavior and qualification

The graphics reader resolves `sh` resources and bounds them by the current clip, transformed
Form BBox and optional shading BBox. Rectangles accept either corner order. Bounds are conservative:
Core Graphics renders the original appearance, including clipping, shading functions and labels.
No axial/radial coordinate endpoints are mistaken for painted bounds. Missing/malformed resources,
nonfinite geometry and regions spanning at least 75% of the page retain the safe page fallback.
The reader does not reconstruct editable gradient/vector objects.

Six original, in-memory PDF regressions cover clipped axial shading, radial BBox intersection,
transformed Forms and reversed coordinates, restored graphics state, curved clips, clipping
committed after a white fill, invalid/unbounded resources, and actual gradient pixel colors with
an overlaid label and adjacent reflowed prose. Existing synthetic fixtures remain unchanged.
The implementation follows the PDF reference's shading operator and clipping/BBox semantics.

## Final fresh-process runs

| Corpus | Pages with reflowed text | Peak RSS | Ceiling | Conversion time | EPUBCheck |
| --- | ---: | ---: | ---: | ---: | --- |
| DGA, 10 pages | 9 | 105,349,120 bytes (100.5 MiB) | 192 MiB | 0.73 s | Pass |
| FAA, 522 pages | 509 | 795,869,184 bytes (759.0 MiB) | 1,280 MiB | 35.74 s | Pass |
| Fed, 135 pages | 129 | 349,306,880 bytes (333.1 MiB) | 768 MiB | 12.41 s | Pass |

All three pass output structure, progress and existing memory limits. These are individual
process measurements, excluding separate Apple services, not iOS runtime measurements, latency
distributions or fidelity scores. Output and memory receipts are retained; complete progress logs
are losslessly compressed with identities. The DGA EPUB contains 27 images and is 7,848,859 bytes.

The pre-support DGA baseline records 2 reflowed pages and eight unsupported-graphics fallbacks.
The final run records nine reflowed pages and no unsupported-graphics warnings. This is improved
text availability, not a nine-page fidelity pass. Page 3 preserves the original page reference
because its collected graphics span most of the page; the generic large-graphic rule remains.

## Memory regression caught during development

The first shading-enabled FAA run exceeds the existing ceiling at 1,609,056,256 bytes peak RSS.
`faa-before-attachment-guard.json` retains that failed result and executable identity. Newly
reflowable pages invoke more PDFKit attributed-text extraction. Object-only selections have no
font style to preserve, so NativeTextReader avoids requesting their attributed strings, which
can decode image attachments. The final FAA run retains 509 reflowed pages and the same 584
images while passing the unchanged memory ceiling. This is a mitigation, not proof that Apple's
underlying attributed-text leak is fixed. Normal text still preserves bold/italic style extraction.

## Remaining fidelity defects

DGA page 3 now exposes existing column-order and placeholder defects: protein bullets interleave
left/right lines, and object-replacement characters become headings. Issues #2 and #8 track those
mechanisms. Page 1's native spacing and label association remain issue #14. Shading support alone
does not qualify bullet order or source tag semantics, and does not fix generic image sizing (#3).
Exact final XHTML for all ten pages and browser evidence accompany the DGA result.


The page-3 screenshot uses the shading build immediately before the attachment-access guard.
`dga/visual-equivalence.json` verifies that its page-3 XHTML, referenced image and CSS are
byte-identical to the final measured output. The final browser viewport is not used as retained
visual evidence. `validation.json` records the 35 Swift tests, 27 tooling tests, six fixture
conversions and successful iOS 27 device-SDK build; no physical-device performance is claimed.
