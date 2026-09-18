import contextlib
import io
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest import mock

import check_corpus_content
from check_corpus_content import CHECK_TYPES, EXPECTATION_KEYS, ROOT, assess, count_checks
import update_doc_counts as counts


def synthetic_regressions():
    """Every counted expectation kind once or more, in the shapes `assess` accepts."""
    first = {
        'page': 1,
        'text': ['alpha', 'beta'], 'orderedText': ['alpha', 'beta', 'gamma'],
        'absentText': ['zeta'], 'headings': ['Alpha'], 'absentHeadings': ['7'],
        'paragraphs': ['alpha'], 'listItems': ['one'], 'preformattedLines': [['a b', 'c d']],
        'lists': [{'kind': 'ol', 'start': 2, 'items': ['one']}], 'preformattedBlocks': ['1) 5'],
        'notes': ['note'], 'distinctParagraphs': [{'first': 'alpha', 'second': 'beta'}],
        'noteLinks': [{'marker': '1', 'before': 'alpha', 'note': 'note'}],
        'continuedParagraphs': [{'end': 'end', 'next': 'next'}],
        'continuedListItems': [{'end': 'end', 'next': 'next'}],
        'separateParagraphs': [{'end': 'end', 'next': 'next'}],
        'scripts': [{'tag': 'sup', 'text': '2', 'before': 'x', 'after': 'y'}],
        'minimumImages': 1, 'maximumImages': 3,
        'warningCodesAnyOf': ['ocrUsed'], 'absentWarningCodes': ['lowConfidence'],
    }
    second = {'page': 2, 'text': ['delta'], 'maximumImages': 0}
    return [
        {'id': 'one', 'sourceSHA256': 'a', 'pages': [first, second]},
        {'id': 'two', 'sourceSHA256': 'b', 'pages': [{'page': 1, 'headings': ['A', 'B']}]},
        {'id': 'empty', 'sourceSHA256': 'c', 'pages': []},
    ]


def assessed_checks(contract, pages):
    case = {'id': contract['id'], 'sha256': contract['sourceSHA256'], 'bytes': 1, 'pages': pages}
    result = {'case': dict(case), 'runPassed': True, 'conversionExitCode': 0}
    report = {'pageCount': pages, 'warnings': []}
    content = {n: {'text': '', 'images': []} for n in range(1, pages + 1)}
    return assess(case, contract, result, report, content, list(range(1, pages + 1)))['contentChecks']


class ContractCountTests(unittest.TestCase):
    def test_counts_match_what_assess_counts(self):
        contracts = synthetic_regressions()
        totals = count_checks(contracts)
        self.assertEqual(totals['documents'], 2)
        self.assertEqual(totals['pages'], 3)
        by_assess = sum(assessed_checks(c, 3) for c in contracts if c['pages'])
        self.assertEqual(totals['checks'], by_assess)
        self.assertEqual(totals['checks'], 28)
        self.assertEqual(totals['byType']['image-presence'], 3)
        self.assertEqual(totals['byType']['heading'], 3)
        self.assertEqual(totals['byType']['source-region'], 0)

    def test_each_type_matches_assess_alone(self):
        for item in synthetic_regressions()[0]['pages'][:1]:
            for key in set(item) - {'page'}:
                contract = {'id': 'one', 'sourceSHA256': 'a', 'pages': [{'page': 1, key: item[key]}]}
                with self.subTest(key=key):
                    self.assertEqual(count_checks([contract])['checks'], assessed_checks(contract, 2))

    def test_table_names_every_expectation_assess_reads(self):
        source = Path(check_corpus_content.__file__).read_text()
        body = source[source.index('def assess('):source.index('def check_evaluation(')]
        read = set(re.findall(r"item\.get\('(\w+)'", body)) | set(re.findall(r"'(\w+)' in item", body))
        self.assertEqual(read, set(EXPECTATION_KEYS))
        self.assertEqual(len(EXPECTATION_KEYS), len(set(EXPECTATION_KEYS)))
        self.assertEqual(len(CHECK_TYPES), len({name for name, _, _ in CHECK_TYPES}))

    def test_real_contracts_count_like_assess_would(self):
        contracts = json.loads((ROOT / 'corpus/regressions.json').read_text())['cases']
        totals = count_checks(contracts)
        self.assertEqual(totals['checks'], sum(totals['byType'].values()))
        self.assertEqual(totals['documents'], len([c for c in contracts if c.get('pages')]))


class RegionTests(unittest.TestCase):
    texts = {'swift-tests': '12 Swift tests', 'coverage': ' '.join(['word'] * 60),
             'documents': '3'}

    def test_inline_region_is_replaced_in_place(self):
        text = 'The suite has <!-- counts:swift-tests -->5 Swift tests<!-- counts:end --> today.\n'
        self.assertEqual(counts.rewrite(text, self.texts),
                         'The suite has <!-- counts:swift-tests -->12 Swift tests<!-- counts:end --> today.\n')

    def test_block_region_is_wrapped_and_surroundings_kept(self):
        text = 'Before.\n\n<!-- counts:coverage -->\nold\ntext\n<!-- counts:end -->\n\nAfter <!-- counts:documents -->2<!-- counts:end -->.\n'
        new = counts.rewrite(text, self.texts)
        self.assertTrue(new.startswith('Before.\n\n<!-- counts:coverage -->\nword word'))
        self.assertTrue(new.endswith('\n<!-- counts:end -->\n\nAfter <!-- counts:documents -->3<!-- counts:end -->.\n'))
        block = new.split('<!-- counts:coverage -->\n')[1].split('\n<!-- counts:end -->')[0]
        self.assertGreater(len(block.splitlines()), 1)
        self.assertTrue(all(len(line) <= counts.WIDTH for line in block.splitlines()))
        self.assertEqual(counts.rewrite(new, self.texts), new)

    def test_counts_stay_beside_their_type_when_wrapped(self):
        contracts = {'checks': 9, 'pages': 2, 'documents': 1, 'titles': ['Our Flag'],
                     'byType': {name: 1 for name, _, _ in CHECK_TYPES}}
        texts = counts.region_texts(contracts, 1, 2)
        self.assertEqual(texts['swift-tests'], '1 Swift test')
        self.assertEqual(texts['python-tests'], '2 Python tests')
        new = counts.rewrite('<!-- counts:coverage -->\n\n<!-- counts:end -->', texts)
        self.assertNotIn('\x00', new)
        self.assertFalse(any(re.fullmatch(r'\d+', line.split(' ')[-1]) for line in new.splitlines()))
        self.assertIn('*Our Flag*', new)

    def test_unknown_region_fails(self):
        with self.assertRaises(KeyError):
            counts.rewrite('<!-- counts:nonsense -->1<!-- counts:end -->', self.texts)

    def test_short_titles(self):
        self.assertEqual(counts.short_title('Dietary Guidelines for Americans, 2025–2030'),
                         'Dietary Guidelines for Americans')
        self.assertEqual(counts.short_title('Tank Health Monitoring (NASA TechPort project 97058)'),
                         'Tank Health Monitoring')
        self.assertEqual(counts.short_title('The Fed Explained: What the Central Bank Does'), 'The Fed Explained')


class StaleDetectionTests(unittest.TestCase):
    def test_check_reports_stale_and_write_fixes_it(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'doc').mkdir()
            (root / 'README.md').write_text('Has <!-- counts:documents -->3<!-- counts:end --> documents.\n')
            (root / 'doc/regression-testing.md').write_text('<!-- counts:swift-tests -->9 Swift tests<!-- counts:end -->\n')
            texts = {'documents': '3', 'swift-tests': '12 Swift tests'}
            diffs = counts.update(root, texts, check=True)
            self.assertEqual(len(diffs), 1)
            self.assertIn('-<!-- counts:swift-tests -->9 Swift tests', diffs[0])
            self.assertIn('+<!-- counts:swift-tests -->12 Swift tests', diffs[0])
            self.assertIn('9 Swift tests', (root / 'doc/regression-testing.md').read_text())
            self.assertEqual(len(counts.update(root, texts, check=False)), 1)
            self.assertEqual(counts.update(root, texts, check=True), [])

    def test_conflict_markers_fail_check_and_block_writing(self):
        # #208: both sides of a conflict around a region rewrite to the current count, so the diff
        # alone could not see the markers, and writing would settle the conflict silently.
        conflicted = ('Has\n<<<<<<< HEAD\n<!-- counts:documents -->2<!-- counts:end --> documents.\n'
                      '=======\n<!-- counts:documents -->4<!-- counts:end --> documents.\n'
                      '>>>>>>> 1f50940 (Merge)\n')
        for check in (True, False):
            with self.subTest(check=check), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'doc').mkdir()
                (root / 'README.md').write_text(conflicted)
                (root / 'doc/regression-testing.md').write_text('<!-- counts:swift-tests -->9 Swift tests<!-- counts:end -->\n')
                with self.assertRaises(counts.ConflictMarkers) as raised:
                    counts.update(root, {'documents': '3', 'swift-tests': '12 Swift tests'}, check=check)
                self.assertEqual(raised.exception.args[0], ['README.md:2', 'README.md:4', 'README.md:6'])
                self.assertEqual((root / 'README.md').read_text(), conflicted)
                self.assertIn('9 Swift tests', (root / 'doc/regression-testing.md').read_text())

    def test_conflict_markers_inside_a_block_region_are_found(self):
        text = '<!-- counts:coverage -->\n<<<<<<< ours\nold\n||||||| base\nolder\n=======\nnew\n>>>>>>>\n<!-- counts:end -->\n'
        self.assertEqual(counts.conflict_lines(text), [2, 4, 6, 8])

    def test_ordinary_markdown_is_not_a_conflict(self):
        text = 'Title\n========\n\na <<<<<<< b\n=======x\n  =======\n>>>>>>>>\n> quote\n'
        self.assertEqual(counts.conflict_lines(text), [])

    def test_main_reports_conflicts_without_a_diff(self):
        stderr = io.StringIO()
        with mock.patch.object(counts, 'swift_test_count', return_value=1), \
                mock.patch.object(counts, 'python_test_count', return_value=1), \
                mock.patch.object(counts, 'region_texts', return_value={}), \
                mock.patch.object(counts, 'contract_counts', return_value={}), \
                mock.patch.object(counts, 'update', side_effect=counts.ConflictMarkers(['README.md:7'])), \
                contextlib.redirect_stderr(stderr):
            self.assertEqual(counts.main(['--check']), 1)
        self.assertIn('conflict markers at README.md:7', stderr.getvalue())

    def test_swift_count_ignores_comments_and_strings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'Tests/X').mkdir(parents=True)
            (root / 'Tests/X/A.swift').write_text(
                '// @Test commented\n/* @Test\n */\nlet s = "@Test"\nlet t = """\n@Test\n"""\n'
                '@Test func a() {}\n@Test(arguments: [1, 2, 3]) func b(x: Int) {}\n'
                '@MainActor @Test("named") func c() {}\n@Suite struct S { @Test func d() {} }\n')
            self.assertEqual(counts.swift_test_count(root), 4)


if __name__ == '__main__':
    unittest.main()
