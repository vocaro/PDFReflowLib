#!/usr/bin/env python3
"""Render a reviewed source region into a committed image-region reference.

Development tool; the corpus gate only reads the committed PNG. The region is given in PDF
points from the top-left of the rendered page (Poppler's displayed crop box). The source is
verified against the pinned manifest identity before rendering with Poppler pdftoppm at
180 DPI. A `region` reference is averaged to 36 DPI grayscale and trimmed to ink; a `glyph`
reference keeps the full 180 DPI grayscale raster with a white margin for component coverage;
a `color` reference is averaged to 36 DPI RGB and trimmed by the same ink box. A JSON sidecar
records provenance and the reference kind.
Choose regions from the source itself; never derive them from converter output.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tempfile

import numpy as np
from PIL import Image

import glyph_structure
import image_regions

ROOT = Path(__file__).resolve().parents[1]


def trim_box(gray):
    """(top, bottom, left, right) of the ink bounding box plus a one-sample margin, as trimmed_to_ink."""
    ink = np.argwhere(gray < image_regions.INK_THRESHOLD)
    if ink.size == 0:
        raise ValueError('Reference region contains no ink')
    (top, left), (bottom, right) = ink.min(0), ink.max(0) + 1
    return max(0, top - 1), bottom + 1, max(0, left - 1), right + 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', required=True)
    parser.add_argument('--page', type=int, required=True)
    parser.add_argument('--region', required=True, help='x0,y0,x1,y1 in PDF points from the top-left')
    parser.add_argument('--name', required=True, help='lowercase hyphenated reference name')
    parser.add_argument('--target', required=True, help='what the region shows, for reviewers')
    parser.add_argument('--kind', choices=('region', 'glyph', 'color'), default='region',
                        help='region: 36 DPI grayscale correlation reference (default); '
                             'glyph: full 180 DPI grayscale for component coverage; '
                             'color: 36 DPI RGB for appearance checks')
    parser.add_argument('--cache-dir', type=Path, default=ROOT / 'corpus/cache')
    parser.add_argument('--output-root', type=Path, default=ROOT / 'corpus/references',
                        help='directory receiving <case>/page-N-<name>.png; measurement-only references '
                             'live outside corpus/references so they never enter the corpus contract')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', args.name):
        parser.error('name must be lowercase hyphenated words')
    region = [float(value) for value in args.region.split(',')]
    if len(region) != 4 or not (0 <= region[0] < region[2] and 0 <= region[1] < region[3]):
        parser.error('region must be x0,y0,x1,y1 with positive width and height')
    cases = {c['id']: c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
    case = cases.get(args.case) or parser.error('unknown corpus case')
    if not 1 <= args.page <= case['pages']:
        parser.error('page is outside the source')
    source = args.cache_dir / case['filename']
    data = source.read_bytes()
    if len(data) != case['bytes'] or hashlib.sha256(data).hexdigest() != case['sha256']:
        parser.error('cached source differs from the pinned corpus identity')
    scale = image_regions.RENDER_DPI / 72
    version = subprocess.run(['pdftoppm', '-v'], capture_output=True, text=True).stderr.split('\n')[0].strip()
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run(['pdftoppm', '-r', str(image_regions.RENDER_DPI)] + ([] if args.kind == 'color' else ['-gray'])
                       + ['-png', '-singlefile', '-f', str(args.page), '-l', str(args.page),
                          '-x', str(round(region[0] * scale)), '-y', str(round(region[1] * scale)),
                          '-W', str(round((region[2] - region[0]) * scale)),
                          '-H', str(round((region[3] - region[1]) * scale)),
                          str(source), directory + '/region'], check=True)
        with Image.open(directory + '/region.png') as rendered:
            if args.kind == 'glyph':
                values = glyph_structure.trimmed_to_ink(np.asarray(rendered.convert('L'), dtype=np.float64))
            elif args.kind == 'color':
                gray = image_regions.pooled(rendered)
                rgb = image_regions.pooled_array(np.asarray(rendered.convert('RGB'), dtype=np.float64))
                box = trim_box(gray)
                values = rgb[box[0]:box[1], box[2]:box[3]]
            else:
                values = image_regions.trimmed_to_ink(image_regions.pooled(rendered))
    reference = Image.fromarray(values.round().clip(0, 255).astype('uint8'), mode='RGB' if args.kind == 'color' else 'L')
    output = args.output_root / args.case / f'page-{args.page}-{args.name}.png'
    output.parent.mkdir(parents=True, exist_ok=True)
    encoded = io.BytesIO()
    reference.save(encoded, format='PNG', optimize=True)
    output.write_bytes(encoded.getvalue())
    sidecar = {
        'case': args.case, 'sourceSHA256': case['sha256'], 'page': args.page,
        'regionPoints': region, 'target': args.target, 'renderer': version,
        'renderDPI': image_regions.RENDER_DPI,
        'referenceDPI': glyph_structure.REFERENCE_DPI if args.kind == 'glyph' else image_regions.REFERENCE_DPI,
        'kind': args.kind, 'mode': reference.mode,
        'inkThreshold': image_regions.INK_THRESHOLD, 'pixels': [reference.width, reference.height],
        'sha256': hashlib.sha256(encoded.getvalue()).hexdigest(),
    }
    output.with_suffix('.json').write_text(json.dumps(sidecar, indent=2) + '\n')
    print(json.dumps({'reference': str(output.relative_to(ROOT) if output.is_relative_to(ROOT) else output), **sidecar}))


if __name__ == '__main__':
    main()
