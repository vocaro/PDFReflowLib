#!/usr/bin/env python3
"""usage: mutate.py  apply each #165 negative-control mutation to the sources in turn, run
SlideDeckTests plus the neighbouring furniture, heading and navigation suites, and restore the
files.

Run from the repository root. Prints the failing tests for each mutation."""
import re, subprocess, sys
from pathlib import Path

LAYOUT = Path('Sources/PDFReflowLib/LayoutReconstructor.swift')
FURNITURE = Path('Sources/PDFReflowLib/FurnitureDetector.swift')
NATIVE = Path('Sources/PDFReflowLib/NativeTextReader.swift')
FILTER = 'SlideDeckTests|FurnitureTests|HeadingTests|NavigationHeadingTests|NumberLedParagraphTests'
MUTATIONS = {
    'no slide titles': (LAYOUT,
        '    static func slideTitle(in lines: [TextLine], bounds: CGRect) -> [TextLine] {\n',
        '    static func slideTitle(in lines: [TextLine], bounds: CGRect) -> [TextLine] {\n        if true { return [] }\n'),
    'a title anywhere on the page': (LAYOUT,
        'bounds.maxY - first.rect.maxY <= bounds.height * 0.125,',
        'bounds.maxY - first.rect.maxY <= bounds.height * 10,'),
    'no clearance under the title': (LAYOUT,
        'if let highest = below.map(\\.rect.maxY).max(), bottom - highest < first.rect.height * 0.5 { return [] }',
        'if false, let highest = below.map(\\.rect.maxY).max(), bottom - highest < first.rect.height * 0.5 { return [] }'),
    'a slide of any length': (LAYOUT,
        'page.lines.reduce(0, { $0 + $1.text.count }) <= 600 else { return false }',
        'page.lines.reduce(0, { $0 + $1.text.count }) <= 6_000_000 else { return false }'),
    'the slide body can be a heading': (LAYOUT,
        'if line.fontSize < title.fontSize * 0.95 { return false }',
        'if false { return false }'),
    'a deck ranks by size': (LAYOUT,
        'let ranked: (CGFloat) -> Int = slideDeck ? { _ in 2 } : byTier',
        'let ranked: (CGFloat) -> Int = byTier'),
    'a repeated note is furniture': (FURNITURE,
        'guard let number = LayoutReconstructor.raisedNoteNumber(page.lines[lineIndex]) else { return false }',
        'if true { return false }\n        guard let number = LayoutReconstructor.raisedNoteNumber(page.lines[lineIndex]) else { return false }'),
    'overprinted lines are kept': (NATIVE,
        '        guard lines.count > 1 else { return lines }',
        '        if true { return lines }\n        guard lines.count > 1 else { return lines }'),
    'any repeat of a word is an overprint': (NATIVE,
        '                    && abs(other.rect.minX - line.rect.minX) <= 0.05 && abs(other.rect.minY - line.rect.minY) <= 0.05',
        '                    && abs(other.rect.minX - line.rect.minX) <= 500 && abs(other.rect.minY - line.rect.minY) <= 500'),
}
originals = {path: path.read_text() for path in (LAYOUT, FURNITURE, NATIVE)}
try:
    for name, (path, old, new) in MUTATIONS.items():
        assert originals[path].count(old) == 1, name
        path.write_text(originals[path].replace(old, new))
        run = subprocess.run(['swift', 'test', '--filter', FILTER], capture_output=True, text=True)
        failing = sorted(set(re.findall(r'✘ Test (\w+)\(', run.stdout + run.stderr)))
        if not failing and 'error:' in run.stderr:
            failing = ['(did not build)']
        print(f'{name}: {", ".join(failing) or "NO FAILURES"}')
        sys.stdout.flush()
        path.write_text(originals[path])
finally:
    for path, text in originals.items():
        path.write_text(text)
