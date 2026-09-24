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
    17: ('historical', 'the validated structure mapping and bounded index now in the tree, with spatial fallback for unsupported associations'),
    195: ('historical', 'the owner decisions implemented for bibliography paragraphs, conservative endnotes and verified lists'),
    219: ('historical', 'the bibliography, endnote, lettered-list and exercise-order prerequisites now in the tree'),
    18: ('historical', 'the reviewed CDC image fallback already on main, with unqualified panel ordering stated explicitly'),
    44: ('historical', 'the three script corpus admissions already on main, with their qualification limits stated'),
    171: ('historical', 'the source-backed paragraph, reference and table rules already on main'),
    # Fixed, and cited for what it established or where the behavior came from.
    15: ('historical', 'the source-validated chapter boundaries and bounded report processing now in the tree'),
    160: ('historical', 'the column-cut, hanging-entry and cross-figure continuation rules now in the tree'),
    172: ('historical', 'the isolated-marker and detached-cover-label rules now in the tree'),
    7: ('historical', 'the text-layer quality rules #93/#7 introduced, which this library implements'),
    21: ('historical', 'the extraction gate, named by the issue that established it'),
    233: ('historical', 'the line-end hyphen a book encodes as another character, on main and named by its issue'),
    42: ('historical', 'the East Asian spacing and heading rules, on main and named by their issue'),
    235: ('historical', 'the painted-underline rule, on main and named by its issue'),
    246: ('historical', "the page-furniture rule for a footer band, on main and named by its issue"),
    59: ('historical', 'the released half of a word a crop cut off, on main and named by its issue'),
    183: ('historical', 'the list-marker size rule, on main and named by its issue; its mirror is #254'),
    245: ('historical', 'the crop rule it established, on main and named by its issue'),
    24: ('historical', 'a research note recording that #24 was closed with no production change'),
    26: ('historical', 'the reproducibility finding a pinning client is told to record'),
    291: ('historical', "a sentence's own stop joining the block above it, on main and named by its issue"),
    31: ('historical', 'the scanned-table fallback rule, on main and named by its issue'),
    173: ('historical', "the Vision variance across compiled model sets it recorded, measured as not reproducing on main and answered per run by #284's control run"),
    294: ('historical', 'the document-wide heading rank, on main and named by its issue'),
    243: ('historical', "the IRS cover's contents heading that the rank restores, on main and named by its issue"),
    292: ('historical', 'the list conversion — the list-item block, ListBuilder and real list output — on main and named by its issue'),
    293: ('historical', "the corpus lane passing each book's declared language, on main and named by its issue"),
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
    143: ('historical', 'the index-glyph decoding, ported onto main for #226 and named by its issue'),
    13: ('historical', "the operation budget, raised on main to the number #13 reached; the book it names "
         'no longer falls back on it at all'),
    52: ('historical', 'the clip-bounded figure footprint, on main and named as the rule came from it'),
    98: ('historical', 'the same rule, cited beside #52 for the second page it was measured on'),
    43: ('historical', "the font-change word spaces, ported onto main for #225; the paper's heading and "
         'section-label half is unported and the corpus guide says so with its commit'),
    119: ('historical', 'the same-font word spaces, ported onto main for #225 and named as the rule came from it'),
    128: ('historical', 'the kern-absorbed sentence spaces, ported onto main for #225 and named the same way'),
    116: ('historical', 'the recognition-coverage rule and its band retry, ported onto main and named by its issue'),
    67: ('historical', 'the artifact and marked-content scoping of an unplaceable show, ported onto main and named by its issue'),
    91: ('historical', 'the space-only-show and invisible-artifact rules, ported onto main and named by their issue'),
    39: ('historical', 'the marker-continuation rule, ported onto main for #238 and named by its issue'),
    10: ('historical', 'the margin-slot furniture evidence, on main and named by the investigation it settled'),
    184: ('historical', 'the chapter-page head normalization and the vocabulary measured after removal, on main'),
    232: ('historical', 'the pointer convention for records naming a moved tool path, applied and named by its issue'),
    237: ('historical', 'the glyph carry across a split row, on main and named by its issue'),
    238: ('historical', 'the wrapped-line rule, on main; cited beside #39, whose fix it is'),
    239: ('historical', 'the prose-over-pictures rule, on main and named by its issue'),
    240: ('historical', 'coverage measured from what a line wrote, on main and named by its issue'),
    241: ('historical', 'the form-XObject tag rule, on main and named by its issue'),
    242: ('historical', 'the admission of the Warren and NOAA full conversions to the corpus lane, ruled on the '
          'issue and named by it'),
    57: ('historical', 'the figure-seed and row-continuation rules, on main and named by the issue they came from'),
    137: ('historical', 'the rows a page means to be read across — the spanning-picture divider and the '
          'borderless-table row blocks, on main — cited beside #174 and #210 as the cases the run-on '
          "rule must refuse, and widened by #160 to a picture with an empty side and to that picture's "
          'spanning label'),
    220: ('historical', 'the kept-as-extracted layer outcome, on main and named by its issue'),
    221: ('historical', 'the encoding outcome the damaged-text warning reports, on main and named by its issue'),
    222: ('historical', 'the empty-recognition rule, on main and named by its issue'),
    223: ('historical', 'the inherited-resources font walk, on main and named by its issue'),
    224: ('historical', 'the emptyPage and complexLayout triggers, on main and named by the issue that asked for them'),
    225: ('historical', 'the ported missing-space reader, on main and named by the issue that scoped the port'),
    226: ('historical', 'the ported glyph-index decoder, on main and named by the issue that scoped the port'),
    227: ('historical', 'the web-address exclusion from the equation seed, on main and named by its issue'),
    229: ('historical', 'the thin-rule seed and bounded expansion, on main and named by the issue that scoped the port'),
    234: ('historical', 'the closed-issue citation gate, named by the issue that asked for it'),
    6: ('historical', "the invisible-OCR font and geometry inference, fixed on main by `7fcb80f` "
        'and named for where the behavior came from'),
    8: ('historical', 'the object-placeholder exclusion from semantic text and reflow counts, '
        'fixed on main by `305cb14` and named by its issue'),
    9: ('historical', "the comparison harness's relative Poppler image URLs, fixed on main by "
        '`b5f1937` and named by its issue'),
    19: ('historical', 'the `unverifiedTextLayer` warning, implemented on main by `305cb14` and '
         'named by the issue that asked for it'),
    12: ('historical', "the Fed report's prose-as-headings defect, fixed on main by `294d0cd` and "
         'named by the research note that keeps its failing case'),

    # Closed on 2026-09-22 by work that is on `main`, and cited for the rule each established.
    # These were invisible to the gate while `doc/issue-states.json` was a day behind the
    # repository it describes: the snapshot said 85 open where GitHub said 51, so 34 citations
    # passed unchecked. Refreshing it is what surfaced them.
    41: ('historical', 'right-to-left reading and the rules written through it, on main and named by its '
       'issue'),
    120: ('historical', 'the twelve-character anchor the segmented walk resynchronizes on, on main and named by its '
        'issue'),
    123: ('historical', "the hyphen vocabulary and the leading a page's own text states, on main and named by their "
        "issue"),
    130: ('historical', "a recognized line's type size and the wrap tests written on it, on main and named by their "
        "issue"),
    139: ('historical', "the boundary dropped against a disagreeing region's edge, on main and named by its "
        "issue"),
    203: ('historical', 'the cross-page join that steps over a picture, on main and named by its issue'),
    207: ('historical', 'the thin rule a printed row owns, on main and named by its issue'),
    210: ('historical', '`TableReader`, which reads a table as its cells, on main and named by its issue'),
    231: ('historical', 'the reconciliation of the abandoned coordination branch, which is done and is where its '
        'results are recorded; the prose sends a reader there for that list, not for work in progress'),
    247: ('historical', 'converted links and the anchor a linked phrase keeps, on main and named by their '
        'issue'),
    248: ('historical', 'the printed page numbers a marker and the page list carry, on main and named by its '
        'issue'),
    249: ('historical', "the navigation document built from the source's outline, on main and named by its "
        "issue"),
    251: ('historical', "the source's own picture written as the page placed it, on main and named by its "
        "issue"),
    252: ('historical', 'the locked-document password rule and its `encryptedPDF` error, on main and named by its '
        'issue'),
    253: ('historical', 'the package metadata rule, on main and named by its issue'),
    254: ('historical', "the list-marker size rule's mirror, on main and named by its issue; its other half is "
        "#183"),
    255: ('historical', "the crop rule that never admits a line reading as the book's own prose, on main and named by "
        "its issue"),
    256: ('historical', 'the rest of a marked item is no heading, on main and named by its issue'),
    257: ('historical', "a table's column header released from a crop, on main and named by its issue"),
    258: ('historical', 'the line heights a script or a stacked fraction gives PDFKit, on main and named by its '
        'issue'),
    259: ('historical', 'a line the page keys its own material to is no heading, on main and named by its '
        'issue'),
    261: ('historical', 'a bullet alone on its line is the marker its page drew, on main and named by its '
        'issue'),
    262: ('historical', 'the pieces a split row is compared against, on main and named by its issue'),
    263: ('historical', 'the sideways reading order and the turn a line carries, on main and named by its '
        'issue'),
    264: ('historical', 'the margin rule kept out of the line beside it, on main and named by its issue'),
    266: ('historical', 'the numbered item that keeps the rest of a word its page broke, on main and named by its '
        'issue'),
    267: ('historical', "the cross-page join's anchor — only a block the page's own text begins at — on main and named "
        "by its issue"),
    268: ('historical', 'a reference list the page hung at an indent is not a table, on main and named by its '
        'issue'),
    270: ('historical', 'the row of two columns cut at the gutter PDFKit merged across, on main and named by its '
        'issue'),
    271: ('historical', 'the page-furniture band rule, on main and named by its issue'),
    272: ('historical', 'the split row that lends its start to the line beneath it, on main and named by its '
        'issue'),
    273: ('historical', 'a run of whitespace takes no inline script, on main and named by its issue'),
    274: ('historical', 'the space taken back where a page draws one number in two shows, on main and named by its '
        'issue'),
    275: ('historical', 'a lone letter is a word only in the company of words, on main and named by its '
        'issue'),
    # Entered with the commit that closes it, so the gate does not fail the next time the snapshot
    # is refreshed: every citation of it names a rule that commit put on main.
    108: ('historical', 'the language tag, the language-correction opt-in and its measured cost, and the '
        'Latin-to-Cyrillic look-alike repair, on main and named by their issue'),

    # Closed by the nine commits that reached `origin/main` together on 2026-09-22, each cited for
    # the rule it established or the finding it records. They needed a second refresh within a day
    # of #286's, which is that snapshot's blind spot working exactly as #286 describes: an issue
    # closed after the capture date is invisible to this gate until somebody asks GitHub again.
    # #286 itself takes no entry, because no gated document cites it.
    269: ('historical', "Vision's reading differing between two runs of one binary on one host, "
        'recorded beside #281 and #284 and no longer pinned by the suspect-text contract'),
    277: ('historical', 'the page number a contents entry runs its leader out to, on main and named '
        'by its issue'),
    278: ('historical', 'a run of whitespace takes no emphasis from its font, on main and named by '
        'its issue; its sibling is #273'),
    279: ('historical', 'the hanging bullet column that is no column of the page, on main and named '
        'by its issue'),
    281: ('historical', 'the same run-to-run variance as #269, cited beside it for the lane it was '
        'measured in'),
    282: ('historical', 'the reference list hung under an outdented marker column, on main and named '
        'by its issue'),
    283: ('historical', 'a stack of cells standing on the rows of a column is no column of the page, '
        'on main and named by its issue'),
    284: ('historical', "`compare_conversion_runs.py --control`, on main and named by the issue that "
        'asked for it'),
    287: ('historical', 'the gate results directory kept only while it is worth reading, on main and '
        'named by its issue'),
    # Closed the same day these citations were written, which is the blind spot #286 records: the
    # snapshot agreed with GitHub until the push, and the refresh that followed it exposed them.
    174: ('historical', 'the block-level reading order `columnRuns` gives a page with no straight '
        'gutter, on main and named by its issue'),
    230: ('historical', "a line's own depth, read where PDFKit grew its rectangle to fit what the "
        'line carries, on main and named by its issue'),
    260: ('historical', 'a show the line can hold in only one place placing its own boundaries, on '
        'main and named by its issue'),
    285: ('historical', 'the cell that closes a printed row and so lends it no start, on main and '
        'named by its issue'),
    276: ('historical', "every measure a page takes of a sideways line reading the writing's own "
        'frame, on main and named by its issue'),
    280: ('historical', 'an item carrying the whole block that holds the rest of its word, on main '
        'and named by its issue'),
    288: ('historical', 'a line the page broke at a hyphen closing up whatever opens beneath it, '
        'on main and named by its issue'),
    289: ('historical', "the candidate band read against a book's own page image where the sheet "
        'carries one, on main and named by its issue'),
    290: ('historical', 'a bare number in the outer margin refused the title reading, on main and '
        'named by its issue'),

    # Closed, but the defect is still in `main`; the prose says so and names the commit. #5 and
    # #11 join this group from #236's audit: both were read against `main` — Warren and NOAA
    # measured at 2.32 and 2.16 times the default output budget, and no note linker exists — and
    # both turned out to have been closed by the abandoned branch after all, not by `main`.
    14: ('branch-only', '2e18b3149'),
    37: ('branch-only', '277cbde39'),
    40: ('branch-only', '20c78f352'),
    45: ('branch-only', 'e1cbc0d0e'),
    153: ('branch-only', '58a2ddda6'),
    158: ('branch-only', 'bff0a046c'),
    164: ('branch-only', '88803aca7'),
    165: ('branch-only', '3a65be6c1'),
    5: ('branch-only', 'fbe3464'),
    11: ('branch-only', '9803329'),
}
# Where a citation parked as 'unaudited' is reported. The kind is empty today: #236 settled the
# seven it was introduced for, four to 'historical' and two to 'branch-only', and #12's citation
# left the prose. It stays so the next batch has somewhere to sit while it is read against `main`.
UNAUDITED_TRACKER = 236


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
