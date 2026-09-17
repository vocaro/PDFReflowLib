#!/usr/bin/env python3
"""usage: make-anchors.py <repo> <out.swift>  derive MarkedAnchors.swift from MarkedTextReader.swift for survey.swift.

The copy runs the reader's own content-stream scan and records every show origin with its MCID
(and the MCIDs shown from unknown origins) instead of associating lines; nothing else changes."""
import sys
s = open(sys.argv[1] + '/Sources/PDFReflowLib/MarkedTextReader.swift').read()
s = s.replace('enum MarkedTextReader {', 'enum MarkedAnchors {\n    nonisolated(unsafe) static var lastAnchors: [(CGPoint, Int?)] = []\n'
              '    nonisolated(unsafe) static var lastUnknown: Set<Int> = []\n    nonisolated(unsafe) static var lastInvalid = false', 1)
old = '        guard CGPDFScannerScan(scanner), !s.invalid, s.marks.isEmpty, s.saved.isEmpty, !s.inText else { return false }'
assert old in s
s = s.replace(old, '        let ok = CGPDFScannerScan(scanner)\n        lastAnchors = s.anchors.map { ($0.point, $0.id) }; '
              'lastUnknown = s.unknownOrigins; lastInvalid = !ok || s.invalid || !s.marks.isEmpty\n        return false\n' + old)
s = s.replace('guard !tags.isEmpty else { return true }', '')
open(sys.argv[2], 'w').write(s)
