"""List single-letter initials set at >= 2x the size of the text that follows them in the same block
(drop-cap candidates), from mutool's structured text. usage: dropcapscan.py <pdf> [first last]"""
import subprocess, sys, re
import xml.etree.ElementTree as ET
pdf = sys.argv[1]
pages = sys.argv[2:4] if len(sys.argv) > 3 else None
count = int(subprocess.run(['qpdf', '--show-npages', pdf], capture_output=True, text=True).stdout)
first, last = (int(pages[0]), int(pages[1])) if pages else (1, count)
hits = 0
for start in range(first, last + 1, 50):
    end = min(last, start + 49)
    out = subprocess.run(['mutool', 'draw', '-F', 'stext', pdf, f'{start}-{end}'], capture_output=True, text=True).stdout
    for page in ET.fromstring(re.sub(r'&#x?[0-9a-fA-F]+;', '?', out[out.index('<document'):])).iter('page'):
        number = page.get('id') or page.get('number')
        runs = []
        for font in page.iter('font'):
            text = ''.join(c.get('c', '') for c in font.iter('char'))
            runs.append((float(font.get('size')), text))
        for i, (size, text) in enumerate(runs[:-1]):
            letters = text.strip()
            if len(letters) == 1 and letters.isalpha() and letters.isupper():
                nsize, ntext = runs[i + 1]
                if size >= 2 * nsize and ntext[:1].islower():
                    hits += 1
                    print(number, repr(letters), size, repr(ntext[:30]), flush=True)
print('hits', hits)
