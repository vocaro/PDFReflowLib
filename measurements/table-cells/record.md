# Table cell association checks

Part of [#27](https://github.com/vocaro/PDFReflowLib/issues/27). The source-region and glyph
checks prove a preserved table image is complete; they cannot say whether cells are associated
with the right rows and columns. Every corpus table is still preserved as an image (#36, #31),
so this record ships the `tableCells` contract type with synthetic evidence only. Converter
`56e70e2`; Python 3.14.6.

## Contract shape

A `tableCells` expectation has the shape of the transcriptions already reviewed in
`corpus/usgs-mcs2025-copper-review.json` (`tableReferences`): `columns` in order (a spanning header
is written as its joined path, for example "Mine production 2023"), `rows` with a `label`, one
string `values` entry per column, an optional `group` list of indentation-only parent labels that
must precede the row, an optional `note`, and an optional `title`. All three USGS transcriptions
validate as expectations (`test_usgs_review_transcriptions_validate_as_expectations`).

## Method

`tools/check_corpus_content.py` now collects every `<table>` on a page into a grid: rows of
normalized cell text with `colspan`/`rowspan` expanded, and the number of leading header rows (rows
whose every nonempty cell is a `<th>`; a table without `<th>` has one header row).
`tools/table_cells.py` passes a page when some table on it has, for each expected column, a distinct
grid column whose header path (distinct header cells top to bottom, joined by spaces) equals the
label, and for each expected row a distinct body row whose first cell starts with the label and
whose cells under the mapped columns equal the expected values exactly. Each expected `group` label
must appear as the first cell of an earlier body row. Prose that merely contains the table's words
does not pass: the check needs a `<table>` element on the source page.

## Controls (`tools/test_table_cells.py`)

Positive: a spanning two-level header table (USGS page-2 subset), a grouped one-header table
(USGS page-1 subset with `<sup>` markers), and a page carrying both tables. Negative controls:
swapped values inside a row, two adjacent cells exchanged, a missing row, two value cells merged
into one `colspan`, two header cells merged, a missing group row, a changed label, an empty
table, a table on another page, the table rendered as a prose paragraph, one body row claimed by
two expected rows, and invalid expectations (missing keys, duplicate or empty columns, wrong value
counts, non-string values, empty group labels, unknown keys, empty title). 8 tests, 1 contract
check counted per expectation.

## Corpus status

Converted EPUBs for FAA, Wallace, Our Flag, USGS and The Fed Explained (converter `56e70e2`)
contain no `<table>` element (0 in every spine file), so no `tableCells` check can be added to
`corpus/regressions.json` yet. The Fed report's recurring tagged tables (pages 46, 82–83, 120–121)
are preserved as images. When #36 or a table writer lands, the USGS transcriptions and the Our Flag
page-27 `tableReference` are ready to become contracts; until then the USGS Salient Statistics table
is guarded by the 36 DPI region check and the full-resolution glyph check.

## What the check proves and does not prove

It proves row/column association of text cells against a reviewed transcription and rejects merged
or shifted cells. It does not judge table semantics markup (`scope`, captions, summaries), cell
styling, or tables emitted as preformatted text or lists; those layouts fail the check by design.
