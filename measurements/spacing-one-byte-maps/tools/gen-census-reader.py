#!/usr/bin/env python3
"""usage: gen-census-reader.py <NativeSpacingReader.swift> <out.swift>

Derives CensusSpacingReader, an instrumented copy of NativeSpacingReader whose page-invalidating
assignments record the first reason as `<operator or check>@<source line>`. Operator loops
(`for op in [...]`) are unrolled into one registration per operator so each is named. Behaviour
is otherwise identical.
"""
import re, sys

source = open(sys.argv[1]).read().splitlines()
numbered = list(enumerate(source, 1))
expanded = []  # (original line number, context, text)
i = 0
context = '?'
while i < len(numbered):
    number, line = numbered[i]
    loop = re.match(r'(\s*)for op in \[(.*)\] \{\s*$', line)
    if loop:
        indent = loop.group(1)
        ops = re.findall(r'"((?:\\"|[^"])+)"', loop.group(2))
        body = []
        i += 1
        while not re.match(indent + r'\}\s*$', numbered[i][1]):
            body.append(numbered[i]); i += 1
        for op in ops:
            literal = '"' + op + '"'
            for bnumber, bline in body:
                expanded.append((bnumber, op.replace('\\', ''), bline.replace('(table, op)', f'(table, {literal})')[len(indent) - len(indent):]))
        i += 1
        continue
    marker = re.search(r'CGPDFOperatorTableSetCallback\(table, "([^"]+)"\)', line)
    if marker:
        context = marker.group(1)
    elif re.search(r'func show\(', line):
        context = 'show'
    elif re.search(r'func accept\(', line):
        context = 'operationBound'
    expanded.append((number, context, line))
    i += 1

out = []
for number, context, line in expanded:
    tag = f'{context}@{number}'.replace('"', 'dquote')
    line = line.replace('Self.state(info).invalid = true', f'Self.state(info).fail("{tag}")')
    line = line.replace('s.invalid = true', f's.fail("{tag}")')
    line = re.sub(r'(?<![.\w])invalid = true', f'fail("{tag}")', line)
    out.append(line)
text = '\n'.join(out) + '\n'
text = text.replace('enum NativeSpacingReader {', 'enum CensusSpacingReader {\n    nonisolated(unsafe) static var lastReason: String? = nil', 1)
text = text.replace('        var invalid = false\n',
                    '        var invalid = false\n        var reason: String?\n'
                    '        func fail(_ value: String) { if reason == nil { reason = value }; invalid = true }\n', 1)
old = '        guard CGPDFScannerScan(scanner), !s.invalid, s.saved.isEmpty, !s.inText else { return [] }\n'
assert old in text
text = text.replace(old,
    '        let scanned = CGPDFScannerScan(scanner)\n'
    '        CensusSpacingReader.lastReason = s.reason ?? (!scanned ? "scanFailed" : !s.saved.isEmpty ? "unbalancedq" : s.inText ? "unclosedBT" : nil)\n'
    '        guard scanned, !s.invalid, s.saved.isEmpty, !s.inText else { return [] }\n')
old = '        guard page.rotationAngle == 0, hasSupportedFont(page), let table = CGPDFOperatorTableCreate() else { return [] }\n'
assert old in text
text = text.replace(old, '        CensusSpacingReader.lastReason = page.rotationAngle != 0 ? "rotated" : !hasSupportedFont(page) ? "noSupportedFont" : nil\n' + old)
if '--accept-textless-gs' in sys.argv[3:]:
    # Experiment only: an ExtGState without a Font entry changes no text state this reader models.
    pattern = re.compile(r'CGPDFOperatorTableSetCallback\(table, "gs"\) \{ _, info in Self\.state\(info\)\.fail\("gs@\d+"\) \}')
    assert pattern.search(text)
    text = pattern.sub(lambda _: '''CGPDFOperatorTableSetCallback(table, "gs") { scanner, info in
                let s = Self.state(info)
                var name: UnsafePointer<CChar>?, dict: CGPDFDictionaryRef?, font: CGPDFObjectRef?
                guard s.accept(scanner), CGPDFScannerPopName(scanner, &name), let name,
                      let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "ExtGState", name),
                      CGPDFObjectGetValue(object, .dictionary, &dict), let dict else { s.fail("gsUnresolved"); return }
                if CGPDFDictionaryGetObject(dict, "Font", &font) { s.fail("gsFont") }
            }''', text)
leftover =[l for l in text.splitlines() if 'invalid = true' in l and 'func fail' not in l]
assert not leftover, leftover
open(sys.argv[2], 'w').write(text)
