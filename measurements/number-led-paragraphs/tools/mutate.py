#!/usr/bin/env python3
"""usage: mutate.py  — apply each negative mutation to LayoutReconstructor, run the suites that
should catch it, restore the file and report the failing tests.

Run from the repository root. The source file is restored from an in-memory copy after every
mutation, including on failure.
"""
import re
import subprocess
import sys

SOURCE = 'Sources/PDFReflowLib/LayoutReconstructor.swift'
SUITES = ('NumberLedParagraphTests|CitationContinuationTests|ListContinuationTests|'
          'ListBulletsAndCodedReportsTests|AcademicFrontMatterTests|PageContinuationTests|'
          'ExerciseNumberingTests|NumberedNoteTests|HeadingTests|StructureTests')

MUTATIONS = [
    ('the sequence and shared-edge rules reverted together',
     'func isLonely(_ line: TextLine) -> Bool {\n            guard let marker = ListMarker(line.text) else { return false }',
     'func isLonely(_ line: TextLine) -> Bool {\n            if true { return false }\n            guard let marker = ListMarker(line.text) else { return false }',
     'let right = column.map(\\.rect.maxX).filter { $0 >= furthest - body * 0.5 }.max { a, b in',
     'let right = furthest\n            _ = column.map(\\.rect.maxX).filter { $0 >= furthest - body * 0.5 }.max { a, b in'),
    ('no marker is lonely',
     'func isLonely(_ line: TextLine) -> Bool {\n            guard let marker = ListMarker(line.text) else { return false }',
     'func isLonely(_ line: TextLine) -> Bool {\n            if true { return false }\n            guard let marker = ListMarker(line.text) else { return false }'),
    ('every marker is lonely',
     'func isLonely(_ line: TextLine) -> Bool {\n            guard let marker = ListMarker(line.text) else { return false }',
     'func isLonely(_ line: TextLine) -> Bool {\n            if true { return ListMarker(line.text) != nil }\n            guard let marker = ListMarker(line.text) else { return false }'),
    ('the justified edge is the furthest line',
     'let right = column.map(\\.rect.maxX).filter { $0 >= furthest - body * 0.5 }.max { a, b in',
     'let right = furthest\n            _ = column.map(\\.rect.maxX).filter { $0 >= furthest - body * 0.5 }.max { a, b in'),
    ('a lonely marker never opens a flush paragraph',
     'func runsOnFlush(_ line: TextLine) -> Bool {\n            let closing',
     'func runsOnFlush(_ line: TextLine) -> Bool {\n            if true { return false }\n            let closing'),
    ('every numbered list line is a title',
     'guard let range = line.text.range(of: "^[0-9]{1,2}\\\\.\\\\s+", options: .regularExpression),',
     'if true { return line.text.range(of: "^[0-9]", options: .regularExpression) != nil }\n        guard let range = line.text.range(of: "^[0-9]{1,2}\\\\.\\\\s+", options: .regularExpression),'),
    ('no numbered title is a label',
     'static func isNumberedTitle(_ line: TextLine, body: CGFloat) -> Bool {',
     'static func isNumberedTitle(_ line: TextLine, body: CGFloat) -> Bool {\n        if true { return false }'),
    ('heading tags are always taken literally',
     'for index in indices { elements[index].line?.structure?.headingLevel = 0 }',
     'if false { for index in indices { elements[index].line?.structure?.headingLevel = 0 } }'),
    ('any heading tag over a sentence is demoted',
     'guard !page.hasSyntheticTextStyle, lines.allSatisfy({ $0.fontSize <= reflowBody * 1.05\n                      && paragraphTypes.contains(LabelStyle($0, body: reflowBody)) }),',
     'guard !page.hasSyntheticTextStyle,',
    ),
]


def run() -> list[str]:
    result = subprocess.run(['swift', 'test', '--filter', SUITES], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if 'error:' in output and 'Test run' not in output:
        return ['BUILD FAILED: ' + '; '.join(re.findall(r'error: .*', output)[:2])]
    return sorted({match for match in re.findall(r'Test (\w+)\(\) recorded an issue', output)})


def main() -> int:
    original = open(SOURCE).read()
    status = 0
    try:
        for name, *edits in MUTATIONS:
            text = original
            for old, new in zip(edits[::2], edits[1::2]):
                if old not in text:
                    print(f'{name}: PATTERN NOT FOUND')
                    status = 1
                    text = original
                    break
                text = text.replace(old, new, 1)
            if text == original:
                continue
            open(SOURCE, 'w').write(text)
            failures = run()
            print(f'| {name} | {", ".join(f"`{f}`" for f in failures) or "NONE — mutation survived"} |')
            if not failures:
                status = 1
    finally:
        open(SOURCE, 'w').write(original)
    return status


sys.exit(main())
