#!/usr/bin/env python3
"""Survey-only instrumentation for #148/#157. Not part of the library.

Run from the repository root to add five stderr logs to `LayoutReconstructor`, guarded by the
`PDFREFLOW_ROW_LOG` environment variable, then build a release CLI and convert with that variable
set. Each line is one decision this work added:

    ROWJOIN          a row PDFKit split outside mathematics, with each piece's rectangle
    BOXJOIN          two halves of a word a box or figure was read between
    PAGEJOIN         a cross-page anchor line that does not read as prose (the candidates the
                     word-break clause is asked about; only a real break joins)
    LOSTHYPHEN       a line-end hyphen restored from the column's measure
    SPACEDCOMPOUND   a line whose mid-line `x- y` closed up, as the source set it

`--revert` takes the logs out again.
"""
import sys

PATH = 'Sources/PDFReflowLib/LayoutReconstructor.swift'
GUARD = 'ProcessInfo.processInfo.environment["PDFREFLOW_ROW_LOG"] != nil'
EDITS = [
    ("""            if opensWithMathMinus { mathMinusRows.append(joined) }""",
     """            if opensWithMathMinus { mathMinusRows.append(joined) }
            if !math, %s {
                let shape = pieces.map { "[\\(lines[$0].rect.minX),\\(lines[$0].rect.maxX),\\(lines[$0].fontSize)]" }
                FileHandle.standardError.write(("ROWJOIN\\t" + shape.joined(separator: " ") + "\\t"
                    + pieces.map { lines[$0].text }.joined(separator: " ||| ") + "\\n").data(using: .utf8)!)
            }""" % GUARD),
    ("""            blocks.remove(at: next)""",
     """            if next > index + 1, %s {
                FileHandle.standardError.write(("BOXJOIN\\t\\(page.number)\\t"
                    + left.text.suffix(60) + " ||| " + right.text.prefix(60) + "\\n").data(using: .utf8)!)
            }
            blocks.remove(at: next)""" % GUARD),
    ("""              readsAsProse(last.text) || continuesWordBreak(last.text, first.text, vocabulary: vocabulary),""",
     """              readsAsProse(last.text) || {
                  if %s {
                      FileHandle.standardError.write(("PAGEJOIN\\t\\(page.number)\\t" + last.text.suffix(60)
                          + " ||| " + first.text.prefix(50) + "\\n").data(using: .utf8)!)
                  }
                  return continuesWordBreak(last.text, first.text, vocabulary: vocabulary)
              }(),""" % GUARD),
    ("""                        paragraph.append(line.content)""",
     """                        if %s {
                            FileHandle.standardError.write(("LOSTHYPHEN\\t\\(page.number)\\t"
                                + prev.text.suffix(40) + " ||| " + line.text.prefix(40) + "\\n").data(using: .utf8)!)
                        }
                        paragraph.append(line.content)""" % GUARD),
    ("""            if changed { page.lines[index].replaceContent(InlineText(elements: elements)) }""",
     """            if changed {
                if %s {
                    FileHandle.standardError.write(("SPACEDCOMPOUND\\t\\(page.number)\\t"
                        + page.lines[index].text + "\\n").data(using: .utf8)!)
                }
                page.lines[index].replaceContent(InlineText(elements: elements))
            }""" % GUARD),
]

revert = '--revert' in sys.argv
text = open(PATH).read()
for plain, logged in EDITS:
    old, new = (logged, plain) if revert else (plain, logged)
    if old not in text:
        sys.exit(f'not found: {old.strip()[:60]}')
    text = text.replace(old, new, 1)
open(PATH, 'w').write(text)
print('reverted' if revert else 'instrumented')
