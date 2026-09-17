"""mutate.py [index...]: disable each part of #100/#102 in the negctl copy, run the new tests, restore."""
import re, subprocess, sys
N = '/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue100/negctl'
F = f'{N}/Sources/PDFReflowLib/LayoutReconstructor.swift'
MUTATIONS = [
    ('box titles wired into labels', '            + boxTitles(in: free.map(untagged), page: page)', ''),
    ('box title space beneath', 'guard gap >= leading + size * 0.25,', 'guard true,'),
    ('box title line beneath on its edge', 'guard (title + [below]).allSatisfy({', 'guard (title).allSatisfy({'),
    ('box title ending before a marker', 'let last = lastCharacterBeforeMarker(title[count - 1]), !".,;:".contains(last),', 'let last = lastCharacterBeforeMarker(title[count - 1]),'),
    ('box title measure', 'title.allSatisfy({ $0.rect.width <= measure + size * 0.5 }),', 'title.allSatisfy({ $0.rect.width <= stack[count].rect.width + size * 0.5 }),'),
    ('box title two-line leading', 'zip(title, title.dropFirst()).allSatisfy({ $0.rect.minY - $1.rect.maxY <= leading + size * 0.1 }),', ''),
    ('pair branch', '                labels += [line, second]\n', '                _ = second\n'),
    ('pair needs book style', 'guard styles.contains(style), let second = nearestBelow(line)', 'guard let second = nearestBelow(line)'),
    ('pair one style', 'LabelStyle(second, body: body) == style,', ''),
    ('pair stacks', 'stacksUnderHeading(second, after: line), !opensHeading(second.text),', '!opensHeading(second.text),'),
    ('pair second line edge', 'abs(second.rect.minX - line.rect.minX) <= body * 0.5, second.rect.width <= prose * 0.9,', 'second.rect.width <= prose * 0.9,'),
    ('pair sentence end', 'let end = second.text.last, !".,;:".contains(end) else { continue }', 'let end = second.text.last else { continue }'),
    ('pair italic title case', 'guard !style.italic || isTitleCase(text) && !isCaption(text), opens(beneath: second)', 'guard opens(beneath: second)'),
    ('pair list line', '!isList(second.text), !isContentsEntry(line.text)', '!isContentsEntry(line.text)'),
    ('contents entries seed no formula', 'line.text.count < 160, !isContentsEntry(line.text) else { return false }', 'line.text.count < 160 else { return false }'),
]
original = open(F).read()
picks = list(map(int, sys.argv[1:])) or range(len(MUTATIONS))
try:
    for i in picks:
        name, old, new = MUTATIONS[i]
        assert original.count(old) == 1, f'{name}: {original.count(old)} matches'
        open(F, 'w').write(original.replace(old, new))
        out = subprocess.run(['swift', 'test', '--filter', 'BoxTitlesAndTwoLineSubheadsTests'], cwd=N, capture_output=True, text=True).stdout
        failed = sorted(set(re.findall(r'✘ Test (\w+)\(\) failed', out)))
        built = 'Test run' in out
        print(f'{i:2} {name}: built={built} failing={failed}', flush=True)
finally:
    open(F, 'w').write(original)
