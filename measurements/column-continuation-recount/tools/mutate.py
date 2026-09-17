#!/usr/bin/env python3
"""Single-rule and single-guard mutations of this change; each must fail at least one test.

usage: mutate.py <first> <last> [--log path]   (indices into MUTANTS; run from the worktree root)
The source is restored after every mutant, including on interruption.
"""
import re
import subprocess
import sys
from pathlib import Path

LAYOUT = Path('Sources/PDFReflowLib/LayoutReconstructor.swift')
FILTER = 'ColumnContinuationRecount|TitlesAndProseInCrops|PageContinuation|ColumnCut'

MUTANTS = [
    # Rules switched off: the pre-change behavior for each class.
    ('rule: wrapped caption lines compete', 'if other.fontSize < line.fontSize * 0.95 {', 'if false {'),
    ('rule: no next-line join', 'if nextLineInColumn(last, first, page: page, body: body) { return true }', ''),
    ('rule: no head below a column-head figure', 'first.rect.midY > last.rect.midY || headedByFigure && sameSize',
     'first.rect.midY > last.rect.midY'),
    ('rule: lowercase openings only', 'if opening.isLowercase { return true }', 'guard opening.isLowercase else { return false }; return true'),
    ('rule: no figure-page skipping', 'pageBlocks.contains { if case .image = $0.content { true } else { false } }',
     'false && pageBlocks.contains { if case .image = $0.content { true } else { false } }'),
    ('rule: ceiling at the crossing element bottom', 'let ceiling = lowest?.maxY ?? .infinity', 'let ceiling = lowest?.minY ?? .infinity'),
    # Guards removed one at a time.
    ('guard: caption excuse only below anchor size', 'if other.fontSize < line.fontSize * 0.95 {', 'if true {'),
    ('guard: next line same size', 'guard Int(first.fontSize.rounded()) == Int(last.fontSize.rounded()),\n              abs(',
     'guard abs('),
    ('guard: next line same edge', 'abs(first.rect.minX - last.rect.minX) <= body * 0.5,', 'true,'),
    ('guard: next line below', 'first.rect.maxY <= last.rect.minY + last.rect.height * 0.25,', 'true,'),
    ('guard: next line pitch', 'pitch <= max(last.rect.height, first.rect.height) * 1.5 else', 'true else'),
    ('guard: no line between', 'other != last && other != first && other.rect.midY < last.rect.midY && other.rect.midY > first.rect.midY',
     'false && other.rect.midY > first.rect.midY'),
    ('guard: head-below needs same size', 'first.rect.midY > last.rect.midY || headedByFigure && sameSize',
     'first.rect.midY > last.rect.midY || headedByFigure'),
    ('guard: head figure reaches above foot', '&& $0.minY >= first.rect.maxY - body * 0.5 && $0.maxY > last.rect.midY',
     '&& $0.minY >= first.rect.maxY - body * 0.5'),
    ('guard: head figure above head', '&& $0.minY >= first.rect.maxY - body * 0.5', ''),
    ('guard: same-page opening same size', 'sameSize && opensOnAFullLine(first, in: page.lines, body: body)',
     'opensOnAFullLine(first, in: page.lines, body: body)'),
    ('guard: same-page opening full line', 'sameSize && opensOnAFullLine(first, in: page.lines, body: body)', 'sameSize'),
    ('guard: cross-page opening full line', '\n                && opensOnAFullLine(first, in: page.lines, body: max(4, bodySize(page.lines)))', ''),
    ('guard: cross-page opening same size',
     '|| Int(first.fontSize.rounded()) == Int(last.fontSize.rounded())\n                && opensOnAFullLine',
     '|| opensOnAFullLine'),
    ('guard: short line must close sentence', 'fillsColumn(first, in: lines, body: body) || endsSentence(InlineText(first.text))',
     'fillsColumn(first, in: lines, body: body)'),
    ('guard: open words only', 'return openWords.contains(word.lowercased())', 'return true'),
    ('guard: possessive stem', 'return stem.count >= 2 && stem.allSatisfy(\\.isLetter)', 'return stem.count >= 1'),
    ('guard: crossing element itself excused', ', other.rect != lowest else', ' else'),
    ('guard: skipped page holds no prose', 'return skippedPage.page.lines.contains {', 'return false && skippedPage.page.lines.contains {'),
    ('guard: figure page needs an image', 'pageBlocks.contains { if case .image = $0.content { true } else { false } }\n            && ', ''),
    ('guard: skipped page markers inline', 'right.elements.insert(contentsOf: (skipped.dropFirst() + [page.number]).map { .sourcePage($0) }, at: 0)',
     'right.elements.insert(contentsOf: [InlineText.Element.sourcePage(page.number)], at: 0)'),
]


def run(index, log):
    name, old, new = MUTANTS[index]
    source = LAYOUT.read_text()
    if source.count(old) != 1:
        print(f'{index} {name}: pattern found {source.count(old)} times', file=log, flush=True)
        return None
    try:
        LAYOUT.write_text(source.replace(old, new))
        result = subprocess.run(['swift', 'test', '--filter', FILTER], capture_output=True, text=True)
        output = result.stdout + result.stderr
        failed = sorted(set(re.findall(r'✘ Test (\w+)\(', output)))
        built = 'error:' not in output or failed
        verdict = 'killed' if failed else ('BUILD ERROR' if not built else 'SURVIVED')
        print(f'{index} {name}: {verdict} {failed}', file=log, flush=True)
        return bool(failed)
    finally:
        LAYOUT.write_text(source)


if __name__ == '__main__':
    first, last = int(sys.argv[1]), int(sys.argv[2])
    log = open(sys.argv[sys.argv.index('--log') + 1], 'a') if '--log' in sys.argv else sys.stdout
    for index in range(first, min(last, len(MUTANTS) - 1) + 1):
        run(index, log)
        if log is not sys.stdout:
            print(open(sys.argv[sys.argv.index('--log') + 1]).read().splitlines()[-1])
