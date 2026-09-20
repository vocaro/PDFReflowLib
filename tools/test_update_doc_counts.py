import re
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

import update_doc_counts as counts
from check_corpus_content import CONTRACT_CHECK_TYPES, PAGE_CHECK_TYPES, assess, count_checks
from pdfreflow_tools.corpus import ROOT, regression_contracts

DOC = """# Title

The lane converts <!-- counts:corpus-documents -->1<!-- counts:end --> documents.

<!-- counts:contract-breakdown -->
stale
<!-- counts:end -->

Prose that must not move.
"""


class CountSourceTests(unittest.TestCase):
    """The numbers come from the suites, not from the text they are written into."""

    def test_every_counted_check_kind_is_in_the_table(self):
        source = (ROOT / 'tools/check_corpus_content.py').read_text()
        body = source[source.index('def assess('):source.index('def check_evaluation(')]
        counted = set(re.findall(r"item\.get\('(\w+)'", body)) | set(re.findall(r"'(\w+)' in item", body))
        counted -= {'page'}
        self.assertEqual(counted, set(PAGE_CHECK_TYPES),
                         'assess reads a page expectation that PAGE_CHECK_TYPES does not count')

    def test_assess_refuses_a_contract_whose_running_total_leaves_the_table(self):
        contract = {'sourceSHA256': 'a' * 64, 'pages': [{'page': 1, 'text': ['one']}]}
        case = {'id': 'c', 'sha256': 'a' * 64, 'bytes': 1, 'pages': 1}
        result = {'case': case, 'runPassed': True, 'conversionExitCode': 0}
        pages = {1: {'text': 'one', 'images': []}}
        report = {'pageCount': 1, 'warnings': []}
        self.assertTrue(assess(case, contract, result, report, pages, [1])['passed'])
        without_text = {k: v for k, v in PAGE_CHECK_TYPES.items() if k != 'text'}
        with unittest.mock.patch.dict(PAGE_CHECK_TYPES, without_text, clear=True):
            with self.assertRaises(ValueError):
                assess(case, contract, result, report, pages, [1])
        self.assertEqual(list(PAGE_CHECK_TYPES)[0], 'text', 'the table must survive the patch in order')

    def test_counts_are_taken_from_the_real_contracts_and_suites(self):
        contracts = regression_contracts()['cases']
        expected = count_checks(contracts)
        self.assertEqual(expected['pages'], sum(len(c['pages']) for c in contracts))
        self.assertGreater(expected['checks'], expected['pages'])
        self.assertEqual(set(expected['byType']), set(CONTRACT_CHECK_TYPES) | set(PAGE_CHECK_TYPES))
        text = counts.region_texts()['contract-coverage']
        self.assertIn(f'{expected["checks"]} checks on {expected["pages"]} reviewed pages', text)

    def test_the_swift_count_matches_what_swift_test_reports(self):
        """The @Test scan is a stand-in for `swift test list`; this is the claim it rests on."""
        listing = subprocess.run(['swift', 'test', 'list', '--skip-build'], cwd=ROOT,
                                 capture_output=True, text=True)
        if listing.returncode != 0:
            self.skipTest('no debug test build to list')
        self.assertEqual(counts.swift_test_count(),
                         sum(1 for line in listing.stdout.splitlines() if line.strip()))

    def test_the_python_count_is_the_suite_check_all_runs(self):
        self.assertEqual(counts.python_test_count(), unittest.TestLoader().discover(
            str(ROOT / 'tools'), pattern='test_*.py', top_level_dir=str(ROOT / 'tools')).countTestCases())


class RegionRewriteTests(unittest.TestCase):
    texts = {'corpus-documents': '18', 'contract-breakdown': 'A ' + 'long word ' * 30 + 'end.'}

    def rewritten(self, document):
        return counts.rewrite(*counts.resolve_conflicts(document)[:1], self.texts)

    def test_only_region_bodies_change(self):
        new = counts.rewrite(DOC, self.texts)
        self.assertIn('The lane converts <!-- counts:corpus-documents -->18<!-- counts:end --> documents.', new)
        self.assertIn('Prose that must not move.', new)
        self.assertNotIn('stale', new)

    def test_a_paragraph_region_is_wrapped_and_an_inline_region_is_not(self):
        new = counts.rewrite(DOC, self.texts)
        body = new.split('<!-- counts:contract-breakdown -->')[1].split('<!-- counts:end -->')[0]
        self.assertTrue(body.startswith('\n') and body.endswith('\n'))
        self.assertTrue(all(len(line) <= counts.WIDTH for line in body.splitlines()))
        self.assertGreater(len(body.strip().splitlines()), 1)

    def test_rewriting_is_idempotent(self):
        once = counts.rewrite(DOC, self.texts)
        self.assertEqual(counts.rewrite(once, self.texts), once)

    def test_an_unknown_region_name_is_an_error(self):
        with self.assertRaises(KeyError):
            counts.rewrite('<!-- counts:invented -->x<!-- counts:end -->', self.texts)


class MergeConflictTests(unittest.TestCase):
    """#156's own failure mode: two branches that both regenerated the same counts."""

    texts = {'corpus-documents': '18', 'contract-breakdown': 'Twenty checks.'}

    def conflict(self, ours, theirs):
        return f'Before.\n<<<<<<< HEAD\n{ours}\n=======\n{theirs}\n>>>>>>> other\nAfter.\n'

    def test_a_conflict_between_two_generated_lines_is_resolved_by_regenerating(self):
        document = self.conflict('The lane converts <!-- counts:corpus-documents -->16<!-- counts:end --> documents.',
                                 'The lane converts <!-- counts:corpus-documents -->17<!-- counts:end --> documents.')
        resolved, unresolved = counts.resolve_conflicts(document)
        self.assertEqual(unresolved, 0)
        new = counts.rewrite(resolved, self.texts)
        self.assertNotIn('<<<<<<<', new)
        self.assertNotIn('=======', new)
        self.assertIn('<!-- counts:corpus-documents -->18<!-- counts:end -->', new)
        self.assertIn('Before.\n', new)
        self.assertIn('After.\n', new)

    def test_a_conflict_inside_one_region_body_needs_no_special_case(self):
        document = ('<!-- counts:contract-breakdown -->\n<<<<<<< HEAD\nsixteen\n=======\n'
                    'seventeen\n>>>>>>> other\n<!-- counts:end -->\n')
        new = counts.rewrite(*counts.resolve_conflicts(document)[:1], self.texts)
        self.assertEqual(new, '<!-- counts:contract-breakdown -->\nTwenty checks.\n<!-- counts:end -->\n')

    def test_a_conflict_that_touches_prose_is_left_for_a_person(self):
        document = self.conflict('Prose one. <!-- counts:corpus-documents -->16<!-- counts:end -->',
                                 'Prose two. <!-- counts:corpus-documents -->17<!-- counts:end -->')
        resolved, unresolved = counts.resolve_conflicts(document)
        self.assertEqual(unresolved, 1)
        self.assertIn('<<<<<<<', resolved)

    def test_git_itself_produces_a_conflict_this_tool_resolves(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp)
            run = lambda *args: subprocess.run(['git', *args], cwd=repo, check=True,
                                               capture_output=True, text=True)
            run('init', '-q', '-b', 'main')
            run('config', 'user.email', 'test@example.com')
            run('config', 'user.name', 'Test')
            document = repo / 'doc.md'
            document.write_text(counts.rewrite(DOC, {**self.texts, 'corpus-documents': '15'}))
            run('add', 'doc.md')
            run('commit', '-qm', 'base')
            run('checkout', '-qb', 'other')
            document.write_text(counts.rewrite(document.read_text(), {**self.texts, 'corpus-documents': '17'}))
            run('commit', '-qam', 'other counts')
            run('checkout', '-q', 'main')
            document.write_text(counts.rewrite(document.read_text(), {**self.texts, 'corpus-documents': '16'}))
            run('commit', '-qam', 'our counts')
            merge = subprocess.run(['git', 'merge', 'other'], cwd=repo, capture_output=True, text=True)
            self.assertNotEqual(merge.returncode, 0, 'expected a conflict to resolve')
            self.assertIn('<<<<<<<', document.read_text())
            resolved, unresolved = counts.resolve_conflicts(document.read_text())
            self.assertEqual(unresolved, 0)
            new = counts.rewrite(resolved, self.texts)
            self.assertNotIn('<<<<<<<', new)
            self.assertIn('<!-- counts:corpus-documents -->18<!-- counts:end -->', new)


class GateTests(unittest.TestCase):
    def test_the_repository_documents_are_current(self):
        diffs, conflicted = counts.update(ROOT, counts.region_texts(), check=True)
        self.assertEqual(conflicted, [])
        self.assertEqual(diffs, [], 'run python3 tools/update_doc_counts.py')

    def test_a_hand_edited_count_fails_the_check_and_is_repaired_by_a_run(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'doc').mkdir()
            for relative in counts.DOCS:
                (root / relative).write_text((ROOT / relative).read_text())
            texts = counts.region_texts()
            counts.update(root, {**texts, 'python-tests': '3 Python tests'}, check=False)
            self.assertIn('3 Python tests', (root / 'doc/regression-testing.md').read_text())
            self.assertTrue(counts.update(root, texts, check=True)[0], 'a wrong count must fail --check')
            self.assertIn('3 Python tests', (root / 'doc/regression-testing.md').read_text(),
                          '--check must not write')
            counts.update(root, texts, check=False)
            self.assertEqual(counts.update(root, texts, check=True)[0], [])
            for relative in counts.DOCS:
                self.assertEqual((root / relative).read_text(), (ROOT / relative).read_text())

    def test_every_region_in_the_documents_has_generated_text(self):
        names = {match['name'] for relative in counts.DOCS
                 for match in counts.REGION.finditer((ROOT / relative).read_text())}
        self.assertTrue(names)
        self.assertEqual(names - set(counts.region_texts()), set())

    def test_no_generated_region_is_left_unused(self):
        names = {match['name'] for relative in counts.DOCS
                 for match in counts.REGION.finditer((ROOT / relative).read_text())}
        self.assertEqual(set(counts.region_texts()) - names, set(),
                         'a generated count nothing cites is a count nobody maintains')


if __name__ == '__main__':
    unittest.main()
