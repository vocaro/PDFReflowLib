import os, re, subprocess
import numpy as np
from PIL import Image
D = os.path.dirname(os.path.abspath(__file__))
pdf = '/Users/trevorharmon/Development/PDFReflowLib/corpus/cache/jresv82n3p173_A1b.pdf'
for p in range(1, 7):
    subprocess.run(['pdftoppm', '-r', '144', '-f', str(p), '-l', str(p), '-gray', '-png', pdf, f'{D}/pop'], capture_output=True)
    pop = np.asarray(Image.open(f'{D}/pop-{p}.png').convert('L')).astype(int)
    cg = np.asarray(Image.open(f'{D}/cg-{p}.png').convert('L')).astype(int)
    h = min(pop.shape[0], cg.shape[0]); w = min(pop.shape[1], cg.shape[1])
    pop, cg = pop[:h, :w], cg[:h, :w]
    t = subprocess.run(['mutool', 'trace', pdf, str(p)], capture_output=True, text=True).stdout
    out = []
    for m in re.finditer(r'<fill_image_mask transform="([^"]+)"', t):
        a, _, _, dd, e, f = map(float, m.group(1).split())
        y0, y1, x0, x1 = int(f * 2), int((f + dd) * 2), int(e * 2), int((e + a) * 2)
        c = cg[y0:y1, x0:x1]; q = pop[y0:y1, x0:x1]
        out.append(f'{(c < 128).mean():.2f}/{(q < 128).mean():.2f}')
    print(p, 'dark fraction CG/Poppler per box:', ' '.join(out), '| page mean abs diff', round(float(np.abs(cg - pop).mean()), 2))
