import json
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

from check_corpus_content import ROOT, assess, read_pages
import table_cells

XHTML = 'xmlns="http://www.w3.org/1999/xhtml"'

# A subset of the USGS copper page-2 transcription (corpus/usgs-mcs2025-copper-review.json) with
# spanning headers, and the page-1 Salient Statistics layout with indentation-only group rows.
WORLD = f'''<table {XHTML}><thead>
<tr><th rowspan="2"></th><th colspan="2">Mine production</th><th colspan="2">Refinery production</th><th rowspan="2">Reserves (note 6)</th></tr>
<tr><th>2023</th><th>2024e</th><th>2023</th><th>2024e</th></tr></thead><tbody>
<tr><td>United States</td><td>1,130</td><td>1,100</td><td>882</td><td>890</td><td>47,000</td></tr>
<tr><td>Australia</td><td>778</td><td>800</td><td>442</td><td>460</td><td>(7)100,000</td></tr>
<tr><td>Chile</td><td>5,250</td><td>5,300</td><td>2,080</td><td>1,900</td><td>190,000</td></tr>
<tr><td>Germany</td><td>—</td><td>—</td><td>609</td><td>630</td><td>—</td></tr>
</tbody></table>'''

SALIENT = f'''<table {XHTML}>
<tr><th></th><th>2020</th><th>2021</th><th>2022</th><th>2023</th><th>2024<sup>e</sup></th></tr>
<tr><td>Production</td><td></td><td></td><td></td><td></td><td></td></tr>
<tr><td>Mine, recoverable</td><td>1,200</td><td>1,230</td><td>1,230</td><td>1,130</td><td>1,100</td></tr>
<tr><td>Refinery</td><td></td><td></td><td></td><td></td><td></td></tr>
<tr><td>Primary (from ore)</td><td>872</td><td>922</td><td>930</td><td>843</td><td>850</td></tr>
<tr><td>Copper recovered from old (post-consumer) scrap<sup>1</sup></td><td>161</td><td>169</td><td>152</td><td><sup>e</sup>150</td><td>150</td></tr>
</table>'''


def world_expectation():
    return {'title': 'World Mine and Refinery Production and Reserves',
            'columns': ['Mine production 2023', 'Mine production 2024e', 'Refinery production 2023',
                        'Refinery production 2024e', 'Reserves (note 6)'],
            'rows': [{'label': 'United States', 'values': ['1,130', '1,100', '882', '890', '47,000']},
                     {'label': 'Australia', 'values': ['778', '800', '442', '460', '(7)100,000']},
                     {'label': 'Chile', 'values': ['5,250', '5,300', '2,080', '1,900', '190,000']},
                     {'label': 'Germany', 'values': ['—', '—', '609', '630', '—']}]}


def salient_expectation():
    return {'columns': ['2020', '2021', '2022', '2023', '2024e'],
            'rows': [{'label': 'Mine, recoverable', 'group': ['Production'], 'values': ['1,200', '1,230', '1,230', '1,130', '1,100']},
                     {'label': 'Primary (from ore)', 'group': ['Production', 'Refinery'], 'values': ['872', '922', '930', '843', '850']},
                     {'label': 'Copper recovered from old (post-consumer) scrap', 'note': '1', 'group': [],
                      'values': ['161', '169', '152', 'e150', '150']}]}


# Fed page 47's Table A as the converter emits it (#114): each header spans a label column and an
# amount column, one body row is empty on the asset side, and the caption holds title and description.
TABLE_A = (f'<table {XHTML}><caption><p>Table A. Simplified view of the Federal Reserve balance sheet, as of June 24, 2020</p>'
           '<p>The Federal Reserve publishes data weekly regarding its balance sheet.</p></caption>'
           '<thead><tr><th colspan="2">Assets (billions of dollars)</th><th colspan="2">Liabilities (billions of dollars)</th></tr></thead><tbody>'
           '<tr><td>Treasury securities held outright</td><td>4,197</td><td>Deposits of depository institutions</td><td>2,938</td></tr>'
           '<tr><td>Agency debt and mortgage-backed securities holdings</td><td>1,946</td><td>Federal Reserve notes in circulation</td><td>1,915</td></tr>'
           '<tr><td></td><td></td><td>U.S. Treasury, General Account</td><td>1,587</td></tr>'
           '<tr><td>Other assets</td><td>939</td><td>Capital and other liabilities</td><td>642</td></tr>'
           '<tr><td>Total</td><td>7,082</td><td>Total</td><td>7,082</td></tr></tbody></table>')
TITLE = 'Table A. Simplified view of the Federal Reserve balance sheet, as of June 24, 2020'
DESCRIPTION = 'The Federal Reserve publishes data weekly regarding its balance sheet.'


def table_a_expectation():
    def spanning(header, column):
        return {'header': header, 'span': 2, 'column': column}
    assets, liabilities = 'Assets (billions of dollars)', 'Liabilities (billions of dollars)'
    return {'caption': [TITLE, DESCRIPTION],
            'columns': [spanning(assets, 1), spanning(assets, 2), spanning(liabilities, 1), spanning(liabilities, 2)],
            'rows': [{'label': 'Treasury securities held outright',
                      'values': ['Treasury securities held outright', '4,197', 'Deposits of depository institutions', '2,938']},
                     {'label': 'Agency debt and mortgage-backed securities holdings',
                      'values': ['Agency debt and mortgage-backed securities holdings', '1,946', 'Federal Reserve notes in circulation', '1,915']},
                     {'label': 'U.S. Treasury, General Account', 'labelColumn': 3,
                      'values': ['', '', 'U.S. Treasury, General Account', '1,587']},
                     {'label': 'Other assets', 'values': ['Other assets', '939', 'Capital and other liabilities', '642']},
                     {'label': 'Total', 'values': ['Total', '7,082', 'Total', '7,082']}]}


def grids(*tables):
    return [table_cells.grid_from_table(ET.fromstring(table)) for table in tables]


class TableCellTests(unittest.TestCase):
    def test_review_shaped_transcriptions_match_spanning_and_grouped_tables(self):
        self.assertEqual(table_cells.check_page(world_expectation(), grids(WORLD)), [])
        self.assertEqual(table_cells.check_page(salient_expectation(), grids(SALIENT)), [])
        # Any table on the page may satisfy the expectation; the other table's failure is not reported.
        self.assertEqual(table_cells.check_page(salient_expectation(), grids(WORLD, SALIENT)), [])

    def test_grid_expands_spans_and_marks_header_rows(self):
        grid = grids(WORLD)[0]
        self.assertEqual(grid['headerRows'], 2)
        self.assertEqual(grid['cells'][0], ['', 'Mine production', 'Mine production', 'Refinery production', 'Refinery production', 'Reserves (note 6)'])
        self.assertEqual(grid['cells'][1], ['', '2023', '2024e', '2023', '2024e', 'Reserves (note 6)'])
        self.assertEqual(grids(SALIENT)[0]['headerRows'], 1)
        headerless = grids(WORLD.replace('<th>', '<td>').replace('<th ', '<td ').replace('</th>', '</td>'))[0]
        self.assertEqual(headerless['headerRows'], 1)

    def test_swapped_cells_missing_row_merged_columns_and_missing_group_fail(self):
        swapped = world_expectation()
        swapped['rows'][2]['values'] = ['5,300', '5,250', '2,080', '1,900', '190,000']
        self.assertTrue(table_cells.check_page(swapped, grids(WORLD)))
        shifted = WORLD.replace('<td>882</td><td>890</td>', '<td>890</td><td>882</td>')
        self.assertTrue(table_cells.check_page(world_expectation(), grids(shifted)))
        missing = WORLD.replace('<tr><td>Chile</td><td>5,250</td><td>5,300</td><td>2,080</td><td>1,900</td><td>190,000</td></tr>', '')
        self.assertEqual(table_cells.check_page(world_expectation(), grids(missing)), ["missing row 'Chile'"])
        merged = WORLD.replace('<td>1,130</td><td>1,100</td>', '<td colspan="2">1,130 1,100</td>')
        self.assertTrue(table_cells.check_page(world_expectation(), grids(merged)))
        merged_header = WORLD.replace('<th>2023</th><th>2024e</th><th>2023</th>', '<th colspan="2">2023 2024e</th><th>2023</th>')
        self.assertTrue(table_cells.check_page(world_expectation(), grids(merged_header)))
        no_group = SALIENT.replace('<tr><td>Refinery</td><td></td><td></td><td></td><td></td><td></td></tr>', '')
        errors = table_cells.check_page(salient_expectation(), grids(no_group))
        self.assertEqual(errors, ["row 'Primary (from ore)' is not preceded by group row 'Refinery'"])
        wrong_label = SALIENT.replace('Mine, recoverable', 'Mine, recovered')
        self.assertTrue(table_cells.check_page(salient_expectation(), grids(wrong_label)))
        self.assertEqual(table_cells.check_page(world_expectation(), []), ['no table element on the page'])
        self.assertTrue(table_cells.check_page(world_expectation(), grids(f'<table {XHTML}><tr><th>only</th></tr></table>')))

    def test_a_row_cannot_satisfy_two_expected_rows(self):
        duplicated = world_expectation()
        duplicated['rows'].append(dict(duplicated['rows'][0]))
        self.assertTrue(table_cells.check_page(duplicated, grids(WORLD)))

    def test_invalid_expectations_are_rejected(self):
        for invalid in [{}, {'columns': [], 'rows': []}, {'columns': ['a'], 'rows': []},
                        {'columns': ['a', 'a'], 'rows': [{'label': 'x', 'values': ['1', '2']}]},
                        {'columns': ['a'], 'rows': [{'label': 'x', 'values': ['1', '2']}]},
                        {'columns': ['a'], 'rows': [{'label': '', 'values': ['1']}]},
                        {'columns': ['a'], 'rows': [{'label': 'x', 'values': [1]}]},
                        {'columns': ['a'], 'rows': [{'label': 'x', 'values': ['1'], 'group': ['']}]},
                        {'columns': ['a'], 'rows': [{'label': 'x', 'values': ['1'], 'extra': 1}]},
                        {'columns': ['a'], 'rows': [{'label': 'x', 'values': ['1']}], 'title': ''},
                        ['a']]:
            with self.assertRaises(ValueError):
                table_cells.validate(invalid)

    def test_headers_spanning_a_label_and_an_amount_column_match_table_a(self):
        self.assertEqual(table_cells.check_page(table_a_expectation(), grids(TABLE_A)), [])
        grid = grids(TABLE_A)[0]
        self.assertEqual(grid['caption'], [TITLE, DESCRIPTION])
        self.assertEqual(grid['spans'][:2], [(0, 0, 2), (0, 2, 2)])
        # The string form cannot address the amount column: one header path names two grid columns.
        with self.assertRaises(ValueError):
            table_cells.validate({'columns': ['Assets (billions of dollars)', 'Assets (billions of dollars)'],
                                  'rows': [{'label': 'Total', 'values': ['Total', '7,082']}]})

    def test_spanning_header_negative_controls(self):
        failing = {
            # Headers over the label columns only, with empty header cells over the amounts.
            'unspanned': TABLE_A.replace('<th colspan="2">Assets (billions of dollars)</th>', '<th>Assets (billions of dollars)</th><th></th>')
                                .replace('<th colspan="2">Liabilities (billions of dollars)</th>', '<th>Liabilities (billions of dollars)</th><th></th>'),
            # A header spanning three columns is not the source's two.
            'wider': TABLE_A.replace('<th colspan="2">Assets (billions of dollars)</th><th colspan="2">',
                                     '<th colspan="3">Assets (billions of dollars)</th><th colspan="1">'),
            # Amounts exchanged between the asset and liability sides.
            'swapped': TABLE_A.replace('<td>4,197</td><td>Deposits of depository institutions</td><td>2,938</td>',
                                       '<td>2,938</td><td>Deposits of depository institutions</td><td>4,197</td>'),
            # A label merged with its amount (the prose reading the contract replaces).
            'merged': TABLE_A.replace('<td>Other assets</td><td>939</td>', '<td colspan="2">Other assets 939</td>'),
            # The Treasury account on the asset side.
            'wrong side': TABLE_A.replace('<td></td><td></td><td>U.S. Treasury, General Account</td><td>1,587</td>',
                                          '<td>U.S. Treasury, General Account</td><td>1,587</td><td></td><td></td>'),
            'missing row': TABLE_A.replace('<tr><td>Total</td><td>7,082</td><td>Total</td><td>7,082</td></tr>', ''),
        }
        for name, table in failing.items():
            self.assertNotEqual(table, TABLE_A, name)
            self.assertTrue(table_cells.check_page(table_a_expectation(), grids(table)), name)

    def test_caption_paragraphs_must_be_the_tables_own_in_order(self):
        body = TABLE_A[TABLE_A.index('</caption>') + len('</caption>'):]
        opening = f'<table {XHTML}>'
        failing = {
            'no caption': opening + body,
            'merged': opening + f'<caption><p>{TITLE} {DESCRIPTION}</p></caption>' + body,
            'title only': opening + f'<caption><p>{TITLE}</p></caption>' + body,
            'reversed': opening + f'<caption><p>{DESCRIPTION}</p><p>{TITLE}</p></caption>' + body,
        }
        for name, table in failing.items():
            errors = table_cells.check_page(table_a_expectation(), grids(table))
            self.assertTrue(errors and 'caption' in errors[0], (name, errors))
        # Without a caption expectation the same table passes; a caption of bare text is one paragraph.
        uncaptioned = table_a_expectation(); del uncaptioned['caption']
        self.assertEqual(table_cells.check_page(uncaptioned, grids(opening + body)), [])
        self.assertEqual(grids(opening + f'<caption>{TITLE}</caption>' + body)[0]['caption'], [TITLE])

    def test_invalid_spanning_and_caption_expectations_are_rejected(self):
        def with_column(column):
            return {'columns': [column], 'rows': [{'label': 'x', 'values': ['1']}]}
        for column in [{'header': 'a', 'span': 1, 'column': 1}, {'header': 'a', 'span': 2, 'column': 0},
                       {'header': 'a', 'span': 2, 'column': 3}, {'header': 'a', 'span': True, 'column': 1},
                       {'header': 'a', 'span': 2.0, 'column': 1}, {'header': '', 'span': 2, 'column': 1},
                       {'header': 'a', 'span': 2}, {'header': 'a', 'span': 2, 'column': 1, 'extra': 1}, 3]:
            with self.assertRaises(ValueError, msg=column):
                table_cells.validate(with_column(column))
        duplicated = {'header': 'a', 'span': 2, 'column': 1}
        with self.assertRaises(ValueError):
            table_cells.validate({'columns': [duplicated, dict(duplicated)], 'rows': [{'label': 'x', 'values': ['1', '2']}]})
        for label_column in [0, 2, True, '1']:
            with self.assertRaises(ValueError, msg=label_column):
                table_cells.validate({'columns': ['a'], 'rows': [{'label': 'x', 'values': ['1'], 'labelColumn': label_column}]})
        for caption in [[], [''], 'title', [1]]:
            with self.assertRaises(ValueError, msg=caption):
                table_cells.validate({'columns': ['a'], 'rows': [{'label': 'x', 'values': ['1']}], 'caption': caption})
        table_cells.validate(table_a_expectation())

    def test_usgs_review_transcriptions_validate_as_expectations(self):
        review = json.loads((ROOT / 'corpus/usgs-mcs2025-copper-review.json').read_text())
        for table in review['tableReferences']:
            table_cells.validate({'columns': table['columns'], 'rows': table['rows'], 'title': table['title']})


class TableContractTests(unittest.TestCase):
    def setUp(self):
        self.case = {'id': 'fixture', 'sha256': 'source', 'bytes': 1, 'pages': 1}
        self.contract = {'sourceSHA256': 'source', 'pages': [{'page': 1, 'tableCells': [world_expectation()]}]}

    def epub(self, body):
        directory = tempfile.TemporaryDirectory(); self.addCleanup(directory.cleanup)
        path = Path(directory.name) / 'book.epub'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr('EPUB/package.opf', '<package xmlns="http://www.idpf.org/2007/opf"><manifest><item id="a" href="a.xhtml"/></manifest><spine><itemref idref="a"/></spine></package>')
            archive.writestr('EPUB/a.xhtml', f'<html {XHTML} xmlns:epub="http://www.idpf.org/2007/ops"><body>{body}</body></html>')
        return path

    def check(self, body):
        pages, markers = read_pages(self.epub(body))
        return assess(self.case, self.contract, {'case': self.case, 'runPassed': True, 'conversionExitCode': 0},
                      {'pageCount': self.case['pages']}, pages, markers)

    def test_table_on_the_page_passes_and_counts_one_check(self):
        result = self.check('<span epub:type="pagebreak" id="page-1"/><p>intro</p>' + WORLD.replace(f' {XHTML}', ''))
        self.assertTrue(result['passed'], result['errors'])
        self.assertEqual(result['contentChecks'], 1)

    def test_table_as_prose_missing_or_on_another_page_fails(self):
        prose = '<span epub:type="pagebreak" id="page-1"/><p>United States 1,130 1,100 882 890 47,000</p>'
        self.assertFalse(self.check(prose)['passed'])
        self.case['pages'] = 2
        self.contract['pages'][0]['page'] = 2
        wrong_page = ('<span epub:type="pagebreak" id="page-1"/>' + WORLD.replace(f' {XHTML}', '')
                      + '<span epub:type="pagebreak" id="page-2"/><p>later</p>')
        result = self.check(wrong_page)
        self.assertFalse(result['passed'])
        self.assertIn('no table element on the page', result['errors'][0])

    def test_caption_paragraphs_are_page_paragraphs_but_not_headings(self):
        self.contract['pages'][0]['tableCells'] = [table_a_expectation()]
        self.contract['pages'][0]['paragraphs'] = [DESCRIPTION]
        result = self.check('<span epub:type="pagebreak" id="page-1"/>' + TABLE_A.replace(f' {XHTML}', ''))
        self.assertTrue(result['passed'], result['errors'])
        pages, _ = read_pages(self.epub('<span epub:type="pagebreak" id="page-1"/>' + TABLE_A.replace(f' {XHTML}', '')))
        self.assertEqual(pages[1]['paragraphs'][:2], [TITLE, DESCRIPTION])
        self.assertEqual(pages[1]['headings'], [])
        # Caption and header text are separate words.
        self.assertIn('balance sheet. Assets (billions of dollars)', pages[1]['text'])
        # The title as a paragraph before an uncaptioned table fails the caption check.
        prose = ('<span epub:type="pagebreak" id="page-1"/>' + f'<p>{TITLE}</p><p>{DESCRIPTION}</p>'
                 + TABLE_A.replace(f' {XHTML}', '').replace(TABLE_A[TABLE_A.index('<caption>'):TABLE_A.index('</caption>') + 10], ''))
        result = self.check(prose)
        self.assertFalse(result['passed'])
        self.assertIn('caption paragraphs', result['errors'][0])

    def test_invalid_table_expectation_is_not_ignored(self):
        self.contract['pages'][0]['tableCells'] = [{'columns': ['a'], 'rows': []}]
        with self.assertRaises(ValueError):
            self.check('<span epub:type="pagebreak" id="page-1"/><p>x</p>')


if __name__ == '__main__':
    unittest.main()
