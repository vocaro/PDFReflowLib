"""Whether any glyph of the Census report's undecoded maths fonts has the outline of a glyph the
document's own words establish (#297).

    python3 measurements/census-math-glyph-identity/glyph-outlines.py corpus/cache/rrs2002-01.pdf

Needs `mutool` (MuPDF) on the PATH and fontTools. Every embedded font program here is CFF
(`FontFile3`, `Type1C`) and names its glyphs `G<n>` alone. `GlyphIndexDecoder` establishes the
Cork text fonts (`dcr`, `dcbx`, `dcti`, `dctt`) at `n = code + 3` from the document's own words,
so each of their glyphs has a character. For each glyph of the maths fonts (`cmr`, `cmmi`, `cmsy`,
`cmex`, `cmmib`) this finds the established glyph whose outline is nearest: the two paths must
have the same operators, and the distance is the largest difference between corresponding points
after moving both to their own bounding box's lower left, in font units (1000 to the em). It
prints, per maths font, how many glyphs have an established glyph within 2, 10 and 40 units, and
each nearest match.
"""
import io
import json
import re
import subprocess
import sys

from fontTools.cffLib import CFFFontSet
from fontTools.pens.recordingPen import RecordingPen

source = sys.argv[1]
ESTABLISHED = ('dcr', 'dcbx', 'dcti', 'dctt')
MATHS = ('cmr', 'cmmi', 'cmsy', 'cmex', 'cmmib')
# Cork (T1) printable ASCII and the ligatures the report prints; enough to name a match.
CORK = {code: chr(code) for code in range(33, 127)}
CORK.update({27: 'ff', 28: 'fi', 29: 'fl', 30: 'ffi', 31: 'ffl', 21: '–', 22: '—'})


def show(number, *flags):
    return subprocess.run(['mutool', 'show', *flags, source, str(number)], capture_output=True).stdout


def programs():
    """Every Type1C program in the file, by its font's name without the subset tag."""
    trailer = show('trailer').decode('latin-1')
    count = int(re.search(r'/Size (\d+)', trailer).group(1))
    found = {}
    for number in range(1, count):
        body = show(number).decode('latin-1', 'replace')
        if '/Type /FontDescriptor' not in body or '/FontFile3' not in body:
            continue
        name = re.search(r'/FontName /(?:[A-Z]{6}\+)?(\S+)', body).group(1)
        stream = int(re.search(r'/FontFile3 (\d+) 0 R', body).group(1))
        cff = CFFFontSet()
        cff.decompile(io.BytesIO(show(stream, '-b')), None)
        found[name] = cff[cff.fontNames[0]]
    return found


def outline(font, glyph):
    pen = RecordingPen()
    font.CharStrings[glyph].draw(pen)
    points = [point for _, arguments in pen.value for point in arguments]
    if not points:
        return None
    left = min(x for x, _ in points)
    bottom = min(y for _, y in points)
    return tuple(op for op, _ in pen.value), [(x - left, y - bottom) for x, y in points]


def distance(a, b):
    if a is None or b is None or a[0] != b[0]:
        return None
    return max(max(abs(x1 - x2), abs(y1 - y2)) for (x1, y1), (x2, y2) in zip(a[1], b[1]))


fonts = programs()
established = []
for name, font in fonts.items():
    if name.startswith(ESTABLISHED):
        for glyph in font.charset:
            match = re.fullmatch(r'G(\d+)', glyph)
            if match:
                code = int(match.group(1)) - 3
                established.append((name, glyph, CORK.get(code, f'<{code}>'), outline(font, glyph)))
for name, font in sorted(fonts.items()):
    if not name.startswith(MATHS):
        continue
    nearest = []
    for glyph in font.charset:
        if glyph == '.notdef':
            continue
        mine = outline(font, glyph)
        best = min(((distance(mine, other[3]), other) for other in established
                    if distance(mine, other[3]) is not None), default=(None, None), key=lambda pair: pair[0])
        nearest.append({'glyph': glyph, 'operators': len(mine[0]) if mine else 0,
                        'nearest': f'{best[1][0]} {best[1][1]} {best[1][2]!r}' if best[1] else None,
                        'distance': round(best[0], 1) if best[0] is not None else None})
    within = {limit: sum(1 for n in nearest if n['distance'] is not None and n['distance'] <= limit)
              for limit in (2, 10, 40)}
    print(json.dumps({'font': name, 'glyphs': len(nearest), 'withSameOperators': sum(1 for n in nearest if n['distance'] is not None),
                      'within2': within[2], 'within10': within[10], 'within40': within[40]}))
    for entry in nearest:
        print('   ', json.dumps(entry, ensure_ascii=False))
