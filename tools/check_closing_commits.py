#!/usr/bin/env python3
"""Fail when history records a commit as merged without its content and that commit closes an issue.

`dd160b4` merged the abandoned coordination branch with the `ours` strategy: its 153 commits became
ancestors of `main` while none of their content did. Those commits carry `Closes`/`Fixes` for 124
issues, so GitHub reports 124 defects fixed that `main` has never fixed. Two agents built on such an
issue and lost most of a session each (#225, #226) before #231 read every one of the 124 against
`main`'s code. [Decision 0012](../doc/decisions/0012-an-issue-is-closed-by-what-main-holds.md) settles
the convention that produced it; this gate holds the mechanism shut.

The mechanism is one thing and is exactly detectable: a merge whose tree equals its first parent's
tree brings no content, whatever its parents say. Every commit such a merge introduces — reachable
from `HEAD`, absent from its tree — is recorded as merged and is not here. That is not by itself
wrong: `52becb79` closed out `wip/issue-4-pdfkit-growth` the same way, and nothing was claimed
fixed by it. What is wrong is an issue whose *only* claim to be closed sits in commits no tree
holds, because that claim is what a reader trusts.

So the gate fails on an empty merge that orphans a closure claim, unless `RECORDED` names it and
says where the reconciliation lives. An empty merge that orphans nothing is a note. An issue also
claimed by a commit that is present passes: a port that lands the fix under its own commit answers
for the issue whatever the branch did. A branch whose commits were cherry-picked before it was
merged reads as an empty merge too, and is a note unless its `Closes` never moved to the commit
that landed — which is the same defect wearing a different hat, and is fixed the same way.

This reads git and nothing else, so it has an answer offline and needs no allow-list that grows
with the defect: the 124 are data, derived here rather than retyped. It cannot see an issue somebody
closed by hand on GitHub while citing a branch commit — no local check can — and decision 0012 is
what governs that. `--list` prints the issues an empty merge orphans.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from pdfreflow_tools.corpus import ROOT

SNAPSHOT = 'doc/issue-states.json'

# `Closes #N` in a commit message is what GitHub acts on and what a reader reads.
CLAIM = re.compile(r'\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)\b', re.I)

# The empty merges whose orphaned closure claims have been reconciled, and where that reconciliation
# is. An entry is required before such a merge may exist; dropping the merge drops the entry.
RECORDED = {
    'dd160b4': ('the abandoned coordination branch '
                '(decision 0005; every issue it orphans was read against `main` for #231 and '
                'carries a comment naming the branch commit that holds its fix)'),
}


def git(*arguments, root=ROOT):
    """That git command's output, as text."""
    return subprocess.run(['git', '-C', str(root), *arguments],
                          check=True, capture_output=True, text=True).stdout


def empty_merges(revision='HEAD', root=ROOT):
    """[(commit, subject)] for merges on that history whose tree is their first parent's tree.

    Such a merge records its other parents as merged and brings nothing of theirs into the tree.
    """
    found = []
    for line in git('rev-list', '--merges', '--format=%H%x00%s', revision, root=root).splitlines():
        if line.startswith('commit ') or not line.strip():
            continue
        commit, subject = line.split('\x00', 1)
        if git('rev-parse', f'{commit}^{{tree}}', root=root) == git('rev-parse', f'{commit}^1^{{tree}}', root=root):
            found.append((commit, subject))
    return found


def introduced(merge, root=ROOT):
    """The commits that merge records as merged and its first parent does not already hold."""
    parents = git('rev-parse', f'{merge}^@', root=root).split()
    return set(git('rev-list', *parents[1:], '--not', parents[0], root=root).split())


def closure_claims(revision='HEAD', root=ROOT):
    """{issue: {commit}} for every `Closes #N` on that history."""
    claims = {}
    for entry in git('log', '--format=%H%x00%B%x01', revision, root=root).split('\x01'):
        if not entry.strip():
            continue
        commit, message = entry.strip('\n').split('\x00', 1)
        for issue in CLAIM.findall(message):
            claims.setdefault(int(issue), set()).add(commit)
    return claims


def issue_list(issues, most=12):
    """`#1, #2, ...` for a failure line, kept short enough to read when a whole branch is stranded."""
    shown = ', '.join(f'#{issue}' for issue in sorted(issues)[:most])
    return shown if len(issues) <= most else f'{shown} and {len(issues) - most} more'


def orphaned(claims, absent):
    """{issue: {commit}} for the issues whose every closure claim sits in an absent commit."""
    return {issue: commits for issue, commits in claims.items() if commits <= absent}


def audit(merges, absent_by_merge, claims, recorded=RECORDED):
    """(failures, notes) for that history, judged against the merges RECORDED already answers for.

    `merges` is [(commit, subject)], `absent_by_merge` {commit: {commit}}, `claims` {issue: {commit}}.
    """
    failures, notes, answered = [], [], set()
    for merge, subject in merges:
        entry = next((short for short in recorded if merge.startswith(short)), None)
        stranded = orphaned(claims, absent_by_merge[merge])
        if entry:
            answered.add(entry)
        if stranded and not entry:
            failures.append(f'{merge[:9]} ("{subject}") has its first parent\'s tree, so it brings no '
                            f'content, and it is the only place {issue_list(stranded)} '
                            f'{"is" if len(stranded) == 1 else "are"} closed. Close the issue from '
                            f'the commit that lands the fix, land it, or reopen the issue and add '
                            f'this merge to RECORDED with where it is reconciled')
        elif stranded:
            notes.append(f'{merge[:9]} ("{subject}") records {len(absent_by_merge[merge])} commit(s) '
                         f'whose content is not in this tree, closing {len(stranded)} issue(s): '
                         f'{recorded[entry]}')
        else:
            notes.append(f'{merge[:9]} ("{subject}") brings no content and closes nothing')
    for entry in sorted(set(recorded) - answered):
        failures.append(f'{entry} is in RECORDED but is no longer an empty merge on this history; '
                        f'drop the entry')
    return failures, notes


def states(root=ROOT):
    """{issue: state} from the checked-in snapshot, or {} when it is absent."""
    path = Path(root) / SNAPSHOT
    if not path.exists():
        return {}
    snapshot = json.loads(path.read_text())
    return ({number: 'open' for number in snapshot['open']} |
            {number: 'closed' for number in snapshot['closed']})


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--list', action='store_true',
                        help='also print each issue an empty merge is the only closure for')
    parser.add_argument('--revision', default='HEAD', help='the history to read (default HEAD)')
    arguments = parser.parse_args(argv)
    if git('rev-parse', '--is-shallow-repository').strip() == 'true':
        raise SystemExit('this repository is shallow; the gate cannot see whether a merge brought '
                         'its content. Run `git fetch --unshallow` and try again')
    merges = empty_merges(arguments.revision)
    absent_by_merge = {merge: introduced(merge) for merge, _ in merges}
    claims = closure_claims(arguments.revision)
    failures, notes = audit(merges, absent_by_merge, claims)
    known = states()
    print(f'{arguments.revision}: {len(claims)} issue(s) closed by commit message, {len(merges)} '
          f'merge(s) that bring no content.')
    for note in notes:
        print('NOTE ' + note)
    if arguments.list:
        for merge, _ in merges:
            for issue, commits in sorted(orphaned(claims, absent_by_merge[merge]).items()):
                state = known.get(issue, f'not in {SNAPSHOT}')
                print(f'     #{issue} ({state}) closed only by '
                      f'{", ".join(sorted(commit[:9] for commit in commits))}')
    for failure in failures:
        print('FAIL ' + failure, file=sys.stderr)
    if failures:
        raise SystemExit(f'{len(failures)} merge(s) closing an issue without bringing the fix')
    print(f'PASS every issue closed on {arguments.revision} is closed by a commit this tree holds, '
          f'or by a merge RECORDED answers for')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
