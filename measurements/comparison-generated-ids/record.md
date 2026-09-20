# What generated identifiers cost the conversion comparator

Work on [#92](https://github.com/vocaro/PDFReflowLib/issues/92), on top of `6ad52fb`,
2026-09-19, macOS 27 / Xcode 27, arm64. `tools/compare_conversion_runs.py` compared each page's
parsed record verbatim, and two of the fields in that record are generated identifiers that
renumber book-wide: `read_pages` keys a page's paragraphs by a book-wide ordinal, and
`EPUBWriter` names image assets `images/image-N.ext` in book-wide first-use order
(`Sources/PDFReflowLib/EPUBWriter.swift:70`). One edit early in a book therefore renumbered
every later page, and the tool reported them all. This records what that cost on two real books
and what the same edits report now.

## Method

Both books were converted once by the release build of `6ad52fb`
(`c9fe35afcd3077974d529a23cd9674dde62d79c9c88085673ae54218acb0b235`) with
`--package-identifier urn:uuid:… --modification-date 2026-01-01T00:00:00Z`. The candidate is
that EPUB with one edit applied to its spine markup, so the two runs differ in exactly the one
thing named and nothing else — a converter change would confound the count with its own effects.
Two edits were used: removing one whole `<p>` from a named page, and removing one `<figure>` and
its image asset and renumbering the assets after it the way the writer would. Both algorithms
were then run over the same pair in one process. Each converted book was deleted as soon as its
numbers were recorded.

## Removing one paragraph

| Book | Pages | Edited page | Pages reported before | After | Summarized as renumbering |
| --- | ---: | ---: | ---: | ---: | ---: |
| census-rrs2002-01 | 20 | 5 | 15 | 1 | 14 |
| fed-explained-2021 | 135 | 8 | 117 | 1 | 116 |

The Fed number is the one [#92](https://github.com/vocaro/PDFReflowLib/issues/92) reports from
the branch's build as 123; 117 is what `main`'s converter lays out for the same edit. The pages
that are no longer reported are not dropped: they appear in `idOnlyShifts`, which says 116 pages
differ only in `paragraphIDs`, and `--detail` lists them.

## Removing one image asset

The Fed book has 315 image assets. Removing `image-5.png` (a region on source page 4) and
renumbering the 310 after it:

| | Pages reported | Image assets reported |
| --- | ---: | ---: |
| Before | 132 | 311 |
| After | 1 (page 4) | 1 (`EPUB/images/image-5.png`) |

The 310 assets whose bytes are unchanged and whose names moved are counted in `imageRenames`.
Matching assets by SHA-256 rather than by name is also why the page that lost the image is now
named at all: before, a changed image named no page, because a page's record held asset names
and those are what the comparison saw.

## What is still a difference

Normalizing an ordinal away must not normalize away what the ordinal was evidence of. A
paragraph that straddles a page marker carries one ordinal on both pages, so each page now
records, per paragraph, whether that paragraph also appears on the previous or the next page.
`tools/test_conversion_comparison.py` joins the last paragraph of census page 5 to the first of
page 6 across the marker, leaving both pages exactly the text and images they had, and requires
both pages to be reported with `paragraphSpans` as the only differing field. A re-encoded image,
a moved image, a swapped pair of images and a changed word on a later page are covered by the
same suite.

## Reproduce

```sh
swift build -c release
pdf-reflow corpus/cache/the-fed-explained.pdf fed.epub \
  --package-identifier urn:uuid:00000000-0000-4000-8000-000000000002 \
  --modification-date 2026-01-01T00:00:00Z
# Remove one <p> from the markup of page 8 in the spine document that holds it, then:
python3 tools/compare_conversion_runs.py --baseline BEFORE --candidate AFTER \
  --output result.json --detail
```

`BEFORE` and `AFTER` are evaluation directories as `tools/evaluate_real_document.py` writes
them. The unedited comparison for the "before" column is `6ad52fb`'s
`tools/compare_conversion_runs.py`.
