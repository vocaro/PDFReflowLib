#!/usr/bin/env python3
"""Recompute the table row/column and colour controls for the region references.

Usage: python3 measurements/image-regions/cell-controls.py <corpus-evaluation-directory>
Reads converted EPUBs from a complete corpus run; writes cell-controls.json beside this script.
Every mutation is applied to the converted image, so each control answers what the check would
say about a real defect in a preserved crop.
"""
import io
import json
from pathlib import Path
import sys
import zipfile

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
import image_regions  # noqa: E402
from check_corpus_content import read_spine  # noqa: E402


def png(pixels, mode='L'):
    data = io.BytesIO()
    Image.fromarray(pixels.astype('uint8'), mode=mode).save(data, format='PNG')
    return data.getvalue()


def grey(data):
    with Image.open(io.BytesIO(data)) as image:
        return np.asarray(image.convert('L'), dtype='uint8').copy()


def swapped(data, first, second):
    """Exchange two equally sized (left, top, width, height) boxes inside a converted image."""
    pixels = grey(data)
    box = lambda b: (slice(b[1], b[1] + b[3]), slice(b[0], b[0] + b[2]))
    a, b = pixels[box(first)].copy(), pixels[box(second)].copy()
    pixels[box(first)], pixels[box(second)] = b, a
    return png(pixels)


def blanked(data, region):
    pixels = grey(data)
    pixels[region[1]:region[1] + region[3], region[0]:region[0] + region[2]] = 255
    return png(pixels)


def complemented(data):
    """Keep CIE lightness and invert the chroma axes: same greys, different colours."""
    with Image.open(io.BytesIO(data)) as image:
        lab = np.asarray(image.convert('RGB').convert('LAB'), dtype='int16').copy()
    lab[:, :, 1] = 255 - lab[:, :, 1]
    lab[:, :, 2] = 255 - lab[:, :, 2]
    return png(np.asarray(Image.fromarray(lab.clip(0, 255).astype('uint8'), mode='LAB')
                          .convert('RGB')), mode='RGB')


def main():
    corpus = Path(sys.argv[1])
    usgs, flag, cdc = 'usgs-mcs2025-copper', 'gpo-our-flag-2003', 'cdc-zombie-pandemic-2011'
    controls = []

    def images(case, page):
        path = corpus / case / f'{case}.epub'
        pages, _, _ = read_spine(path)
        with zipfile.ZipFile(path) as archive:
            return [archive.read(asset) for asset in pages[page]['images']]

    def score(case, name, candidates):
        reference = (ROOT / 'corpus/references' / case / f'{name}.png').read_bytes()
        return round(image_regions.region_score(reference, candidates), 3)

    def record(case, page, names, label, mutate=None, index=None):
        candidates = images(case, page)
        if mutate is not None:
            candidates = [mutate(data) if position == index else data
                          for position, data in enumerate(candidates)]
        for name in names:
            controls.append({'case': case, 'page': page, 'reference': name, 'control': label,
                             'score': score(case, name, candidates)})

    # The Salient Statistics crop is the second image on USGS page 1; rows and year columns are
    # located by its own ink bands, so the boxes below are that crop's pixels at 180 DPI.
    usgs_names = ['page-1-salient-statistics', 'page-1-row-mine-recoverable',
                  'page-1-row-london-metal-exchange', 'page-1-column-2022']
    mine_2022, mine_2023 = (1000, 66, 82, 27), (1104, 66, 82, 27)
    london_2020, london_2021 = (791, 533, 84, 28), (896, 533, 84, 28)
    london_2022, producer_2022 = (1000, 533, 84, 28), (1000, 478, 84, 28)
    record(usgs, 1, usgs_names, 'correct output')
    record(usgs, 1, usgs_names, 'Mine, recoverable row: 2022 and 2023 cells exchanged',
           lambda data: swapped(data, mine_2022, mine_2023), 1)
    record(usgs, 1, usgs_names, 'Mine, recoverable row: 2022 cell erased',
           lambda data: blanked(data, mine_2022), 1)
    record(usgs, 1, usgs_names, 'London Metal Exchange row: 2020 and 2021 cells exchanged',
           lambda data: swapped(data, london_2020, london_2021), 1)
    record(usgs, 1, usgs_names, '2022 column: London and U.S. producer values exchanged',
           lambda data: swapped(data, london_2022, producer_2022), 1)
    record(usgs, 1, usgs_names, 'London Metal Exchange row erased',
           lambda data: blanked(data, (5, 533, 1286, 28)), 1)

    flag_names = ['page-27-flag-size-table', 'page-27-row-125-foot-pole',
                  'page-27-row-250-foot-pole', 'page-27-column-flagpole-heights']
    size_125, size_250 = (320, 250, 90, 22), (320, 308, 90, 22)
    height_125, height_250 = (0, 250, 60, 22), (0, 308, 60, 22)
    record(flag, 27, flag_names, 'correct output')
    record(flag, 27, flag_names, 'flag sizes of the 125- and 250-foot rows exchanged',
           lambda data: swapped(data, size_125, size_250), 2)
    record(flag, 27, flag_names, 'pole heights of the 125- and 250-foot rows exchanged',
           lambda data: swapped(data, height_125, height_250), 2)
    record(flag, 27, flag_names, '125-foot row erased',
           lambda data: blanked(data, (0, 250, 415, 22)), 2)
    record(flag, 27, flag_names, '125-foot flag size erased',
           lambda data: blanked(data, size_125), 2)

    # Colour: the reference is grayscale and converted images are reduced to grayscale, so a
    # lightness-preserving recolouring of a full-colour page is invisible to the check.
    original = images(cdc, 13)[0]
    mutated = complemented(original)
    before = np.asarray(Image.open(io.BytesIO(original)).convert('RGB'), dtype='int16')
    after = np.asarray(Image.open(io.BytesIO(mutated)).convert('RGB'), dtype='int16')
    difference = np.abs(before - after).max(axis=2)
    record(cdc, 13, ['page-13-page'], 'correct output')
    record(cdc, 13, ['page-13-page'], 'complementary chroma at unchanged lightness',
           lambda data: mutated, 0)

    payload = {
        'threshold': image_regions.DEFAULT_MINIMUM_CORRELATION,
        'colourMutation': {
            'case': cdc, 'page': 13,
            'pixelsChangedOver20Levels': round(float((difference > 20).mean()), 4),
            'pixelsChangedOver60Levels': round(float((difference > 60).mean()), 4),
        },
        'controls': controls,
    }
    (Path(__file__).parent / 'cell-controls.json').write_text(json.dumps(payload, indent=2) + '\n')
    print(json.dumps(payload, indent=2))


if __name__ == '__main__':
    main()
