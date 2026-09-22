import subprocess
import tempfile
import unittest
from pathlib import Path

from check_closing_commits import (audit, closure_claims, empty_merges, introduced, issue_list,
                                   orphaned)

MERGE = [('dd160b4d4', 'Close out the abandoned branch')]


class ClosureJudgmentTests(unittest.TestCase):
    """The judgment, over synthetic histories: which empty merge strands which closure claim."""

    def test_an_unrecorded_empty_merge_stranding_a_closure_fails(self):
        failures, notes = audit(MERGE, {'dd160b4d4': {'aaa'}}, {7: {'aaa'}}, recorded={})
        self.assertEqual(notes, [])
        self.assertEqual(len(failures), 1)
        self.assertIn('#7 is closed', failures[0])

    def test_a_recorded_empty_merge_is_a_note_naming_where_it_is_reconciled(self):
        failures, notes = audit(MERGE, {'dd160b4d4': {'aaa'}}, {7: {'aaa'}},
                                recorded={'dd160b4': 'read for #231'})
        self.assertEqual(failures, [])
        self.assertIn('read for #231', notes[0])
        self.assertIn('closing 1 issue(s)', notes[0])

    def test_an_empty_merge_that_closes_nothing_needs_no_entry(self):
        failures, notes = audit([('52becb794', 'Close out wip/issue-4')], {'52becb794': {'aaa'}},
                                {7: {'present'}}, recorded={})
        self.assertEqual(failures, [])
        self.assertIn('closes nothing', notes[0])

    def test_an_issue_a_present_commit_also_claims_is_not_stranded(self):
        failures, notes = audit(MERGE, {'dd160b4d4': {'aaa'}}, {7: {'aaa', 'ported'}}, recorded={})
        self.assertEqual(failures, [])
        self.assertIn('closes nothing', notes[0])

    def test_an_entry_no_empty_merge_answers_for_fails(self):
        failures, _ = audit([], {}, {}, recorded={'dd160b4': 'read for #231'})
        self.assertEqual(len(failures), 1)
        self.assertIn('drop the entry', failures[0])

    def test_orphaned_reads_only_claims_wholly_inside_the_absent_set(self):
        self.assertEqual(orphaned({7: {'a'}, 8: {'a', 'b'}, 9: {'b'}}, {'a'}), {7: {'a'}})

    def test_a_stranded_branch_is_listed_short_enough_to_read(self):
        self.assertEqual(issue_list(range(1, 4)), '#1, #2, #3')
        self.assertEqual(issue_list(range(1, 20), most=3), '#1, #2, #3 and 16 more')


class HistoryReadingTests(unittest.TestCase):
    """The git half, over a real repository: an `ours` merge is what the tree says, not the parents."""

    def repository(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        self.git('init', '-b', 'main', root=root)
        self.git('config', 'user.email', 'test@example.com', root=root)
        self.git('config', 'user.name', 'Test', root=root)
        self.commit(root, 'base.txt', 'base', 'Start')
        return root

    def git(self, *arguments, root):
        return subprocess.run(['git', '-C', str(root), *arguments],
                              check=True, capture_output=True, text=True).stdout

    def commit(self, root, name, text, message):
        (root / name).write_text(text)
        self.git('add', name, root=root)
        self.git('commit', '-m', message, root=root)
        return self.git('rev-parse', 'HEAD', root=root).strip()

    def test_an_ours_merge_is_found_and_its_commits_are_absent(self):
        root = self.repository()
        self.git('checkout', '-b', 'side', root=root)
        stranded = self.commit(root, 'fix.txt', 'fix', 'Repair the thing\n\nCloses #42')
        self.git('checkout', 'main', root=root)
        self.commit(root, 'other.txt', 'other', 'Something else')
        self.git('merge', '-s', 'ours', 'side', '-m', 'Close out side', root=root)

        merges = empty_merges(root=root)
        self.assertEqual(len(merges), 1)
        merge = merges[0][0]
        self.assertIn(stranded, introduced(merge, root=root))
        claims = closure_claims(root=root)
        self.assertEqual(claims, {42: {stranded}})
        failures, _ = audit(merges, {merge: introduced(merge, root=root)}, claims, recorded={})
        self.assertEqual(len(failures), 1)
        self.assertIn('#42 is closed', failures[0])
        self.assertFalse((root / 'fix.txt').exists())

    def test_an_ordinary_merge_that_brings_its_content_is_not_an_empty_merge(self):
        root = self.repository()
        self.git('checkout', '-b', 'side', root=root)
        self.commit(root, 'fix.txt', 'fix', 'Repair the thing\n\nCloses #42')
        self.git('checkout', 'main', root=root)
        self.commit(root, 'other.txt', 'other', 'Something else')
        self.git('merge', '--no-ff', 'side', '-m', 'Merge side', root=root)

        self.assertEqual(empty_merges(root=root), [])
        self.assertTrue((root / 'fix.txt').exists())


if __name__ == '__main__':
    unittest.main()
