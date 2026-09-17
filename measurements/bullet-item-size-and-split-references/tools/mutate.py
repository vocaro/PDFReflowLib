#!/usr/bin/env python3
"""usage: mutate.py  — apply each negative mutation to the two changed sources, run the suites
that should catch it, restore the files and report the failing tests.

Run from the repository root. Every source is restored from an in-memory copy after each
mutation, including on failure.
"""
import re
import subprocess
import sys

READER = 'Sources/PDFReflowLib/NativeTextReader.swift'
LAYOUT = 'Sources/PDFReflowLib/LayoutReconstructor.swift'
SUITES = ('BulletItemSizeAndSplitReferencesTests|SplitRowsAndLostHyphensTests|'
          'RowPiecesAndSpacedParagraphTests|AcademicSectionTitleTests|ListContinuationTests|'
          'ListBulletsAndCodedReportsTests|MarkerPieceTests|TallRowsAndMinusTests')

SIZE = 'static func bulletItemBodySize(in attributed: NSAttributedString) -> CGFloat? {'
SMALLER = 'guard let body = size, body > cap.pointSize + 0.05,'
SUBSTANTIAL = 'guard itemText.filter(\\.isLetter).count >= 15,'
SPACE = 'func stretchedWordSpace(_ left: TextLine, _ right: TextLine, size: CGFloat) -> Bool {'
EVIDENCE = 'guard left.trailingSpace, gap > 0, gap <= size * 2,'
ORDINARY = '[left, right].allSatisfy({ abs($0.rect.height - ordinary) <= ordinary * 0.15 }) else { return false }'
MEASURE = '&& sharedEdge(right.rect.maxX, \\.maxX, besides: [left, right], atLeast: 3)'
UNSHARED = 'return !sharedEdge(left.rect.maxX, \\.maxX, besides: [left, right])'
NESTED = 'guard !listLine(line) || isLonely(line), !opensRepeatedDashItem(line),'

MUTATIONS = [
    ('no bullet-item size at all', READER, SIZE, SIZE + '\n        if true { return nil }'),
    ('a bullet of any size restates its line', READER, SMALLER, 'guard let body = size,'),
    ('a marker before any text at all is an item', READER, SUBSTANTIAL, 'guard true ||'),
    ('no stretched word space', LAYOUT, SPACE, SPACE + '\n            if true { return false }'),
    ('the word space PDFKit kept is not required', LAYOUT, EVIDENCE, 'guard gap > 0, gap <= size * 2,'),
    ('a junction of any width is a word space', LAYOUT, EVIDENCE, 'guard left.trailingSpace, gap > 0,'),
    ('a split row need not stand in an ordinary line', LAYOUT, ORDINARY,
     '[left, right].allSatisfy({ _ in true }) else { return false }'),
    ('a split row need not reach its measure', LAYOUT, MEASURE, '&& true'),
    ('the left piece may end on an edge the page shares', LAYOUT, UNSHARED, 'return true'),
    ('a nested dash item wraps into its bullet', LAYOUT, NESTED,
     'guard !listLine(line) || isLonely(line),'),
]


def run() -> list[str]:
    result = subprocess.run(['swift', 'test', '--filter', SUITES], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if 'error:' in output and 'Test run' not in output:
        return ['BUILD FAILED: ' + '; '.join(re.findall(r'error: .*', output)[:2])]
    return sorted({match for match in re.findall(r'Test (\w+)\(\) recorded an issue', output)})


def main() -> int:
    originals = {path: open(path).read() for path in (READER, LAYOUT)}
    rows = []
    try:
        for name, path, before, after in MUTATIONS:
            source = originals[path]
            if source.count(before) != 1:
                rows.append((name, [f'ANCHOR NOT UNIQUE ({source.count(before)})']))
                continue
            open(path, 'w').write(source.replace(before, after, 1))
            rows.append((name, run()))
            open(path, 'w').write(source)
    finally:
        for path, source in originals.items():
            open(path, 'w').write(source)
    for name, failures in rows:
        print(f'| {name} | ' + (', '.join(f'`{test}`' for test in failures) or 'NONE') + ' |')
    return 0 if all(failures for _, failures in rows) else 1


if __name__ == '__main__':
    sys.exit(main())
