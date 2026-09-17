import subprocess, sys, shutil, re
# Disable each rule part in turn, run the focused suites, record failing tests, restore.
W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a397b1066057391a4'
S = '/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue97/src-cand'
LR = 'Sources/PDFReflowLib/LayoutReconstructor.swift'
FD = 'Sources/PDFReflowLib/FurnitureDetector.swift'
mutations = [
    ('italic sub-heading tier', LR, 'guard style.bold || style.italic && isTitleCase(line.text) && !isCaption(line.text), recordingSubheadings',
     'guard style.bold || false && isTitleCase(line.text) && !isCaption(line.text), recordingSubheadings'),
    ('title case (untagged)', LR, 'style.italic && isTitleCase(line.text) && !isCaption', 'style.italic && true && !isCaption'),
    ('caption guard (untagged)', LR, 'isTitleCase(line.text) && !isCaption(line.text), recordingSubheadings', 'isTitleCase(line.text) && true, recordingSubheadings'),
    ('not italic beneath (untagged)', LR, ': !LabelStyle(below, body: body).italic\n', ': true\n'),
    ('list beneath (untagged)', LR, '&& (paragraph && !isList(below.text) || opensListBeneath(below, title: line, body: body))',
     '&& (paragraph && !isList(below.text))'),
    ('list beneath (tagged)', LR, '|| opensListBeneath(below, title: line, body: body) else { return false }', 'else { return false }'),
    ('list depth bound', LR, 'indent >= -body * 0.5 && indent <= body * 2.5', 'indent >= -body * 0.5 && indent <= body * 100'),
    ('mnemonic not a formula', LR, '&& !isLetterMnemonic(line)', '&& true'),
    ('mnemonic needs bold', LR, 'LabelStyle(line, body: line.fontSize).bold\n', 'true\n'),
    ('lone folio recorded', FD, "guard isFolio || inward.min().map({ $0 >= separation }) == true else { return }",
     "guard let gap = inward.min(), isFolio || gap >= separation else { return }"),
    ('blank folio page emptied', FD, "guard !kept.isEmpty || removed.isSubset(of: plan.bareFolios[pageIndex] ?? []) else { return nil }",
     "guard !kept.isEmpty else { return nil }"),
    ('only bare folios empty a page', FD, "removed.isSubset(of: plan.bareFolios[pageIndex] ?? [])", "true"),
    ('lettered contents folio', LR, r"|(?:\d{1,3}|[a-z])[-–]\d{1,4})?\s*$", r")?\s*$"),
]
only = sys.argv[1:]
for name, path, old, new in mutations:
    if only and name not in only:
        continue
    source = open(f'{W}/{path}').read()
    assert source.count(old) == 1, (name, source.count(old))
    open(f'{W}/{path}', 'w').write(source.replace(old, new))
    try:
        out = subprocess.run(['swift', 'test', '--filter', 'FAAHeadingLeftovers|TaggedSplitsAndTitles|HeadingPlacement|Furniture|NavigationHeading'],
                             cwd=W, capture_output=True, text=True).stdout
        failed = sorted(set(re.findall(r'✘ Test (\w+)\(\) failed', out)))
        summary = re.findall(r'Test run with .*', out)
        errors = [l for l in out.splitlines() if 'error:' in l][:3]
        print(f'{name}: {"FAILS " + ", ".join(failed) if failed else "NOT CAUGHT"} {summary[-1] if summary else errors}', flush=True)
    finally:
        shutil.copy(f'{S}/{path.split("/")[-1]}', f'{W}/{path}')
