#!/usr/bin/env python3
"""Single-guard mutations of this change: each must fail at least one test.

usage: mutate.py <first> <last> [log]   (run from the worktree root; restores the source after each)
"""
import re
import subprocess
import sys
from pathlib import Path

SOURCE = Path('Sources/PDFReflowLib/LayoutReconstructor.swift')
FILTER = ('titleShadow|sectionBands|pageTitleOver|titleArtRequires|wrappedSentence|sentenceBeneath|formulaMargin|'
          'columnContinuation|dgaOlderAdultsReadsEachColumnWhole')

MUTANTS = [
    ('shadow: no coverage test', 'covered >= area(rect) * 0.6', 'true'),
    ('shadow: no extent bound', 'hull.insetBy(dx: -size, dy: -size).contains(rect)', 'true'),
    ('shadow: any line may touch', 'if grazed, hull', 'if true, hull'),
    ('title: any type size', 'line.fontSize >= body * 1.25', 'true'),
    ('band: other lines may touch', 'guard titles.count == 1, others.isEmpty,', 'guard titles.count == 1,'),
    ('band: any height', 'rect.height <= title.rect.height * 2,', ''),
    ('band: dropped instead of trimmed', 'guard let band = kept, band.width >= rect.height else', 'guard let band = kept, false else'),
    ('wrapped end: rule off', '&& !continuesSentenceAbove(line, in: page.lines, body: body)', ''),
    ('wrapped end: line above may close its sentence', '!".!?:;".contains(ending),', ''),
    ('wrapped end: opening term allowed', 'opening.count >= 3, opening.first?.isLowercase == true,\n              opening.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else { return false }',
     'true else { return false }'),
    ('sentence row: rule off', 'return isSentenceRow(line, in: lines) || isProseRow', 'return isProseRow'),
    ('sentence row: operators allowed', '&& readsAsSentence(text) && text.rangeOfCharacter(from: rowMathSymbols) == nil && !text.contains("=")',
     '&& readsAsSentence(text)'),
    ('sentence row: no capital or full stop needed', 'text.first?.isUppercase == true && text.last == "." && ', ''),
    ('column join: rule off', 'guard let left = joinableText(blocks[index].content) else { continue }',
     'guard false, let left = joinableText(blocks[index].content) else { continue }'),
    ('column join: uppercase continuation', 'guard right.text.first?.isLowercase == true, !endsSentence(left),\n              let last = lastLine(of: left.text, in: page.lines),\n              let first = firstLine(of: right.text, in: page.lines),\n              wordCount',
     'guard !endsSentence(left),\n              let last = lastLine(of: left.text, in: page.lines),\n              let first = firstLine(of: right.text, in: page.lines),\n              wordCount'),
    ('column join: closed sentence', 'guard right.text.first?.isLowercase == true, !endsSentence(left),\n              let last = lastLine(of: left.text, in: page.lines),\n              let first = firstLine(of: right.text, in: page.lines),\n              wordCount',
     'guard right.text.first?.isLowercase == true,\n              let last = lastLine(of: left.text, in: page.lines),\n              let first = firstLine(of: right.text, in: page.lines),\n              wordCount'),
    ('column join: no fill test', 'fillsColumn(last, in: page.lines, body: body) else { return false }', 'true else { return false }'),
    ('column join: identities ignored', 'leftGroup != rightGroup { return false }', 'false { return false }'),
    ('column join: prose below allowed', 'return below && isProse(other, beside: last, share: 0.5, page: page, images: images)\n                || between', 'return between'),
    ('column join: prose between allowed', '|| between && isProse(other, beside: last, share: 0.9, page: page, images: images)', ''),
    ('column join: prose above allowed', '|| above && isProse(other, beside: first, share: 0.5, page: page, images: images)', ''),
    ('column join: no section ceiling', '.map(\\.minY).min() ?? .infinity', '.map(\\.minY).min().map { _ in CGFloat.infinity } ?? .infinity'),
    ('stacked titles: refinement off', 'if headingTypography(next) {\n                guard let smallest', 'if headingTypography(next) {\n                return nil\n                guard let smallest'),
]


def main():
    first, last = int(sys.argv[1]), int(sys.argv[2])
    log = open(sys.argv[3], 'a') if len(sys.argv) > 3 else sys.stdout
    original = SOURCE.read_text()
    try:
        for index, (name, old, new) in enumerate(MUTANTS[first:last + 1], start=first):
            if original.count(old) != 1:
                print(f'{index} {name}: pattern found {original.count(old)} times', file=log, flush=True)
                continue
            SOURCE.write_text(original.replace(old, new))
            run = subprocess.run(['swift', 'test', '--filter', FILTER], capture_output=True, text=True)
            output = run.stdout + run.stderr
            if 'error:' in output and 'Test run with' not in output:
                print(f'{index} {name}: BUILD FAILED', file=log, flush=True)
                continue
            failed = sorted(set(re.findall(r'✘ Test (\w+)\(', output)))
            summary = re.findall(r'Test run with .*', output)
            verdict = 'killed' if failed else 'SURVIVED'
            print(f'{index} {name}: {verdict} {failed} {summary[-1] if summary else ""}', file=log, flush=True)
    finally:
        SOURCE.write_text(original)


if __name__ == '__main__':
    main()
