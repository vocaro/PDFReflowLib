#!/usr/bin/env python3
"""Recompute the real-output negative and tolerance controls for the region references.

Usage: python3 measurements/image-regions/controls.py <corpus-evaluation-directory>
Reads converted EPUBs from a complete corpus run; writes controls.json beside this script.
"""
import io
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import image_regions  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter  # noqa: E402


def png(image):
    data = io.BytesIO()
    image.save(data, format='PNG')
    return data.getvalue()


def main():
    corpus = Path(sys.argv[1])

    def asset(case, name):
        with zipfile.ZipFile(corpus / case / f'{case}.epub') as archive:
            return archive.read(name)

    def reference(case, name):
        return (ROOT / 'corpus/references' / case / f'{name}.png').read_bytes()

    def score(case, name, data):
        return round(image_regions.region_score(reference(case, name), [data]), 3)

    faa, usgs, flag, algebra = 'faa-phak-8083-25c', 'usgs-mcs2025-copper', 'gpo-our-flag-2003', 'wallace-algebra-2010'
    table = Image.open(io.BytesIO(asset(flag, 'EPUB/images/image-57.png')))
    exercises = Image.open(io.BytesIO(asset(algebra, 'EPUB/images/image-1263.png'))).convert('L')
    erased_row, erased_exponent = exercises.copy(), exercises.copy()
    ImageDraw.Draw(erased_row).rectangle([0, 1170, exercises.width, 1215], fill=255)
    ImageDraw.Draw(erased_exponent).rectangle([380, 1170, 398, 1185], fill=255)
    clipped = Image.new('L', table.size, 255)
    clipped.paste(table.convert('L').crop((0, 0, table.width, table.height // 2)), (0, 0))
    controls = [
        ('wrong image: FAA figure 5-36 reference vs figure 5-35 crop', score(faa, 'page-121-figure-5-36', asset(faa, 'EPUB/images/image-139.png'))),
        ('wrong image: FAA figure 5-36 reference vs figure 5-37 crop', score(faa, 'page-121-figure-5-36', asset(faa, 'EPUB/images/image-141.png'))),
        ('wrong image: FAA figure 5-37 reference vs figure 5-36 crop', score(faa, 'page-121-figure-5-37', asset(faa, 'EPUB/images/image-140.png'))),
        ('wrong image: USGS tariff reference vs prose crop', score(usgs, 'page-1-tariff', asset(usgs, 'EPUB/images/image-1.png'))),
        ('wrong image: USGS tariff reference vs statistics crop', score(usgs, 'page-1-tariff', asset(usgs, 'EPUB/images/image-2.png'))),
        ('clipped: Our Flag table crop with lower half blanked', score(flag, 'page-27-flag-size-table', png(clipped))),
        ('missing equation: Wallace exercise 35 row erased', score(algebra, 'page-347-exercise-35', png(erased_row))),
        ('limitation: Wallace exercise 35 final exponent erased', score(algebra, 'page-347-exercise-35', png(erased_exponent))),
        ('tolerance: Our Flag table crop with 1.5-pixel Gaussian blur', score(flag, 'page-27-flag-size-table', png(table.filter(ImageFilter.GaussianBlur(1.5))))),
    ]
    output = {'threshold': image_regions.DEFAULT_MINIMUM_CORRELATION,
              'controls': [{'control': name, 'score': value} for name, value in controls]}
    Path(__file__).with_name('controls.json').write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps(output, indent=2))


if __name__ == '__main__':
    main()
