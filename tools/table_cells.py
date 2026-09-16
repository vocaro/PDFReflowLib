#!/usr/bin/env python3
"""Check row/column cell association of a table emitted as XHTML text against a reviewed transcription.

A `tableCells` expectation carries the same shape as the table transcriptions in
corpus/<case>-review.json: `columns` (header labels in order, spanning headers written as the
joined header path such as "Mine production 2023"), and `rows` with a `label`, `values` (one per
column) and optionally `group` (indentation-only parent labels that must precede the row).

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
    grid, header_flags = [], []
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
    return {'cells': [row + [''] * (width - len(row)) for row in grid], 'headerRows': header_rows}


def _span(value):
    return int(value) if value and re.fullmatch(r'[1-9]\d*', value) else 1


def validate(expectation):
    if not isinstance(expectation, dict) or not {'columns', 'rows'} <= set(expectation) \
            or not set(expectation) <= {'columns', 'rows', 'title'}:
        raise ValueError('Table cells expectation needs columns and rows (optional title)')
    columns = expectation['columns']
    if not columns or any(not isinstance(c, str) or not normalized(c) for c in columns) \
            or len({normalized(c) for c in columns}) != len(columns):
        raise ValueError('Table columns must be distinct nonempty strings')
    if not expectation['rows']:
        raise ValueError('Table needs at least one row')
    for row in expectation['rows']:
        if (not isinstance(row, dict) or not {'label', 'values'} <= set(row)
                or not set(row) <= {'label', 'values', 'group', 'note'}
                or not isinstance(row['label'], str) or not normalized(row['label'])
                or len(row['values']) != len(columns)
                or any(not isinstance(v, str) for v in row['values'])
                or any(not isinstance(g, str) or not normalized(g) for g in row.get('group', []))):
            raise ValueError('Each table row needs a nonempty label and one string value per column')
    if 'title' in expectation and (not isinstance(expectation['title'], str) or not normalized(expectation['title'])):
        raise ValueError('Table title must be a nonempty string')


def _header_columns(grid, columns, body_start):
    """Map each expected column label to the grid column whose header path (distinct header cells
    from top to bottom, joined by spaces) equals it; one grid column cannot serve two labels."""
    mapping = {}
    for label in columns:
        wanted = normalized(label)
        for column in range(len(grid[0]) if grid else 0):
            path, previous = [], None
            for row in grid[:body_start]:
                text = row[column]
                if text and text != previous:
                    path.append(text)
                previous = text
            if normalized(' '.join(path)) == wanted and column not in mapping.values():
                mapping[label] = column
                break
    return mapping if len(mapping) == len(columns) else None


def check_table(expectation, table):
    """Return a list of association errors for one table grid (empty when the table matches)."""
    grid, body_start = table['cells'], table['headerRows']
    if not grid or body_start >= len(grid):
        return ['table has no body rows']
    columns = expectation['columns']
    mapping = _header_columns(grid, columns, body_start)
    if mapping is None:
        return [f'header columns not found: {columns!r}']
    errors = []
    used = set()
    for row in expectation['rows']:
        label = normalized(row['label'])
        candidates = [i for i in range(body_start, len(grid)) if grid[i][0].startswith(label) and i not in used]
        if not candidates:
            errors.append(f'missing row {row["label"]!r}')
            continue
        matched = None
        for index in candidates:
            cells = [grid[index][mapping[c]] for c in columns]
            if cells == [normalized(v) for v in row['values']]:
                matched = index
                break
        if matched is None:
            index = candidates[0]
            cells = [grid[index][mapping[c]] for c in columns]
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
