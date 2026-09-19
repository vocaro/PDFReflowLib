#!/usr/bin/env python3
"""Render a reviewed source region into a committed image-region reference.

Development tool; the corpus gate only reads the committed PNG. The region is given in PDF
points from the top-left of the rendered page (Poppler's displayed crop box). The source is
verified against the pinned manifest identity before rendering with Poppler pdftoppm at
180 DPI, averaged to 36 DPI grayscale and trimmed to ink. A JSON sidecar records provenance.
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

from PIL import Image

import image_regions
from pdfreflow_tools.corpus import ROOT, manifest_cases, matches_identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', required=True)
    parser.add_argument('--page', type=int, required=True)
    parser.add_argument('--region', required=True, help='x0,y0,x1,y1 in PDF points from the top-left')
    parser.add_argument('--name', required=True, help='lowercase hyphenated reference name')
    parser.add_argument('--target', required=True, help='what the region shows, for reviewers')
    parser.add_argument('--cache-dir', type=Path, default=ROOT / 'corpus/cache')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', args.name):
        parser.error('name must be lowercase hyphenated words')
    region = [float(value) for value in args.region.split(',')]
    if len(region) != 4 or not (0 <= region[0] < region[2] and 0 <= region[1] < region[3]):
        parser.error('region must be x0,y0,x1,y1 with positive width and height')
    cases = {c['id']: c for c in manifest_cases(ROOT)}
    case = cases.get(args.case) or parser.error('unknown corpus case')
    if not 1 <= args.page <= case['pages']:
        parser.error('page is outside the source')
    source = args.cache_dir / case['filename']
    if not matches_identity(source, case):
        parser.error('cached source differs from the pinned corpus identity')
    scale = image_regions.RENDER_DPI / 72
    version = subprocess.run(['pdftoppm', '-v'], capture_output=True, text=True).stderr.split('\n')[0].strip()
    with tempfile.TemporaryDirectory() as directory:
        subprocess.run(['pdftoppm', '-r', str(image_regions.RENDER_DPI), '-gray', '-png', '-singlefile',
                        '-f', str(args.page), '-l', str(args.page),
                        '-x', str(round(region[0] * scale)), '-y', str(round(region[1] * scale)),
                        '-W', str(round((region[2] - region[0]) * scale)),
                        '-H', str(round((region[3] - region[1]) * scale)),
                        str(source), directory + '/region'], check=True)
        with Image.open(directory + '/region.png') as rendered:
            values = image_regions.trimmed_to_ink(image_regions.pooled(rendered))
    reference = Image.fromarray(values.round().clip(0, 255).astype('uint8'), mode='L')
    output = ROOT / 'corpus/references' / args.case / f'page-{args.page}-{args.name}.png'
    output.parent.mkdir(parents=True, exist_ok=True)
    encoded = io.BytesIO()
    reference.save(encoded, format='PNG', optimize=True)
    output.write_bytes(encoded.getvalue())
    sidecar = {
        'case': args.case, 'sourceSHA256': case['sha256'], 'page': args.page,
        'regionPoints': region, 'target': args.target, 'renderer': version,
        'renderDPI': image_regions.RENDER_DPI, 'referenceDPI': image_regions.REFERENCE_DPI,
        'inkThreshold': image_regions.INK_THRESHOLD, 'pixels': [reference.width, reference.height],
        'sha256': hashlib.sha256(encoded.getvalue()).hexdigest(),
    }
    output.with_suffix('.json').write_text(json.dumps(sidecar, indent=2) + '\n')
    print(json.dumps({'reference': str(output.relative_to(ROOT)), **sidecar}))


if __name__ == '__main__':
    main()
