import json
import tempfile
import unittest
import unittest.mock
from pathlib import Path

import check_issue_citations as gate
from pdfreflow_tools.corpus import ROOT


class CitationReadingTests(unittest.TestCase):
    def test_prose_citations_and_issue_links_are_found(self):
        found = gate.citations('Tracked in #45 and [#164](https://github.com/vocaro/PDFReflowLib/issues/164).')
        self.assertEqual(sorted(found), [45, 164])

    def test_a_heading_anchor_is_not_a_citation(self):
        # `doc/behaviour.md#911-report-…` and `(#issue-30-coverage-expansion)` are link targets.
        self.assertEqual(gate.citations('See [the report](behaviour.md#911-commission) and '
                                        '[the seven](#issue-30-coverage-expansion).'), {})

    def test_code_is_not_a_citation(self):
        self.assertEqual(gate.citations('Run `awk \'{print $1}\' #5` here.'), {})
        self.assertEqual(gate.citations('```\ncurl example.com/#5\n```'), {})

    def test_a_commit_trailer_style_reference_is_still_a_citation(self):
        self.assertEqual(sorted(gate.citations('The fix (#204) landed.')), [204])

    def test_line_numbers_are_reported(self):
        self.assertEqual(gate.citations('one\n#45\n#45 again\n'), {45: [2, 3]})


class SnapshotTests(unittest.TestCase):
    def test_the_checked_in_snapshot_is_well_formed(self):
        snapshot, states = gate.load_snapshot()
        self.assertEqual(snapshot['repository'], gate.REPOSITORY)
        self.assertTrue(snapshot['capturedOn'])
        self.assertFalse(set(snapshot['open']) & set(snapshot['closed']), 'an issue cannot be both')
        self.assertGreater(len(states), 200)
        self.assertTrue(all(isinstance(number, int) for number in states))

    def test_the_gate_needs_no_network(self):
        """It reads the snapshot; only --refresh talks to GitHub."""
        source = (ROOT / 'tools/check_issue_citations.py').read_text()
        body = source[source.index('def audit('):source.index('def main(')]
        self.assertNotIn('subprocess', body)
        self.assertNotIn('urllib', source)


class AuditTests(unittest.TestCase):
    """The gate's verdicts, run against a throwaway tree so the real documents are untouched."""

    snapshot = {'capturedOn': '2026-09-19', 'repository': gate.REPOSITORY, 'source': 'test',
                'open': [231], 'closed': [45, 204]}

    def tree(self, document, snapshot=None):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        (root / 'doc').mkdir()
        (root / gate.SNAPSHOT).write_text(json.dumps(snapshot or self.snapshot))
        (root / 'doc/behaviour.md').write_text(document)
        (root / 'README.md').write_text('# Title\n')
        return root

    def audit(self, document, allowed, snapshot=None):
        with unittest.mock.patch.object(gate, 'ALLOWED', allowed):
            return gate.audit(self.tree(document, snapshot))[:2]

    def test_an_open_issue_passes_without_an_entry(self):
        failures, notes = self.audit('Tracked in #231.\n', {})
        self.assertEqual((failures, notes), ([], []))

    def test_a_closed_issue_with_no_entry_fails(self):
        failures, _ = self.audit('Folio joins are tracked in #45.\n', {})
        self.assertEqual(len(failures), 1)
        self.assertIn('#45 is closed but cited at doc/behaviour.md:1', failures[0])

    def test_a_historical_entry_passes_with_its_reason(self):
        failures, notes = self.audit('The gate (#204) exists.\n', {204: ('historical', 'named by its issue')})
        self.assertEqual(failures, [])
        self.assertIn('named by its issue', notes[0])

    def test_a_branch_only_entry_must_name_the_commit_in_every_citing_document(self):
        allowed = {45: ('branch-only', 'e1cbc0d0e')}
        failures, _ = self.audit('Raised in #45; the defect stands.\n', allowed)
        self.assertEqual(len(failures), 1)
        self.assertIn('cites it without naming that commit', failures[0])
        failures, notes = self.audit('Raised in #45; unfixed, the work is in `e1cbc0d0e`.\n', allowed)
        self.assertEqual(failures, [])
        self.assertIn('closed, unfixed on main', notes[0])

    def test_an_issue_the_snapshot_does_not_know_fails_rather_than_passing(self):
        failures, _ = self.audit('New work in #999.\n', {})
        self.assertEqual(len(failures), 1)
        self.assertIn('run --refresh', failures[0])

    def test_an_allow_list_entry_nothing_cites_fails(self):
        failures, _ = self.audit('Nothing here.\n', {204: ('historical', 'stale entry')})
        self.assertEqual(len(failures), 1)
        self.assertIn('no gated document cites it; drop the entry', failures[0])

    def test_an_unaudited_entry_names_its_tracker_in_the_note(self):
        _, notes = self.audit('#45 tracks it.\n', {45: ('unaudited', 'still reads as a tracker')})
        self.assertIn(f'#{gate.UNAUDITED_TRACKER}', notes[0])


class RepositoryTests(unittest.TestCase):
    def test_the_repository_documents_pass(self):
        failures, _, _ = gate.audit()
        self.assertEqual(failures, [])

    def test_decision_records_are_exempt_by_directory(self):
        names = gate.documents()
        self.assertNotIn('doc/decisions/0005-abandoned-coordination-branch.md', names)
        self.assertIn('doc/corpus.md', names)
        self.assertIn('README.md', names)

    def test_the_twelve_of_234_are_all_branch_only_and_named_in_the_prose(self):
        # Two of the twelve #234 named are no longer branch-only: #36's rules were ported for
        # #229 and #43's missing-space half for #225, so both are cited as history now. #43's
        # other half is still unported, and the corpus guide names its commit for that.
        self.assertEqual(gate.ALLOWED[36][0], 'historical')
        self.assertEqual(gate.ALLOWED[43][0], 'historical')
        self.assertIn('417edc705', (ROOT / 'doc/corpus.md').read_text())
        # #13's budget was ported too, so three of the twelve are now history.
        self.assertEqual(gate.ALLOWED[13][0], 'historical')
        twelve = [14, 37, 39, 40, 45, 153, 158, 164, 165]
        for issue in twelve:
            self.assertEqual(gate.ALLOWED[issue][0], 'branch-only', issue)
        cited = {}
        for name in gate.documents():
            for issue in gate.citations((ROOT / name).read_text()):
                cited.setdefault(issue, set()).add(name)
        for issue in twelve:
            commit = gate.ALLOWED[issue][1]
            for name in cited[issue]:
                self.assertIn(commit, (ROOT / name).read_text(), f'#{issue} in {name}')


if __name__ == '__main__':
    unittest.main()
