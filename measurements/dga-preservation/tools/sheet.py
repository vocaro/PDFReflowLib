"""Contact sheet: sheet.py out.png label=path [label=path ...]; each image scaled to max 500 wide."""
import sys
from PIL import Image, ImageDraw

items = [a.split('=', 1) for a in sys.argv[2:]]
tiles = []
for label, path in items:
    im = Image.open(path).convert('RGB')
    scale = min(1.0, 500 / im.width, 300 / im.height)
    im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))))
    tiles.append((label, im))
width = 520
height = sum(im.height + 24 for _, im in tiles) + 10
sheet = Image.new('RGB', (width, height), (200, 200, 200))
draw = ImageDraw.Draw(sheet)
y = 5
for label, im in tiles:
    draw.text((8, y), f'{label} {im.width}x{im.height}', fill=(0, 0, 0))
    sheet.paste(im, (10, y + 14))
    y += im.height + 24
sheet.save(sys.argv[1])
