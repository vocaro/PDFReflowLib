#!/usr/bin/env python3
"""Render the measurement-only references used by the raster qualification sweep.

Each reference is a Poppler render of a reviewed source region through
`tools/render_region_reference.py`, written under `measurements/raster-qualification/references`
rather than `corpus/references`, so none of them enters the corpus content contract. Regions
are given in PDF points from the crop box's top-left; the earlier raster-DPI targets' normalized
rectangles are converted with the page's crop box. Sources are verified by the renderer.
"""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'tools'))
from raster_sweep import crop_box  # noqa: E402

REFERENCES = [
    # case, page, region (points or normalized x,y,w,h with 'normalized'), name, kinds, target
    ('gpo-warren-1964', 50, ('normalized', [0.19, 0.058, 0.765, 0.038]), 'opening-lines', ['glyph', 'region'],
     'Two opening scan lines: September 26 to October 3, 1963 / the Soviet Embassy in the United States'),
    ('gpo-warren-1964', 890, ('normalized', [0.118, 0.074, 0.4, 0.075]), 'notes-415-421', ['glyph', 'region'],
     'Small notes 415-421 in the left column'),
    ('gpo-warren-1964', 100, ('points', [45, 38, 366, 150]), 'motorcade-paragraph', ['glyph', 'region'],
     'First body lines with inline note markers 63-66: motorcade reached the intersection of Elm and Houston Streets'),
    ('cia-blue-book-14-1955', 150, ('normalized', [0.204, 0.123, 0.173, 0.113]), 'totals-header', ['glyph', 'region'],
     'TOTALS header, Certain/Doubtful/Total labels and the first handwritten row'),
    ('cia-blue-book-14-1955', 74, ('points', [60, 225, 550, 485]), 'table-iv', ['glyph', 'region'],
     'Table IV chi-square test of knowns versus unknowns: headers, seven shape rows and totals'),
    ('nbs-jres-geltman-1977', 1, ('points', [55, 200, 465, 275]), 'abstract', ['glyph', 'region'],
     'Abstract paragraph and key words in small scanned type'),
    ('fed-explained-2021', 45, ('points', [60, 385, 235, 482]), 'open-market-desk', ['glyph', 'color'],
     'Figure 3.3 OPEN MARKET DESK node: white label on a dark band, illustration and four small caption lines'),
    ('fed-explained-2021', 82, ('points', [95, 130, 530, 227]), 'regulations-f-h', ['glyph', 'color', 'region'],
     'Figure 5.7 header band, Banks and banking band, and the Regulation F and H rows'),
    ('dga-2025-2030', 3, ('normalized', [0.048, 0.228, 0.445, 0.086]), 'protein-title', ['color', 'region'],
     'Food photograph, green gradient title Prioritize Protein Foods and the blue bullet text'),
    ('gpo-our-flag-2003', 27, ('points', [80, 438, 246, 575]), 'flag-size-table', ['glyph'],
     'Flag size table headers, ten numeric pairs and dot leaders at full resolution'),
    ('gpo-911-2004', 472, ('points', [35, 62, 362, 150]), 'notes-38-41', ['glyph', 'region'],
     'Chapter 1 endnotes 38-41 in small type with italic titles and numbers'),
]


def main():
    cases = {c['id']: c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
    written = []
    for case_id, page, (mode, values), name, kinds, target in REFERENCES:
        source = ROOT / 'corpus/cache' / cases[case_id]['filename']
        if mode == 'normalized':
            width, height = crop_box(source, page, '/opt/homebrew/bin/pdfinfo')
            x, y, w, h = values
            region = [x * width, y * height, (x + w) * width, (y + h) * height]
        else:
            region = values
        for kind in kinds:
            suffix = {'glyph': '-glyphs', 'color': '-color', 'region': ''}[kind]
            run = subprocess.run([sys.executable, ROOT / 'tools/render_region_reference.py', '--case', case_id,
                                  '--page', str(page), '--region', ','.join(f'{v:.2f}' for v in region),
                                  '--name', name + suffix, '--kind', kind, '--target', target,
                                  '--output-root', HERE / 'references'], check=True, capture_output=True, text=True)
            written.append(json.loads(run.stdout.strip().splitlines()[-1]))
            print(written[-1]['reference'], written[-1]['pixels'], flush=True)
    (HERE / 'references/index.json').write_text(json.dumps(written, indent=2) + '\n')


if __name__ == '__main__':
    main()
