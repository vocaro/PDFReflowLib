"""Restore the pre-#107 vocabulary carry in place, for the negative control.

Not part of the package. Run it from the repository root against the library source, run the
suite, then restore the file:

    cp Sources/PDFReflowLib/LayoutReconstructor.swift /tmp/LayoutReconstructor.swift.keep
    python3 measurements/cross-page-fragments/negative-stub.py Sources/PDFReflowLib/LayoutReconstructor.swift
    swift test
    cp /tmp/LayoutReconstructor.swift.keep Sources/PDFReflowLib/LayoutReconstructor.swift

The stub puts back exactly what #148 left: one `previous`, tested against every line and assigned
by every line at or after the page's first body-sized line.
"""
import sys

path = sys.argv[1]
source = open(path).read()

skip_new = '''            if opensBrokenWord(after: above, line: line, first: words.first)
                || (!reachedStream && opensBrokenWord(after: carried, line: line, first: words.first)) {
                words.removeFirst()
            }'''
skip_old = '''            if opensBrokenWord(after: previous, line: line, first: words.first) {
                words.removeFirst()
            }'''
assert skip_new in source, "skip block not found"
source = source.replace(skip_new, skip_old)

carry_new = '''            above = line.text + (endsShortOfMeasure(line, measures: measures) ? "-" : "")
            if inStream {
                reachedStream = true
                lastInStream = above
            }
        }
        // A page with no text stream of its own — a plate, a full-page table — carries the word on.
        if let lastInStream { previous = lastInStream }'''
carry_old = '''            above = line.text + (endsShortOfMeasure(line, measures: measures) ? "-" : "")
            _ = inStream
            if abs(line.fontSize - body) <= body * 0.15 { reachedStream = true }
            if reachedStream { previous = above }
        }
        _ = (carried, lastInStream)'''
assert carry_new in source, "carry block not found"
source = source.replace(carry_new, carry_old)

open(path, 'w').write(source)
print("stubbed")
