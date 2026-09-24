# UCL Hebrew Shakespeare corpus baseline (#44)

Tier: deterministic Apple PDF stack, macOS 27.0 (26A428) arm64, Xcode 27.0
(27A266a), EPUBCheck 5.3.0. Clean repository commit
`f4acc001de305868fdbbf691f731b57d021b6dcf`; release CLI SHA-256
`eff2cdf0df2909bde4112c3636994feab2188f21788424c672031c5260bcd7f0`.
The conversion used `--language he --no-ocr`, rather than the English defaults.

## Source and rights

*Lily Kahn, The First Hebrew Shakespeare Translations: A Bilingual Edition and
Commentary* (UCL Press, 2017), 553 physical PDF pages, 13,421,843 bytes, SHA-256
`8c28b79157cdbf57f4a3e9b65b2ecc1bb02e9e1597a7574e9a9cf2fb53ed6393`.
The unmodified source is the [direct UCL Discovery PDF](https://discovery.ucl.ac.uk/id/eprint/1563534/1/The-First-Hebrew-Shakespeare-Translations.pdf)
linked from its [publisher repository record](https://discovery.ucl.ac.uk/id/eprint/1563534/).
The PDF is untagged and its metadata names Lily Kahn. Its rendered physical page 6 and the
repository record both state CC BY 4.0 for the book, including the images. The source's
requested attribution is: Lily Kahn, *The First Hebrew Shakespeare Translations*. London,
UCL Press, 2017. DOI 10.14324/111.9781911307976. The PDF stays outside the library's MIT
package, in the ignored local corpus cache.

## Full baseline

Built with `swift build -c release --product pdf-reflow`, then ran:

```sh
/usr/bin/time -l .build/release/pdf-reflow \
  corpus/cache/The-First-Hebrew-Shakespeare-Translations.pdf \
  /private/tmp/hebrew-shakespeare-44-baseline.epub --language he --no-ocr
```

The clean rerun exited 0 in 25.30 seconds. Kernel peak converter RSS was 112,115,712 bytes
(106.9 MiB), leaving headroom under a proposed 256 MiB corpus ceiling; this is not a
mobile-device budget. All 1,642 progress percentages were monotonic, from 0 to 100.
The EPUB is 7,377,480 bytes, with 533 ZIP entries (9,436,249 uncompressed bytes), 41
chapter XHTML files, and `<dc:language>he</dc:language>`. It has all 553 page markers in
order, 547 reflowed pages, no recognized pages, and 487 images. EPUBCheck 5.3.0 returned
0 errors and 0 warnings.

The report has 532 `furnitureRemoved`, 481 `imageRegion`, 64 `uncertainHyphen`, 16
`annotationsNotConverted`, 6 `pageImageFallback`, 4 `emptyPage`, and 1
`structureFallback` warnings. The image-only pages are physical 1, 2, 4, 8, 10 and 553;
pages 2, 4, 8 and 10 are also reported empty. These counts describe the baseline; they
do not certify the text's accuracy.

An earlier run with the same release binary, before the shared worktree settled, also exited
0 and had the same page, image and warning counts and 19 passing content checks. It took
38.08 seconds, peaked at 120,242,176 bytes RSS and produced 7,377,478 EPUB bytes. The
clean rerun above is the admission receipt; the difference in compressed size is not used
as a fidelity claim.

## Source review and content contract

Poppler renders of physical pages 5, 6, 13, 81, 150, 250 and 550 were read beside the
page-aligned EPUB text. Page 6 supplies the rights evidence; the other six form the review
set in `corpus/ucl-hebrew-shakespeare-2017-review.json`.

- Page 5 has the title, subtitle, byline and UCL Press logo. The EPUB retains the words and
  an image, although it splits the large title into two headings.
- Page 13 opens the English introduction. `Introduction` is a heading and the section line
  and Haskalah prose reflow, though the section line itself is a paragraph.
- Page 81 prints English prose in the left column and Hebrew in the right. The EPUB retains
  both as selectable paragraphs and marks the Hebrew paragraph `dir="rtl"`; it serializes
  the English column before the Hebrew rather than maintaining their parallel alignment.
- Page 150 prints vocalized Hebrew verse beside an English translation and numbered notes
  at the foot. The EPUB retains both scripts, the vowel points and note 46 after the verse.
  Several Hebrew verse lines become heading elements, repeated fragments and misplaced
  role or note bits, so line pairing and exact note attachment remain unqualified.
- Page 250 prints bilingual dramatic dialogue with speaker names and stage directions.
  The trumpet direction and dialogue survive as text, but some speaker labels separate
  from their utterances; dramatic reading order remains unqualified.
- Page 550 prints bibliography entries with embedded Hebrew. The selected Markel,
  Needler and Salkinson entries remain in source order; typography and punctuation are
  not qualified.

`proposed-entries.json` preserves the reviewed manifest and regression entry proposal.
The case was admitted to `corpus/manifest.json` and `corpus/regressions.json` with
`--language he --no-ocr` and a 256 MiB peak RSS ceiling. The targeted gate passed on
2026-09-24: 28.21 seconds, 111,067,136 bytes peak RSS, EPUBCheck exit 0, and all 19
content checks passed on the six reviewed pages. This is the targeted corpus lane, not
the full 22-case run. Before admission, the contract was run directly through
`tools/check_corpus_content.py`'s page
reader and assessor against this EPUB and report: **19 content checks pass on six pages**,
all 553 source markers are present, and there are no content errors. These checks protect
only verified text and image presence. The remaining pages and the parallel bilingual
layout, verse hierarchy, speaker pairing and precise footnote links need separate fidelity
work. No source PDF, raster or EPUB is committed.
