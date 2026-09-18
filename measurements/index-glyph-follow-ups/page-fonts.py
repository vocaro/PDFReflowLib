"""Per page of the Census report, the fonts its content stream selects and how many shows each draws,
and for each embedded CFF (FontFile3) program its FullName, FamilyName and glyph names (#149).

    python3 measurements/index-glyph-follow-ups/page-fonts.py corpus/cache/rrs2002-01.pdf

Standard library only. Reads the file's uncompressed object layout (Distiller 4.05, PDF 1.3: no object
streams), which is all this survey needs; it is not a general PDF parser.
"""
import re
import struct
import sys
import zlib

data = open(sys.argv[1], 'rb').read()
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


def reference(dictionary, key):
    match = re.search(rb'/' + key + rb'\s*(\d+) 0 R', dictionary)
    return int(match.group(1)) if match else None


pages = []
for number in sorted(offsets):
    kids = re.search(rb'/Type\s*/Pages\b.*?/Kids\s*\[(.*?)\]', body(number), re.S)
    if kids and b'/Parent' not in body(number):
        pending = [int(k) for k in re.findall(rb'(\d+) 0 R', kids.group(1))]
        while pending:
            node = pending.pop(0)
            inner = re.search(rb'/Kids\s*\[(.*?)\]', body(node), re.S)
            if inner and b'/Type /Pages' in body(node):
                pending = [int(k) for k in re.findall(rb'(\d+) 0 R', inner.group(1))] + pending
            else:
                pages.append(node)

programs = {}
for index, page in enumerate(pages, 1):
    resources_ref = reference(body(page), b'Resources')
    resources = body(resources_ref) if resources_ref else body(page)
    fonts_ref = reference(resources, b'Font')
    fonts = body(fonts_ref) if fonts_ref else re.search(rb'/Font\s*<<(.*?)>>', resources, re.S).group(1)
    names = {}
    for match in re.finditer(rb'/(\w+)\s+(\d+) 0 R', fonts):
        font = body(int(match.group(2)))
        base = re.search(rb'/BaseFont\s*/([\w+]+)', font)
        names[match.group(1).decode()] = base.group(1).decode().split('+')[-1] if base else 'Type3'
        descriptor = reference(font, b'FontDescriptor')
        program = descriptor and reference(body(descriptor), b'FontFile3')
        if program:
            programs[names[match.group(1).decode()]] = program
    counts, current = {}, None
    contents = re.search(rb'/Contents\s*(\[[^\]]*\]|\d+ 0 R)', body(page)).group(1)
    content = b'\n'.join(stream(int(n)) for n in re.findall(rb'(\d+) 0 R', contents))
    for match in re.finditer(rb'/(\w+)\s+[\d.]+\s+Tf|(TJ|Tj)\b', content):
        if match.group(1):
            current = names.get(match.group(1).decode(), '?')
        elif current:
            counts[current] = counts.get(current, 0) + 1
    print(f'page {index}: ' + ', '.join(f'{name} {count}' for name, count in sorted(counts.items())))


def index(buffer, position):
    count = struct.unpack('>H', buffer[position:position + 2])[0]
    if count == 0:
        return [], position + 2
    size, position = buffer[position + 2], position + 3
    marks = []
    for _ in range(count + 1):
        marks.append(int.from_bytes(buffer[position:position + size], 'big'))
        position += size
    base = position - 1
    return [buffer[base + marks[i]:base + marks[i + 1]] for i in range(count)], base + marks[-1]


def operands(buffer):
    result, values, position = {}, [], 0
    while position < len(buffer):
        byte = buffer[position]
        if byte <= 21:
            key = 1200 + buffer[position + 1] if byte == 12 else byte
            position += 2 if byte == 12 else 1
            result[key], values = values, []
        elif byte == 28:
            values.append(struct.unpack('>h', buffer[position + 1:position + 3])[0]); position += 3
        elif byte == 29:
            values.append(struct.unpack('>i', buffer[position + 1:position + 5])[0]); position += 5
        elif byte == 30:
            position += 1
            while buffer[position] & 0x0F != 0x0F and buffer[position] >> 4 != 0x0F:
                position += 1
            position += 1
            values.append(0)
        elif byte <= 246:
            values.append(byte - 139); position += 1
        elif byte <= 250:
            values.append((byte - 247) * 256 + buffer[position + 1] + 108); position += 2
        else:
            values.append(-(byte - 251) * 256 - buffer[position + 1] - 108); position += 2
    return result


for name, number in sorted(programs.items()):
    cff = stream(number)
    position = cff[2]
    _, position = index(cff, position)
    tops, position = index(cff, position)
    strings, position = index(cff, position)
    top = operands(tops[0])

    def sid(value):
        return strings[value - 391].decode('latin-1') if value >= 391 else f'<standard {value}>'

    glyphs = sorted({s.decode('latin-1') for s in strings if re.fullmatch(rb'G\d+', s)}, key=lambda g: int(g[1:]))
    print(f'{name}: FullName {sid(top[2][0]) if 2 in top else None}, FamilyName {sid(top[3][0]) if 3 in top else None}, '
          f'{len(glyphs)} glyph names: {" ".join(glyphs)}')
