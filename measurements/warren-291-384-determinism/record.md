# Warren pages 291 and 384 across repeated runs

`gpo-warren-1964` pages 291 and 384 once reconstructed differently from one run of a binary to the
next (#169 item 3, #300). The cause named then was the page body size: two rounded type sizes
carried the same number of characters, and a `Dictionary` max chose between them in the process's
hash order. `main` breaks that tie on the smaller size since 6ad52fb8. This record reruns both pages
on `main` at 684cf06b, the way the original observation read them and through the CLI.

Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max. Source SHA-256
`341cc3471750c9c3be68b95a34b52f6cbdc86c4392427a8483ee1c6bc53cfc19`. Measured 2026-09-25.

## Outside the pipeline

The original observation used the `blocksurvey.swift` probe from #141 (branch commit 1a18b7a3):
one page read and handed straight to `LayoutReconstructor.blocks`, with no furniture pass, no
recognition and no document context. Its `main` equivalent reads the page with `PageReader.read`
and reconstructs it four ways — with the synthetic-text flag as read and inverted, and with the
page's graphics and pictures kept or removed, removing them being what the old probe did for a
page-sized scan. It ran in eight separate processes, so eight different hash seeds:

| Page | Variant | Blocks | Distinct outcomes in 8 runs |
| ---: | --- | ---: | ---: |
| 291 | graphics kept, flag as read (`true`) or inverted | 1 | 1 |
| 291 | graphics removed, flag as read | 12 | 1 |
| 291 | graphics removed, flag inverted | 12 | 1 |
| 384 | graphics kept, flag as read (`true`) or inverted | 1 | 1 |
| 384 | graphics removed, either flag | 3 | 1 |

Every stage hash (page content, crop regions, blocks) agreed across all eight runs.

Neither page ties any more. The characters per rounded size are, on page 291, 8 pt 51, 17 pt 39,
4 pt 38, 19 pt 32 and fewer at five other sizes; on page 384, 16 pt 60, 7 pt 27 and 8 pt 3. The
weighting is the one the tie was measured under; the lines have changed since, as the extraction
repairs landed. So these two pages no longer exercise the tie-break at all, and the rule itself is
held by `bodySizeBreaksATieOnTheSmallerTypeDeterministically`, which does not depend on a hash seed.

## Through the CLI

The CLI has no page-range option, so the pages were cut out with qpdf 12.4.0
(`qpdf --empty --pages GPO-WARRENCOMMISSIONREPORT.pdf 289-293,382-386 -- excerpt.pdf`, ten pages,
SHA-256 `a3bff5986e0a91badfe91fa18f81d5ccfe01371e035df9713f97f79739d59dc3`) and converted five
times by one release build at library defaults with
`--package-identifier urn:uuid:identity --modification-date 2026-01-01T00:00:00Z`.
`tools/epub_identity.py` reported every run identical to the first, EPUB and report alike. The
excerpt's page 4 (source 382) was recognized and compared (`implausibleTextLayer`), so Vision ran
in each; the first run compiled the models (65 s) and the rest reused them (6–10 s).

The excerpt loses the whole book's context — its document body size and recurring furniture —
and the full 920-page book was not converted twice for this record.
