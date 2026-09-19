#!/usr/bin/env python3
"""Fail when Swift code reads PDFKit text, makes a font or draws text outside the extraction gate.

PDFKit's attributed-text extraction can abort with `setObject:forKey: object cannot be nil (key:
NSFont)` while another thread of the same process reads PDFKit text, makes or releases fonts, or
lays out text with CoreText (#21). The library serializes its own extraction through
`NativeTextReader.withExtractionLock`, and tests make their fonts, CoreText drawings and PDFKit
reads through `pdfKitGated` (Tests/PDFReflowLibTests/PDFKitGate.swift), which holds the same lock.
Parallel tests share a process with the library's extraction, so an ungated fixture font is enough.

A call counts as gated when it sits lexically inside one of those closures. A `private` or nested
function holding an ungated call passes it to its callers in the same file, until a caller holds
it inside a gate; the call is reported where it reaches a function other files can call, or code
outside any function. The check is lexical, so it can be fooled (a call through a stored closure),
but every call the repository makes today is written in one of the forms it reads.

usage: check_pdfkit_gate.py   (prints each violation; exit 1 when there is one)
"""
import re
import sys

from pdfreflow_tools.corpus import ROOT

SCANNED = ['Sources', 'Tests']
GATES = ('withExtractionLock', 'pdfKitGated')

# PDFKit text reads (PDFSelection/PDFPage), font construction, and CoreText layout or drawing.
CALLS = [
    ('PDFKit attributed text', r'\.attributedString\b(?!\s*\()'),
    ('PDFKit line selections', r'\bselectionsByLine\s*\('),
    ('PDFKit selection', r'\.selection\s*\(\s*(?:for|from)\b'),
    ('PDFKit selection', r'\bselectionForEntireDocument\b'),
    ('PDFKit character geometry', r'\.(?:characterBounds|characterIndex)\s*\(\s*at\b'),
    ('PDFKit character count', r'\.numberOfCharacters\b'),
    ('PDFKit search', r'\.findString\s*\('),
    ('PDFKit page text', r'\b(?:page|pdfPage|document)\??\.string\b'),
    ('font construction', r'\b[A-Z]\w*Font\s*\(\s*name:[^()]*\bsize:'),
    ('font construction', r'\b(?:NSFont|UIFont)\s*\(\s*descriptor:'),
    ('font construction', r'\.(?:systemFont|boldSystemFont|monospacedSystemFont|monospacedDigitSystemFont)\s*\('),
    ('font construction', r'\.withSize\s*\('),
    ('CoreText font', r'\bCTFontCreate\w*\s*\('),
    ('CoreText layout', r'\b(?:CTLineCreate|CTLineDraw|CTFramesetter|CTFrameDraw|CTTypesetter)\w*\s*\('),
]
PATTERN = re.compile('|'.join(f'(?:{p})' for _, p in CALLS))


def blank_code(text):
    """The text with comments and string literals replaced by spaces, keeping every offset."""
    out = list(text)
    i, n = 0, len(text)

    def blank(start, end):
        for k in range(start, end):
            if out[k] != '\n':
                out[k] = ' '
    while i < n:
        if text.startswith('//', i):
            end = text.find('\n', i)
            end = n if end < 0 else end
            blank(i, end)
            i = end
        elif text.startswith('/*', i):
            depth, j = 1, i + 2
            while j < n and depth:
                if text.startswith('/*', j):
                    depth, j = depth + 1, j + 2
                elif text.startswith('*/', j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            blank(i, j)
            i = j
        elif text[i] == '"' or (text[i] == '#' and re.match(r'#+"', text[i:])):
            hashes = len(re.match(r'#*', text[i:]).group())
            j = i + hashes
            quote = '"""' if text.startswith('"""', j) else '"'
            close = quote + '#' * hashes
            j += len(quote)
            while j < n and not text.startswith(close, j):
                j += 2 if text[j] == '\\' and not hashes else 1
            j = min(n, j + len(close))
            blank(i, j)
            i = j
        else:
            i += 1
    return ''.join(out)


def matching_brace(code, start):
    """The offset just past the brace closing the one at `start`."""
    depth = 0
    for k in range(start, len(code)):
        if code[k] == '{':
            depth += 1
        elif code[k] == '}':
            depth -= 1
            if depth == 0:
                return k + 1
    return len(code)


def gate_spans(code):
    spans = []
    for match in re.finditer(r'\b(?:%s)\s*(?:\(\s*)?\{' % '|'.join(GATES), code):
        brace = match.end() - 1
        spans.append((brace, matching_brace(code, brace)))
    return spans


def functions(code):
    """(name, body start, body end, private) for each function with a body, outermost first."""
    found = []
    for match in re.finditer(r'\bfunc\s+(\w+)', code):
        depth, k = 0, match.end()
        while k < len(code):
            c = code[k]
            if c in '([<':
                depth += 1
            elif c in ')]>' and depth:
                depth -= 1
            elif c == '{' and depth == 0:
                break
            elif c == '}' and depth == 0 or code.startswith('func ', k):
                k = None
                break
            k += 1
        if k is None or k >= len(code):
            continue
        line_start = code.rfind('\n', 0, match.start()) + 1
        modifiers = code[line_start:match.start()]
        found.append({'name': match.group(1), 'start': k, 'end': matching_brace(code, k),
                      'private': bool(re.search(r'\b(?:private|fileprivate)\b', modifiers))})
    for f in found:
        f['parent'] = next((p for p in reversed(found)
                            if p is not f and p['start'] < f['start'] and f['end'] <= p['end']), None)
    return found


def references(code, name, start, end):
    """Offsets calling `name` in code[start:end]: bare, or through `Self.` or a type name."""
    for match in re.finditer(r'\b%s\s*\(' % re.escape(name), code[start:end]):
        at = start + match.start()
        before = code[:at].rstrip(' ')
        if before.endswith('.'):
            owner = re.search(r'(\w+)\s*\.$', before)
            if not owner or not owner.group(1)[0].isupper():
                continue
        elif re.search(r'\bfunc\s*$', before):
            continue
        yield at


def violations_in(text, path='<source>'):
    code = blank_code(text)
    spans = gate_spans(code)
    funcs = functions(code)

    def gated(at):
        return any(s < at < e for s, e in spans)

    def innermost(at):
        inside = [f for f in funcs if f['start'] < at < f['end']]
        return inside[-1] if inside else None

    def line(at):
        return code.count('\n', 0, at) + 1

    found = []
    tainted = {}  # id(function) -> (what, first line) for private and nested functions
    pending = []
    for match in PATTERN.finditer(code):
        if gated(match.start()):
            continue
        what = next(label for label, p in CALLS if re.match(p, code[match.start():]))
        pending.append((match.start(), f'{what} `{match.group().strip()}`', line(match.start())))
    while pending:
        at, what, origin = pending.pop()
        holder = innermost(at)
        if holder is None or not (holder['private'] or holder['parent']):
            where = f"in `{holder['name']}`" if holder else 'outside any function'
            found.append(f'{path}:{origin}: {what} {where}, outside the extraction gate')
            continue
        if id(holder) in tainted:
            continue
        tainted[id(holder)] = True
        scope = holder['parent'] or {'start': 0, 'end': len(code)}
        for ref in references(code, holder['name'], scope['start'], scope['end']):
            if not gated(ref) and not holder['start'] < ref < holder['end']:
                pending.append((ref, f"{what} via `{holder['name']}`", origin))
    return sorted(set(found))


def violations(root=ROOT):
    found = []
    for folder in SCANNED:
        for path in sorted((root / folder).rglob('*.swift')):
            found += violations_in(path.read_text(), path.relative_to(root))
    return found


def main():
    found = violations()
    for v in found:
        print(v)
    if found:
        print(f'{len(found)} PDFKit text, font or CoreText calls outside the extraction gate (#21).')
    return int(bool(found))


if __name__ == '__main__':
    sys.exit(main())
