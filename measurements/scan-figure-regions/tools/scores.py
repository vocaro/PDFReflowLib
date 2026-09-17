import io, os, sys
from PIL import Image
W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a11a7ffaa3ea102c4'
sys.path.insert(0, W + '/tools')
import image_regions
D = os.path.dirname(os.path.abspath(__file__))
R = W + '/corpus/references/nbs-jres-geltman-1977/'
pages = {1: f'{D}/nbs/x/EPUB/images/image-4.png', 2: f'{D}/nbs/x/EPUB/images/image-12.png', 3: f'{D}/nbs/x/EPUB/images/image-20.png'}

def png(image):
    buffer = io.BytesIO(); image.save(buffer, 'PNG'); return buffer.getvalue()

def page_crop(page, box):  # box in points on the 180 DPI (2.5 px/pt) page reference
    image = Image.open(pages[page])
    return png(image.crop(tuple(round(v * 2.5) for v in box)))

cases = [
    ('page-2-figure-1', 2, 'p2-figure1', [('evidence strip 0 only', (131.5, 117.1, 162.2, 179.5)),
                                          ('five evidence boxes span, no top', (131.5, 117.1, 324.5, 186.2)),
                                          ('left half of figure', (128, 42, 276, 192))]),
    ('page-3-figure-2', 3, 'p3-figure2', [('plot evidence box only', (40.3, 148.7, 251.5, 319.6)),
                                          ('top-axis strip only', (42.2, 124.7, 248.7, 136.2))]),
    ('page-1-equation-4', 1, 'p1-eq4', [('equation without number', (298, 658, 470, 686))]),
    ('page-2-equation-11', 2, 'p2-eq11', [('left evidence box only', (289.9, 617.3, 327.4, 638.4)),
                                          ('right evidence box only', (377.3, 615.4, 516.5, 651.8))]),
    ('page-3-equation-15', 3, 'p3-eq15', [('first line box only', (266.9, 214.0, 378.3, 238.0))]),
]
for reference, page, crop, wrong in cases:
    data = open(R + reference + '.png', 'rb').read()
    right = image_regions.region_score(data, [open(f'{D}/crops/{crop}.png', 'rb').read()])
    whole = image_regions.region_score(data, [open(pages[page], 'rb').read()])
    print(f'{reference}: converter crop {right:.3f}; source-page reference image {whole:.3f}')
    for label, box in wrong:
        print(f'    {label}: {image_regions.region_score(data, [page_crop(page, box)]):.3f}')
