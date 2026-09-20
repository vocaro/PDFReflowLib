#!/usr/bin/env python3
"""Fail when the documentation sends a reader to a closed issue as the live tracker for a gap.

`doc/` is where somebody learns what this converter does badly and what is already being worked
on. Twelve of its citations pointed at issues that GitHub reports closed, for defects `main` still
has, because the branch that closed them was merged with the `ours` strategy and its content never
arrived (#234, #231, [decision 0005](../doc/decisions/0005-abandoned-coordination-branch.md)). A
reader who follows such a link concludes the gap is handled. Prose cannot be trusted to stay
honest about this by itself, so it is gated, in the mould of `tools/check_documented_builds.py`
(#204).

Every `#N` and `issues/N` in `README.md` and `doc/**/*.md` is a citation, except inside fenced or
inline code and inside link targets, where `#` introduces a heading anchor. A citation of an issue
the snapshot calls closed must appear in `ALLOWED` with a reason; a citation of an issue the
snapshot does not know fails, which is what forces the snapshot forward.

## Working offline

The issue states are a checked-in snapshot, `doc/issue-states.json`, captured by `--refresh`,
which is the only part that needs the network and is run by a person, not by a gate. So the gate
has a definite answer for every citation whether or not GitHub is reachable, and it never passes
because it could not ask.

That is honest about one thing and no more: **an issue closed after the capture date is not
caught until somebody refreshes**. The snapshot cannot detect that on its own, and no
network-free design can. What keeps it from drifting indefinitely is the unknown-issue rule: the
next citation of an issue newer than the snapshot fails the gate and is fixed by a refresh, which
re-reads every state at once. The gate prints the snapshot's age on every run so the window is
never invisible. The alternative — ask GitHub and skip when `gh` is missing or offline — is worse
in exactly the way this repository has already been bitten by: it would report PASS for a reason
that has nothing to do with whether the documentation is right.
"""
import argparse
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

from pdfreflow_tools.corpus import ROOT

REPOSITORY = 'vocaro/PDFReflowLib'
SNAPSHOT = 'doc/issue-states.json'
DOCUMENTS = ('README.md', 'doc/**/*.md')

# A decision record states what was decided and what was true on the day it was written, and
# names the issues it weighed; it is a dated record, not a tracker, and a reader is not sent to
# those issues to find out what is being worked on. Exempting the directory is deliberate:
# rewriting a decision record to keep its citations current would falsify the record.
HISTORICAL_DIRECTORIES = ('doc/decisions/',)

FENCE = re.compile(r'^\s*```')
LINK = re.compile(r'\]\(([^)]*)\)')
CODE = re.compile(r'`[^`\n]*`')
ISSUE_URL = re.compile(r'issues/(\d+)')
HASH = re.compile(r'(?<![\w/#-])#(\d+)\b')

# Citations of a closed issue the documentation may keep, each with the reason it is not a stale
# tracker. `branch-only` carries the commit that holds the fix: the defect is still in `main`, the
# prose has to say so, and the gate requires that commit to appear in every document that cites
# the issue, so the citation cannot quietly revert to reading like a live tracker (#234).
ALLOWED = {
    # Fixed, and cited for what it established or where the behaviour came from.
    7: ('historical', 'the text-layer quality rules #93/#7 introduced, which this library implements'),
    21: ('historical', 'the extraction gate, named by the issue that established it'),
    24: ('historical', 'a research note recording that #24 was closed with no production change'),
    26: ('historical', 'the reproducibility finding a pinning client is told to record'),
    30: ('historical', 'the coverage expansion that added seven corpus cases, used as its name'),
    38: ('historical', '`TextEncodingCheck`, which is in `main`, named by its issue'),
    93: ('historical', 'the recognition policy #93 introduced and `1b0308b` ported'),
    117: ('historical', 'cited in both places as explicitly not ported, so no reader is misled'),
    176: ('historical', 'the drawn-writing rule, which is in `main`, named by its issue'),
    186: ('historical', 'the typography findings whose ports are #217 and #218'),
    204: ('historical', 'the documented-builds gate, named by the issue that asked for it'),
    217: ('historical', 'the `GlyphIdentityReader` port, cited as established'),
    218: ('historical', 'the section-label port, cited as established'),
    156: ('historical', 'the generated-counts gate, named by the issue that asked for it'),
    92: ('historical', "the comparator's identifier normalization, ported onto main and named by its issue"),
    36: ('historical', 'the rule-adjacent-prose rules, ported onto main for #229 and named by their issue'),
    67: ('historical', 'the artifact and marked-content scoping of an unplaceable show, ported onto main and named by its issue'),
    91: ('historical', 'the space-only-show and invisible-artifact rules, ported onto main and named by their issue'),

    # Closed, but the defect is still in `main`; the prose says so and names the commit.
    13: ('branch-only', '183c2c4b6'),
    14: ('branch-only', '2e18b3149'),
    37: ('branch-only', '277cbde39'),
    39: ('branch-only', '3f7c23ddc'),
    40: ('branch-only', '20c78f352'),
    43: ('branch-only', '417edc705'),
    45: ('branch-only', 'e1cbc0d0e'),
    153: ('branch-only', '58a2ddda6'),
    158: ('branch-only', 'bff0a046c'),
    164: ('branch-only', '88803aca7'),
    165: ('branch-only', '3a65be6c1'),

    # Cited in the present tense as the tracker for a gap, and closed — the same fault #234
    # describes, but on issues `main` itself closed rather than the abandoned branch, so each
    # needs its own reading of whether the gap survived. Listed here so the gate is honest about
    # what it is letting through rather than silent about it.
    5: ('unaudited', 'corpus guide and regression runbook name #5 as the live output-budget gap'),
    6: ('unaudited', 'corpus guide lists #6 as a tracked OCR font/layout defect'),
    8: ('unaudited', 'corpus guide lists #8 as a tracked placeholder-text defect'),
    9: ('unaudited', 'corpus guide lists #9 as a tracked Poppler image-URL defect'),
    11: ('unaudited', 'corpus guide says #11 "tracks note-marker semantics"'),
    12: ('unaudited', 'corpus guide leaves drop-cap ordering "unqualified under" #12'),
    19: ('unaudited', 'corpus guide says #19 "tracks the warning/refusal behavior"'),
}
UNAUDITED_TRACKER = 236  # The issue that asks for the 'unaudited' entries above to be settled.


def documents(root=ROOT):
    """Every documentation file whose citations are gated, as repository-relative paths."""
    root = Path(root)
    found = []
    for pattern in DOCUMENTS:
        found += [path.relative_to(root).as_posix() for path in sorted(root.glob(pattern))]
    return [name for name in found if not name.startswith(HISTORICAL_DIRECTORIES)]


def citations(text):
    """{issue: [line number]} for the issues this text cites, ignoring code and heading anchors."""
    found, inside = {}, False
    for number, line in enumerate(text.splitlines(), 1):
        if FENCE.match(line):
            inside = not inside
            continue
        if inside:
            continue
        cited = set()
        for match in LINK.finditer(line):
            cited |= {int(issue) for issue in ISSUE_URL.findall(match.group(1))}
        cited |= {int(issue) for issue in HASH.findall(LINK.sub('](-)', CODE.sub('`-`', line)))}
        for issue in cited:
            found.setdefault(issue, []).append(number)
    return found


def load_snapshot(root=ROOT):
    snapshot = json.loads((Path(root) / SNAPSHOT).read_text())
    states = {number: 'open' for number in snapshot['open']}
    states.update({number: 'closed' for number in snapshot['closed']})
    return snapshot, states


def refresh(root=ROOT):
    """Recapture the issue states from GitHub. The only part of this tool that needs the network."""
    listing = subprocess.run(['gh', 'issue', 'list', '--repo', REPOSITORY, '--state', 'all',
                              '--limit', '1000', '--json', 'number,state'],
                             check=True, capture_output=True, text=True).stdout
    rows = json.loads(listing)
    if not rows:
        raise SystemExit('gh returned no issues; refusing to write an empty snapshot')
    snapshot = {
        'capturedOn': date.today().isoformat(),
        'repository': REPOSITORY,
        'source': f'gh issue list --repo {REPOSITORY} --state all --limit 1000 --json number,state',
        'purpose': ('What tools/check_issue_citations.py reads instead of the network. Refresh with '
                    '`python3 tools/check_issue_citations.py --refresh` and commit the result.'),
        'open': sorted(row['number'] for row in rows if row['state'] == 'OPEN'),
        'closed': sorted(row['number'] for row in rows if row['state'] == 'CLOSED'),
    }
    (Path(root) / SNAPSHOT).write_text(json.dumps(snapshot, indent=2) + '\n')
    return snapshot


def audit(root=ROOT):
    """(failures, notes): every gated citation judged against the snapshot and the allow-list."""
    snapshot, states = load_snapshot(root)
    failures, notes, cited = [], [], {}
    for name in documents(root):
        for issue, lines in citations((Path(root) / name).read_text()).items():
            cited.setdefault(issue, []).append((name, lines))
    for issue in sorted(cited):
        where = ', '.join(f'{name}:{",".join(str(line) for line in lines)}'
                          for name, lines in cited[issue])
        state = states.get(issue)
        if state is None:
            failures.append(f'#{issue} ({where}) is not in {SNAPSHOT}, captured '
                            f'{snapshot["capturedOn"]}; run --refresh and commit the snapshot')
            continue
        if state == 'open':
            continue
        if issue not in ALLOWED:
            failures.append(f'#{issue} is closed but cited at {where}; either say in the text what is '
                            f'actually true of it, or add it to ALLOWED with the reason it is historical')
            continue
        kind, detail = ALLOWED[issue]
        if kind == 'branch-only':
            missing = [name for name, _ in cited[issue] if detail not in (Path(root) / name).read_text()]
            if missing:
                failures.append(f'#{issue} is closed and its fix lives only in `{detail}`, but '
                                f'{", ".join(missing)} cites it without naming that commit')
            else:
                notes.append(f'#{issue} closed, unfixed on main, `{detail}` named at {where}')
        elif kind == 'unaudited':
            notes.append(f'#{issue} closed and cited as a live tracker at {where} '
                         f'(#{UNAUDITED_TRACKER}): {detail}')
        else:
            notes.append(f'#{issue} closed, cited as history at {where}: {detail}')
    for issue in sorted(set(ALLOWED) - set(cited)):
        failures.append(f'#{issue} is in ALLOWED but no gated document cites it; drop the entry')
    return failures, notes, snapshot


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--refresh', action='store_true',
                        help='recapture doc/issue-states.json from GitHub (needs the network), then check')
    args = parser.parse_args(argv)
    if args.refresh:
        snapshot = refresh()
        print(f'Captured {len(snapshot["open"])} open and {len(snapshot["closed"])} closed issues '
              f'into {SNAPSHOT}.')
    failures, notes, snapshot = audit()
    age = (date.today() - date.fromisoformat(snapshot['capturedOn'])).days
    print(f'{SNAPSHOT} captured {snapshot["capturedOn"]} ({age} day(s) ago): '
          f'{len(snapshot["open"])} open, {len(snapshot["closed"])} closed. An issue closed since '
          f'then is not caught until --refresh.')
    for note in notes:
        print('NOTE ' + note)
    for failure in failures:
        print('FAIL ' + failure, file=sys.stderr)
    if failures:
        raise SystemExit(f'{len(failures)} documentation citation(s) of a closed or unknown issue')
    print(f'PASS {len(documents())} documents cite no closed issue as a live tracker')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
