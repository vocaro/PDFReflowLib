"""Append an incremental update that marks a tagged PDF's catalog /MarkInfo /Marked false.

The source is not modified; the clone differs only by the appended catalog copy and a
cross-reference stream. Encrypted documents are refused because the catalog's strings would
need re-encryption.
"""
import re, struct, subprocess, sys, pathlib, shutil

def untag(src, dst):
    src, dst = pathlib.Path(src), pathlib.Path(dst)
    data = src.read_bytes()
    trailer = subprocess.run(['mutool', 'show', str(src), 'trailer'], capture_output=True, text=True).stdout
    if '/Encrypt' in trailer:
        return 'encrypted'
    root = int(re.search(r'/Root (\d+) 0 R', trailer).group(1)); size = int(re.search(r'/Size (\d+)', trailer).group(1))
    info = re.search(r'/Info (\d+) 0 R', trailer); ids = re.search(r'/ID \[(.*?)\]', trailer, re.S)
    startxref = int(re.search(rb'startxref\s+(\d+)\s+%%EOF\s*$', data[-300:]).group(1))
    catalog = subprocess.run(['mutool', 'show', str(src), str(root)], capture_output=True, text=True).stdout
    body = re.search(r'obj\s*(<<.*>>)\s*endobj', catalog, re.S).group(1)
    if '/Marked true' not in body:
        return 'not tagged'
    patched = body.replace('/Marked true', '/Marked false')
    out = bytearray(data)
    if not out.endswith(b'\n'): out += b'\n'
    catalog_offset = len(out)
    out += f'{root} 0 obj\n{patched}\nendobj\n'.encode('latin-1')
    xref_num = size; xref_offset = len(out)
    rows = struct.pack('>BQH', 1, catalog_offset, 0) + struct.pack('>BQH', 1, xref_offset, 0)
    extra = (f' /Info {info.group(1)} 0 R' if info else '') + (f' /ID [{ids.group(1).strip()}]' if ids else '')
    out += (f'{xref_num} 0 obj\n<< /Type /XRef /Size {size + 1} /W [1 8 2] /Index [{root} 1 {xref_num} 1] /Root {root} 0 R /Prev {startxref}{extra} /Length {len(rows)} >>\nstream\n').encode('latin-1')
    out += rows + f'\nendstream\nendobj\nstartxref\n{xref_offset}\n%%EOF\n'.encode('latin-1')
    dst.write_bytes(out)
    return f'patched (+{len(out) - len(data)} bytes)'

if __name__ == '__main__':
    print(untag(sys.argv[1], sys.argv[2]))
