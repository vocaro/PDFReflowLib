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
SUITES = ('AcademicSectionTitleTests|HangingEntryTests|NumberLedParagraphTests|HeadingTests|'
          'TaggedSplitsAndTitlesTests|ListContinuationTests|CitationContinuationTests|'
          'PageContinuationTests|FAAHeadingLeftoversTests|BoxTitlesAndTwoLineSubheadsTests')

TITLES = 'static func academicSectionTitles(in lines: [TextLine], body: CGFloat, page: PageContent) -> [TextLine] {'
RUN = 'static func hangingRun(in lines: [TextLine], edge: CGFloat, indent: CGFloat, size: CGFloat) -> Bool {'
CENTRED = ('if line.text.filter(\\.isLetter).allSatisfy(\\.isUppercase), !LabelStyle(line, body: body).bold,\n'
           '               opensWithRomanNumeral(line.text) || isUnnumberedSectionHead(line.text),\n'
           '               isCentred(line, in: measure), spacedAbove, opensText() {')
SUBSECTION = 'guard line.text.range(of: "^[A-Z]\\\\.\\\\s+\\\\p{Lu}", options: .regularExpression) != nil,'
CONTINUES = ('if let previous = titles.last, previous == above,\n'
             '               continuesCentredTitle(line, after: previous) || stacksUnderHeading(line, after: previous),')
HANGING = ('let hangingEntry = line.rect.minX - prev.rect.minX >= body * 1.5\n'
           '                && line.rect.minX - prev.rect.minX <= body * 4')
WORDS = 'isWordy(prev.text) || hangingEntry && wordShare(prev.text).words >= 3'
ITALIC = 'abs(line.fontSize - body) <= body * 0.1, LabelStyle(line, body: body).italic,'

MUTATIONS = [
    ('no academic section titles at all', TITLES, TITLES + '\n        if true { return [] }'),
    ('no centred section titles', CENTRED, CENTRED.replace('if line.text', 'if false, line.text')),
    ('every centred line of capitals is a title', CENTRED,
     CENTRED.replace('opensWithRomanNumeral(line.text) || isUnnumberedSectionHead(line.text),\n               ', '')),
    ('a bold label is a centred title', CENTRED, CENTRED.replace('!LabelStyle(line, body: body).bold,', '')),
    ('a centred title needs no text beneath it', CENTRED, CENTRED.replace(', opensText()', '')),
    ('no italic subsection titles', SUBSECTION, SUBSECTION + '\n                  false,'),
    ('a subsection title needs no italic', ITALIC,
     'abs(line.fontSize - body) <= body * 0.1, true || LabelStyle(line, body: body).italic,'),
    ('a title’s next line never continues it', CONTINUES, CONTINUES.replace('if let previous', 'if false, let previous')),
    ('no hanging run', RUN, RUN + '\n        if true { return false }'),
    ('any indent is a hanging run', RUN, RUN + '\n        if true { return true }'),
    ('the hanging indent stays within three bodies', HANGING, HANGING.replace('body * 4', 'body * 3')),
    ('an entry’s first line must read as words', WORDS, 'isWordy(prev.text)'),
]


def run() -> list[str]:
    result = subprocess.run(['swift', 'test', '--filter', SUITES], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if 'error:' in output and 'Test run' not in output:
        return ['BUILD FAILED: ' + '; '.join(re.findall(r'error: .*', output)[:2])]
    return sorted({match for match in re.findall(r'Test (\w+)\(\) recorded an issue', output)})


def main() -> int:
    original = open(SOURCE).read()
    rows = []
    try:
        for name, before, after in MUTATIONS:
            if original.count(before) != 1:
                rows.append((name, [f'ANCHOR NOT UNIQUE ({original.count(before)})']))
                continue
            open(SOURCE, 'w').write(original.replace(before, after, 1))
            rows.append((name, run()))
    finally:
        open(SOURCE, 'w').write(original)
    for name, failures in rows:
        print(f'| {name} | ' + (', '.join(f'`{test}`' for test in failures) or 'NONE') + ' |')
    return 0 if all(failures for _, failures in rows) else 1


if __name__ == '__main__':
    sys.exit(main())
