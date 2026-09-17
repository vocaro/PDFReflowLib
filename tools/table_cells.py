#!/usr/bin/env python3
"""Check row/column cell association of a table emitted as XHTML text against a reviewed transcription.

A `tableCells` expectation carries the same shape as the table transcriptions in
corpus/<case>-review.json: `columns` (header labels in order, spanning headers written as the
joined header path such as "Mine production 2023"), and `rows` with a `label`, `values` (one per
column) and optionally `group` (indentation-only parent labels that must precede the row).

A header cell that spans a label column and an amount column (Fed page 47's "Assets (billions of
dollars)" over each asset's name and its amount) names each spanned column with an object,
`{"header": <header path>, "span": <n>, "column": <1..n>}`: some header cell whose path is
`header` must carry exactly that colspan, and `column` picks one grid column beneath it. A row
whose label sits under such a column instead of the first grid column names it with
`labelColumn` (1-based, into `columns`). An optional `caption` lists the table's caption
paragraphs in order (title, then description); they must equal the paragraphs of the table's
own `<caption>` exactly, so a title emitted as prose before the table, or merged with its
description, fails.

The spine parser expands `<table>` elements on each page into rectangular grids of normalized
cell text, honouring colspan/rowspan. A page passes when some table on that page has a header
column for every expected column, and for every expected row a body row whose label cell starts
with the expected label and whose cells under those columns equal the expected values exactly.
Merged cells, swapped values, missing rows and missing group rows all fail. This checks text
association only; it does not judge table styling or accessibility markup.
"""
import re

HTML = '{http://www.w3.org/1999/xhtml}'


def normalized(text):
    return ' '.join((text or '').split())


def _cell_text(element):
    parts = [element.text or '']
    for child in element:
        parts.append(_cell_text(child))
        parts.append(child.tail or '')
    return ''.join(parts)


def grid_from_table(table):
    """Expand a <table> element into {'cells': rows of cell strings, 'headerRows': n}.

    colspan/rowspan are honoured. Header rows are the leading rows whose every nonempty cell is a
    <th>; a table without any <th> treats its first row as the header.
    """
    rows = [row for section in [table] + list(table) for row in
            ([section] if section.tag == HTML + 'tr' else [r for r in section if r.tag == HTML + 'tr'])]
    grid, header_flags, spans = [], [], []
    pending = {}  # (row, column) -> (text, is_header) carried by a rowspan
    for index, row in enumerate(rows):
        cells = []
        column = 0
        children = [c for c in row if c.tag in (HTML + 'td', HTML + 'th')]
        for cell in children:
            while (index, column) in pending:
                cells.append(pending.pop((index, column)))
                column += 1
            entry = (normalized(_cell_text(cell)), cell.tag == HTML + 'th')
            span = _span(cell.get('colspan'))
            rowspan = _span(cell.get('rowspan'))
            spans.append((index, column, span))
            for offset in range(span):
                for extra in range(1, rowspan):
                    pending[(index + extra, column + offset)] = entry
                cells.append(entry)
                column += 1
        while (index, column) in pending:
            cells.append(pending.pop((index, column)))
            column += 1
        grid.append([text for text, _ in cells])
        header_flags.append(any(text for text, _ in cells) and all(is_header for text, is_header in cells if text))
    width = max((len(row) for row in grid), default=0)
    header_rows = 0
    while header_rows < len(grid) and header_flags[header_rows]:
        header_rows += 1
    if header_rows == 0 and grid:
        header_rows = 1
    caption = table.find(HTML + 'caption')
    paragraphs = []
    if caption is not None:
        blocks = [child for child in caption if child.tag == HTML + 'p']
        paragraphs = [normalized(_cell_text(p)) for p in blocks] if blocks else [normalized(_cell_text(caption))]
    return {'cells': [row + [''] * (width - len(row)) for row in grid], 'headerRows': header_rows,
            # (row, first grid column, colspan) of every cell as written, before expansion.
            'spans': spans, 'caption': [p for p in paragraphs if p]}


def _span(value):
    return int(value) if value and re.fullmatch(r'[1-9]\d*', value) else 1


def _column_key(column):
    return normalized(column) if isinstance(column, str) else (normalized(column['header']), column['span'], column['column'])


def _positive(value):
    return type(value) is int and value >= 1


def validate(expectation):
    if not isinstance(expectation, dict) or not {'columns', 'rows'} <= set(expectation) \
            or not set(expectation) <= {'columns', 'rows', 'title', 'caption'}:
        raise ValueError('Table cells expectation needs columns and rows (optional title and caption)')
    columns = expectation['columns']
    invalid_columns = 'Table columns must be distinct nonempty strings or spanning column objects'
    if not isinstance(columns, list) or not columns:
        raise ValueError(invalid_columns)
    for column in columns:
        if isinstance(column, str):
            if not normalized(column):
                raise ValueError(invalid_columns)
        elif (not isinstance(column, dict) or set(column) != {'header', 'span', 'column'}
              or not isinstance(column['header'], str) or not normalized(column['header'])
              or not _positive(column['span']) or column['span'] < 2
              or not _positive(column['column']) or column['column'] > column['span']):
            raise ValueError('A spanning column needs a header, a span of at least 2 and a column within it')
    if len({_column_key(c) for c in columns}) != len(columns):
        raise ValueError(invalid_columns)
    if not expectation['rows']:
        raise ValueError('Table needs at least one row')
    for row in expectation['rows']:
        if (not isinstance(row, dict) or not {'label', 'values'} <= set(row)
                or not set(row) <= {'label', 'values', 'group', 'note', 'labelColumn'}
                or not isinstance(row['label'], str) or not normalized(row['label'])
                or len(row['values']) != len(columns)
                or any(not isinstance(v, str) for v in row['values'])
                or any(not isinstance(g, str) or not normalized(g) for g in row.get('group', []))
                or ('labelColumn' in row and (not _positive(row['labelColumn']) or row['labelColumn'] > len(columns)))):
            raise ValueError('Each table row needs a nonempty label and one string value per column')
    if 'title' in expectation and (not isinstance(expectation['title'], str) or not normalized(expectation['title'])):
        raise ValueError('Table title must be a nonempty string')
    if 'caption' in expectation and (not isinstance(expectation['caption'], list) or not expectation['caption']
                                     or any(not isinstance(p, str) or not normalized(p) for p in expectation['caption'])):
        raise ValueError('Table caption must be a nonempty list of nonempty paragraph strings')


def _header_columns(table, columns, body_start):
    """Map each expected column (by index) to a grid column. A string label maps to the grid column
    whose header path (distinct header cells from top to bottom, joined by spaces) equals it; a
    spanning column object maps to its `column`-th grid column under a header cell with exactly its
    colspan whose path down to that cell equals its header. One grid column cannot serve two columns."""
    grid = table['cells']

    def path(column, through):
        parts, previous = [], None
        for row in grid[:through + 1]:
            text = row[column]
            if text and text != previous:
                parts.append(text)
            previous = text
        return normalized(' '.join(parts))

    mapping = {}
    for index, label in enumerate(columns):
        if isinstance(label, str):
            wanted = normalized(label)
            candidates = [c for c in range(len(grid[0]) if grid else 0) if path(c, body_start - 1) == wanted]
        else:
            wanted = normalized(label['header'])
            candidates = [start + label['column'] - 1 for row, start, span in table.get('spans', [])
                          if row < body_start and span == label['span'] and grid[row][start]
                          and path(start, row) == wanted]
        for column in candidates:
            if column not in mapping.values():
                mapping[index] = column
                break
    return mapping if len(mapping) == len(columns) else None


def check_table(expectation, table):
    """Return a list of association errors for one table grid (empty when the table matches)."""
    grid, body_start = table['cells'], table['headerRows']
    if not grid or body_start >= len(grid):
        return ['table has no body rows']
    columns = expectation['columns']
    mapping = _header_columns(table, columns, body_start)
    if mapping is None:
        return [f'header columns not found: {columns!r}']
    errors = []
    if 'caption' in expectation:
        wanted = [normalized(p) for p in expectation['caption']]
        if table.get('caption', []) != wanted:
            errors.append(f'caption paragraphs {table.get("caption", [])!r}, expected {wanted!r}')
    used = set()
    for row in expectation['rows']:
        label = normalized(row['label'])
        label_column = mapping[row['labelColumn'] - 1] if 'labelColumn' in row else 0
        candidates = [i for i in range(body_start, len(grid)) if grid[i][label_column].startswith(label) and i not in used]
        if not candidates:
            errors.append(f'missing row {row["label"]!r}')
            continue
        matched = None
        for index in candidates:
            cells = [grid[index][mapping[c]] for c in range(len(columns))]
            if cells == [normalized(v) for v in row['values']]:
                matched = index
                break
        if matched is None:
            index = candidates[0]
            cells = [grid[index][mapping[c]] for c in range(len(columns))]
            errors.append(f'row {row["label"]!r} has cells {cells!r}, expected {row["values"]!r}')
            continue
        used.add(matched)
        for group in row.get('group', []):
            wanted = normalized(group)
            if not any(grid[i][0] == wanted for i in range(body_start, matched)):
                errors.append(f'row {row["label"]!r} is not preceded by group row {group!r}')
    return errors


def check_page(expectation, tables):
    """Errors for a page: empty when any table grid satisfies the expectation."""
    validate(expectation)
    if not tables:
        return ['no table element on the page']
    results = [check_table(expectation, table) for table in tables]
    if any(not r for r in results):
        return []
    return min(results, key=len)
