"""Single-guard mutations for #117. usage: mutate.py <first> <last> (inclusive indices)."""
import re
import subprocess
import sys

W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a5c85a3e7f625e901'
S = W + '/Sources/PDFReflowLib/'
FILTER = 'IllustratedPageTests|TitlesAndProseInCropsTests|DGABulletsAndContentsFolioTests|FigureCropBoundsTests|TableCaptionTests|RuledTablesAndHeaderRulesTests|ImageBackedStructureTests|TintedBoxTests|ColumnCutTests'

M = [
    ('invisible-text guard', 'PDFReflowLibPipeline.swift', 'guard !graphics.hasInvisibleText,\n', 'guard true,\n'),
    ('single-paint guard', 'PDFReflowLibPipeline.swift',
     '!graphics.paints.contains(where: { $0.rect.width * $0.rect.height > pageArea * 0.75 }) else { return false }',
     'true else { return false }'),
    ('page-sized crop guard', 'PDFReflowLibPipeline.swift',
     'guard !crops.contains(where: { $0.width * $0.height > pageArea * 0.75 }) else { return false }', ''),
    ('word-share guard', 'PDFReflowLibPipeline.swift',
     'return words(content.lines.filter { line in crops.contains { $0.intersects(line.rect) } }) * 10 <= words(content.lines)',
     'return true'),
    ('exemption off (baseline decision)', 'PDFReflowLibPipeline.swift',
     'static func layoutComesApart(_ content: PageContent, graphics: GraphicsReader.Result) -> Bool {\n',
     'static func layoutComesApart(_ content: PageContent, graphics: GraphicsReader.Result) -> Bool {\n        if true { return false }\n'),
    ('image flag', 'GraphicsReader.swift', 's.add(shown, image: true)', 's.add(shown)'),
    ('shape fill requirement', 'TintDetector.swift', '!$0.image && $0.filled && !isThin($0.rect) }.map(\\.rect)', '!$0.image && !isThin($0.rect) }.map(\\.rect)'),
    ('shape holds only text', 'TintDetector.swift',
     'guard !finite.contains(where: { $0.rect != shape && shape.contains($0.rect) }) else { continue }', ''),
    ('shape backdrops off', 'TintDetector.swift', '        return boxes + tabs\n', '        return []\n'),
    ('tabs off', 'TintDetector.swift', '        return boxes + tabs\n', '        return boxes\n'),
    ('connector rule off', 'TintDetector.swift', 'if escaped.count >= 2 { dropped += rules }', 'if false { dropped += rules }'),
    ('connector clearance', 'TintDetector.swift',
     'if !lines.contains(where: { rule.insetBy(dx: -body * 2, dy: -body * 2).intersects($0.rect) }) { return true }',
     'if true { return true }'),
    ('escaped count 2 -> 1', 'TintDetector.swift', 'if escaped.count >= 2 { dropped += rules }', 'if escaped.count >= 1 { dropped += rules }'),
    ('underline branch off', 'TintDetector.swift', 'return rule.width > rule.height && touched.count == 1', 'return false && touched.count == 1'),
    ('title backdrops off', 'TintDetector.swift', '        guard !removed.isEmpty else { return paints }', '        guard false else { return paints }'),
    ('title backdrop frame exclusion', 'TintDetector.swift', 'usable(paints[$0]) && !paints[$0].frame && !isThin', 'usable(paints[$0]) && !isThin'),
    ('title backdrop box containment', 'TintDetector.swift',
     'guard !paints.indices.contains(where: { !row.contains($0) && paints[$0].rect.insetBy(dx: -2, dy: -2).contains(hull) }),',
     'guard true,'),
    ('stacked title at cluster level', 'LayoutReconstructor.swift', 'stacked allowStacked: Bool = false', 'stacked allowStacked: Bool = true'),
    ('stacked title off', 'TintDetector.swift', 'in: lines, body: body, stacked: true)', 'in: lines, body: body)'),
    ('one-title block test', 'LayoutReconstructor.swift', '        guard oneTitle, allowStacked', '        guard true, allowStacked'),
    ('icon reading rect off', 'LayoutReconstructor.swift',
     'images.map { Element(rect: readingRect(ofRegion: $0.0), image: $0.1) }', 'images.map { Element(rect: $0.0, image: $0.1) }'),
    ('icon distance guard', 'LayoutReconstructor.swift', '&& line.rect.minX - rect.maxX <= body * 2', ''),
    ('icon height guard', 'LayoutReconstructor.swift', '&& rect.height <= line.rect.height * 3', ''),
    ('trailing heading icons', 'LayoutReconstructor.swift',
     'guard (1...2).contains(headings.count), headings.count + icons.count == tail.count else { return nil }',
     'guard (1...2).contains(headings.count), headings.count == tail.count else { return nil }'),
]

first, last = int(sys.argv[1]), int(sys.argv[2])
for i in range(first, last + 1):
    name, file, old, new = M[i]
    path = S + file
    original = open(path).read()
    assert original.count(old) == 1, (name, original.count(old))
    open(path, 'w').write(original.replace(old, new))
    try:
        run = subprocess.run(['swift', 'test', '--filter', FILTER], cwd=W, capture_output=True, text=True, timeout=560)
        out = run.stdout + run.stderr
        failed = sorted(set(re.findall(r'✘ Test (\w+)\(', out)))
        summary = re.findall(r'Test run with .*', out)
        if 'error:' in out and not summary:
            print(f'{i:2} {name}: BUILD ERROR', [l for l in out.splitlines() if 'error:' in l][:3])
        else:
            print(f'{i:2} {name}: {"KILLED" if failed else "SURVIVED"} {failed} {summary[-1] if summary else ""}')
    finally:
        open(path, 'w').write(original)
    sys.stdout.flush()
