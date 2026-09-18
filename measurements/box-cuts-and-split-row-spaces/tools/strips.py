#!/usr/bin/env python3
# usage: strips.py <pdf> <out-dir> <tsv of page\tline\ttext> : renders a 200-dpi strip of each line
# (PDFKit rectangle, located by diag-cand with the line's first words) and prints the product text.
import sys, subprocess, re, os
pdf, out, listing = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
box = subprocess.run(['pdfinfo', '-f', '1', '-l', '1', '-box', pdf], capture_output=True, text=True).stdout
for n, row in enumerate(open(listing)):
    page, index, text = row.rstrip('\n').split('\t')[:3]
    info = subprocess.run(['pdfinfo', '-f', page, '-l', page, '-box', pdf], capture_output=True, text=True).stdout
    height = float(re.search(rf'Page\s+{page} CropBox:\s+\S+\s+\S+\s+\S+\s+(\S+)', info).group(1))
    needle = text.replace(' ', '')[:12]
    diag = subprocess.run(['/private/tmp/claude-501/i177/diag/diag-cand', pdf, page, text.split(' ')[0]],
                          capture_output=True, text=True).stdout
    rect = None
    for line in diag.splitlines():
        m = re.match(r'LINE \d+ \(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\) "(.*)"$', line)
        if m and m.group(5).replace(' ', '').startswith(needle[:6]):
            x, y, w, h = map(float, m.groups()[:4])
            rect = (x, y, w, h)
            break
    if not rect:
        print(n, page, 'NOT FOUND', text)
        continue
    x, y, w, h = rect
    scale = 200 / 72
    left = max(0, int((x - 30) * scale)); top = max(0, int((height - (y + h) - 6) * scale))
    subprocess.run(['pdftoppm', '-r', '200', '-f', page, '-l', page, '-x', str(left), '-y', str(top),
                    '-W', str(int((w + 60) * scale)), '-H', str(int((h + 12) * scale)), '-png', '-singlefile',
                    pdf, f'{out}/{n:02d}-p{page}'])
    print(n, page, text)
