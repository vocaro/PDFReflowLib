#!/usr/bin/env python3
"""Eight stubs that restore the pre-#148/#157 behaviour, for the negative-control run.

Run from the repository root, then `swift test`. Restore the sources with git afterwards."""
import sys
lr = 'Sources/PDFReflowLib/LayoutReconstructor.swift'
pl = 'Sources/PDFReflowLib/PDFReflowLibPipeline.swift'

s = open(lr).read()
edits = [
    # 1. `joinedRows`: only a row carrying mathematics rejoins, on the weaker prose reading.
    ("""            guard math || runsOn, !widened || clear,
                  isProseRow(pieces: pieces.map { lines[$0] }, in: lines, body: body, fillingItsMeasure: !math)
            else { continue }""",
     """            guard math, isProseRow(pieces: pieces.map { lines[$0] }, in: lines, body: body) else { continue }"""),
    # 2. `joinedRows`: a piece that opens with a raised marker keeps the marker's size.
    ("""            guard line.fontSize < body * 0.8, raisedNoteNumber(line.content) != nil, let ordinary,
                  abs(line.rect.height - ordinary) <= ordinary * 0.15 else { return line.fontSize }
            return body""",
     """            return line.fontSize"""),
    # 3. `joinedRows`: every junction meets at a space.
    ("""        func closesWithMarker(_ right: Int) -> Bool { !math && raisedNoteNumber(lines[right].content) != nil }""",
     """        func closesWithMarker(_ right: Int) -> Bool { false }"""),
    # 4. `joinWordBreaks`: the halves must be adjacent blocks.
    ("""                if candidate == index + 1 { return true }""",
     """                return candidate == index + 1"""),
    # 5. `continuation`: the anchor line must read as prose.
    ("""              readsAsProse(last.text) || continuesWordBreak(last.text, first.text, vocabulary: vocabulary),""",
     """              readsAsProse(last.text),"""),
    # 6. `lostLineEndHyphen`: no line-end hyphen is ever restored.
    ("""        guard endsShortOfMeasure(last, measures: measures), !next.monospaced,""",
     """        if true { return false }
        guard endsShortOfMeasure(last, measures: measures), !next.monospaced,"""),
    # 7. `closeSpacedCompounds`: no mid-line hyphen closes up.
    ("""            guard page.lines[index].text.contains("- ") else { continue }""",
     """            guard false, page.lines[index].text.contains("- ") else { continue }"""),
    # 8. `addVocabulary`: no word is carried across a page break or a lost hyphen.
    ("""            if reachedBody {
                previous = line.text + (endsShortOfMeasure(line, measures: measures) ? "-" : "")
            }""",
     """            previous = line.text"""),
]
for old, new in edits:
    if old not in s:
        print('MISSING:', old[:70])
        sys.exit(1)
    s = s.replace(old, new, 1)
open(lr, 'w').write(s)

p = open(pl).read()
old = "            LayoutReconstructor.closeSpacedCompounds(&content, vocabulary: vocabulary)\n"
if old not in p:
    print('MISSING pipeline hook')
    sys.exit(1)
open(pl, 'w').write(p.replace(old, "", 1))
print('stubbed')
