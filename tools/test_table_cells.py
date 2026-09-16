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

    def test_invalid_table_expectation_is_not_ignored(self):
        self.contract['pages'][0]['tableCells'] = [{'columns': ['a'], 'rows': []}]
        with self.assertRaises(ValueError):
            self.check('<span epub:type="pagebreak" id="page-1"/><p>x</p>')


if __name__ == '__main__':
    unittest.main()
