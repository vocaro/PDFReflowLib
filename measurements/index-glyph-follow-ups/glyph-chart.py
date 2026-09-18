"""A one-page PDF that draws every glyph of one of the Census report's embedded CFF fonts, each labelled
with its `G<n>` name, so the glyph a name stands for can be read off a render (#149).

    python3 measurements/index-glyph-follow-ups/glyph-chart.py corpus/cache/rrs2002-01.pdf cmmi10084 <out.pdf>
    mutool draw -r 110 -o <out.png> <out.pdf> 1

The font program is copied unchanged; the chart's encoding maps codes 1, 2, … to the descriptor's
`CharSet` names in index order, and the labels are set in Helvetica. Standard library only.
"""
import re
import sys
import zlib

source, font_name, output = sys.argv[1:4]
data = open(source, 'rb').read()
offsets = {int(m.group(1)): m.end() for m in re.finditer(rb'(\d+) 0 obj', data)}


def body(number):
    start = offsets[number]
    end, stream = data.find(b'endobj', start), data.find(b'stream', start)
    return data[start:end if stream == -1 or end < stream else stream]


def stream(number):
    start = offsets[number]
    begin = data.index(b'stream', start)
    header, position = data[start:begin], begin + 6
    while data[position] in (10, 13):
        position += 1
    raw = data[position:data.index(b'endstream', position)]
    return zlib.decompress(raw) if b'FlateDecode' in header else raw


descriptor = next(n for n in offsets if re.search(rb'/Type\s*/FontDescriptor', body(n))
                  and re.search(rb'/FontName\s*/\w+\+' + font_name.encode() + rb'\b', body(n)))
program = stream(int(re.search(rb'/FontFile3\s*(\d+) 0 R', body(descriptor)).group(1)))
charset = re.sub(rb'\\\r?\n?', b'', re.search(rb'/CharSet\s*\((.*?)\)', body(descriptor), re.S).group(1))
names = sorted({n.decode() for n in re.findall(rb'/(G\d+)', charset)}, key=lambda n: int(n[1:]))

content = ['BT']
for position, name in enumerate(names):
    x, y = 40 + position % 8 * 70, 730 - position // 8 * 60
    # An octal escape: a literal carriage return in a string reads as a line feed (code 13 as 10).
    content.append(f'/L 8 Tf 1 0 0 1 {x} {y - 22} Tm ({name}) Tj /P 26 Tf 1 0 0 1 {x + 12} {y} Tm (\\{position + 1:03o}) Tj')
content.append('ET')
page = '\n'.join(content).encode('latin-1')
widths = ' '.join(['600'] * len(names))
objects = [
    b'<< /Type /Catalog /Pages 2 0 R >>',
    b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /P 5 0 R /L 6 0 R >> >> /Contents 4 0 R >>',
    b'<< /Length %d >>\nstream\n' % len(page) + page + b'\nendstream',
    (f'<< /Type /Font /Subtype /Type1 /BaseFont /Chart /FirstChar 1 /LastChar {len(names)} /Widths [{widths}] '
     f'/Encoding << /Differences [1 {" ".join("/" + n for n in names)}] >> /FontDescriptor 7 0 R >>').encode(),
    b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    b'<< /Type /FontDescriptor /FontName /Chart /Flags 4 /FontBBox [-100 -300 1200 900] /ItalicAngle 0 '
    b'/Ascent 800 /Descent -200 /CapHeight 700 /StemV 80 /FontFile3 8 0 R >>',
    b'<< /Subtype /Type1C /Length %d >>\nstream\n' % len(program) + program + b'\nendstream',
]
buffer, marks = b'%PDF-1.4\n', []
for number, value in enumerate(objects, 1):
    marks.append(len(buffer))
    buffer += b'%d 0 obj\n' % number + value + b'\nendobj\n'
xref = len(buffer)
buffer += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objects) + 1) + b''.join(b'%010d 00000 n \n' % m for m in marks)
buffer += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objects) + 1, xref)
open(output, 'wb').write(buffer)
print(f'{font_name}: {len(names)} glyphs -> {output}')
