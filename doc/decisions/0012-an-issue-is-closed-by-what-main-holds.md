# 0012 An issue is closed by what main's tree holds, not by a commit that names it

## Context

`dd160b4` closed out the abandoned coordination branch with an `ours` merge
([0005](0005-abandoned-coordination-branch.md)): `dd160b4^{tree}` and `dd160b4^1^{tree}` are both
`9c8b33e`, so all 153 of the branch's commits are ancestors of `main` and none of their content is.
Those commits carry `Closes`/`Fixes` for 124 distinct issue numbers. The audit that accompanied the
merge checked that the branch's *findings* were captured in issues; it did not check that the
*fixes* were in the tree, and the convention it set — close the issue, cite the branch commit —
made the two look like one question.

The cost landed on the people who came next. Two agents working on unrelated issues stopped mid-session
because the work their issue builds on is closed and absent (#225, #226). #231 then read all 124
against `main`'s code, one mechanism at a time: 4 had been hand-ported, 7 were superseded, and 113
were closed with the defect intact. #234 found the same hole in the prose — twelve citations in
`doc/` sent a reader to a closed issue as the live tracker for a gap `main` still has — and gated it.

Three positions were available. Keep the convention and rely on comments: cheapest, and it is what
produced the two lost sessions, because a comment is not what a reader checks first. Reopen all 113:
honest about the defects, but it throws away the distinction between an issue nobody has worked and
one whose fix is written and findable, and it re-opens issues whose fixes have since landed under a
porting issue. Or change what closing means and record where the 113 fixes are.

## Decision

An issue is closed when `main`'s tree holds the fix. Not when a commit somewhere names the issue,
not when a branch that would fix it exists, and not when a merge records that branch as merged.

- A commit says `Closes #N` only if the commit is meant to land on `main` with its content. Work
  that refers to an issue without fixing it says `Refs #N`.
- A merge whose tree equals its first parent's tree brings nothing. It may record a branch as
  closed out, but it closes no issue, and an issue whose only closure claim sits in the commits
  such a merge introduces is not closed.
- An abandoned branch's issues are reopened, or left closed only with a comment on the issue naming
  the commit that holds the unported fix, so that the next person to pick the issue up learns it
  before they start. #231 wrote that comment on all 113.
- Documentation names the commit alongside any closed issue it cites for a defect `main` still has;
  `tools/check_issue_citations.py` gates that (#234).

The 113 stay closed with their comments rather than being reopened: their fixes are written, found
and cited, the reconciliation table on #231 is the index, and the ports since then cite the issue
they came from rather than re-closing it. That is a judgment about these 113 and the record that
now exists for them, not a general license — under this decision a branch abandoned tomorrow reopens
its issues, because no reconciliation would have been written for them.

## Consequences

- `tools/check_closing_commits.py` holds the mechanism shut. It reads git alone: a merge whose tree
  is its first parent's tree brings no content, every commit it introduces is recorded-but-absent,
  and an issue whose every `Closes` sits in that set is closed by nothing. Such a merge fails unless
  `RECORDED` names it and says where its orphaned closures are reconciled. `dd160b4` is the one
  entry. `52becb79`, which closed out `wip/issue-4-pdfkit-growth` the same way, needs none: it
  strands no closure claim, which is the difference that matters.
- The 124 are derived, not retyped. `--list` prints them with the branch commit that closes each and
  its state in `doc/issue-states.json`, so the reconciliation's count is checkable rather than
  historical.
- The gate cannot see an issue closed by hand on GitHub against a branch commit, and no local check
  can. That is what this decision governs in prose, and what the per-issue comments answer for the
  124 already closed that way.
- A port that lands a branch fix keeps citing the issue it came from and need not reopen it to close
  it again: the issue's comment already says where the fix was. Should a port close such an issue
  outright, the gate stops counting it stranded, because a commit this tree holds now claims it.
- The cost is one line in a commit message: `Refs #N` while the work is in flight, `Closes #N` on the
  commit that lands. Nothing about branching, worktrees or review changes.

## Evidence

Commit `dd160b4` and its trees; the reconciliation of all 124 on
[#231](https://github.com/vocaro/PDFReflowLib/issues/231) with the per-issue comments it left; the
two sessions that stopped on a closed-but-absent issue, [#225](https://github.com/vocaro/PDFReflowLib/issues/225)
and [#226](https://github.com/vocaro/PDFReflowLib/issues/226); the documentation half in
[#234](https://github.com/vocaro/PDFReflowLib/issues/234) and `tools/check_issue_citations.py`;
`tools/check_closing_commits.py` and `tools/test_check_closing_commits.py`.
