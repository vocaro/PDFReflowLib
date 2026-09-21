# Links convert to anchors, and the page images they used to force go away

Measured under [#247](https://github.com/vocaro/PDFReflowLib/issues/247), baseline `14a8f90`,
2026-09-20, macOS 27 / Xcode 27, arm64, release CLI at library defaults.

Every link in a source PDF was discarded. `PageReader` read `page.annotations`, learned nothing
from them beyond "some exist", set `preservePageReference` and raised `annotationsNotConverted`,
whose message said that link and form interactions are not reconstructed. A reader was handed a
picture of the page where an interaction used to be.

## What converts

A link annotation gives a rectangle and either a URI action or a destination in this document.
The rectangle is mapped onto characters with [#235](https://github.com/vocaro/PDFReflowLib/issues/235)'s
geometry — the selection over the annotation's horizontal extent within the line's box is the
linked text, the selection before it gives the offset — so the same hit-testing that marks a
painted underline marks a link, rather than a second geometry path.

External targets are written as they stand, from an allowlist of `http`, `https` and `mailto`.
Everything else is dropped and counted: the bundled `links.pdf` fixture carries a
`javascript:alert('no')` link that must never reach an output, and does not.

An internal target names a page, which only the writer can turn into a file name. That
resolution is [decision 0010](../../doc/decisions/0010-deferred-page-destinations.md).

## Four books, before and after

| Document | MB before | MB after | Images before | Images after | External links | Internal links | Pages still warned |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| arxiv-replay-clocks-2023 | 7.1 | **1.2** | 70 | 59 | 1 | 69 | 0 |
| usda-ars-agresearch-2012-11 | 45.2 | **21.5** | 75 | 57 | 32 | 4 | 2 |
| fed-explained-2021 | 51.2 | **22.7** | 317 | 237 | 13 | 114 | 5 |
| gpo-911-2004 | 14.1 | **13.2** | 101 | 96 | 6 | 99 | 23 |

No book carried a single anchor before; the "before" columns for links are zero throughout.

The size change is the policy narrowing, not the anchors. `preservePageReference` fired for any
annotation at all, so a born-digital report whose only annotations are its own cross-references
had a mandatory page image on every such page. Now only an annotation that did not convert forces
one, which is what the warning always claimed. The arXiv paper loses 11 of its 70 images and 83%
of its bytes; the Fed report loses 80 images and 56%. The 9/11 report keeps most of its images
because 23 of its pages carry annotations that are not links, and each of those pages still says
so — with a message that now states how many links converted and how many annotations did not,
rather than asserting that none did.

## Validation

EPUBCheck 3.3 reports no errors on any of the four, and no warnings on three; the 9/11 report's
one warning is the reading-order note its outline already drew (see
[outline-navigation](../outline-navigation/record.md)). Every emitted `href` is checked by
`tools/check_epubs.py`, which resolves each one against the archive and each fragment against the
target document's ids, and rejects any external reference that is not an anchor in an allowed
scheme — the check an unresolved internal-link token would fail.

478 Swift tests pass, seven new. The corpus lane passes 16 of 18 with no content-contract
failures.

## Not measured

Links on a page that becomes a whole-page image cannot survive and are counted as unconverted,
as the issue expected. Form fields are still not reconstructed. Whether the images this change
removes were carrying anything a reader wanted is a judgement no measurement here makes: the
pages that lost them are pages whose every annotation was a link, and their text reflowed before
and reflows now.
