#!/usr/bin/env python3
"""Measure current production rasters against source-reviewed phrases at several DPI/qualities.

Source identities are verified before rendering. PNG/JPEG pairs share one raster. Vision
phrase recovery and pixel error are diagnostic proxies, not reading accuracy or fidelity gates.
The historical glyph/appearance checkers are retained only in the archived #28 evidence.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import platform
import re
import statistics
import subprocess
import time

from PIL import Image, ImageChops, ImageDraw, ImageStat

from pdfreflow_tools.swift_sources import library_sources

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = [ROOT / path for path in library_sources('probe-raster-sweep.swift')]
PROBE_SOURCE = ROOT / 'tools/probes/probe-raster-sweep.swift'
DEFAULT_DPIS = [96, 120, 150, 180, 240, 300]
DEFAULT_QUALITIES = [0.60, 0.75, 0.85, 0.90, 0.95]
BASE_DPI = 180
SOURCE_DPI = 360
SHEET_WIDTH = 1400
Image.MAX_IMAGE_PIXELS = 60_000_000


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def encoding_label(quality):
    """'png' for lossless, else the probe's JPEG label, e.g. 0.9 -> 'jpeg90'."""
    return 'png' if quality is None else f'jpeg{math.floor(quality * 100 + 0.5)}'


def squeezed(text):
    """Text without any whitespace, so recognizer spacing differences do not count."""
    return ''.join(str(text).split())


def phrase_coverage(lines, phrases):
    """Fraction of reviewed phrases present (ignoring whitespace) in recognized lines."""
    text = squeezed(' '.join(lines))
    missing = [phrase for phrase in phrases if squeezed(phrase) not in text]
    return {'expected': len(phrases), 'found': len(phrases) - len(missing),
            'fraction': (len(phrases) - len(missing)) / len(phrases) if phrases else None, 'missing': missing}


def jpeg_metrics(png, jpeg):
    """Error of a JPEG against the PNG of the same raster."""
    if png.size != jpeg.size:
        raise ValueError('JPEG and PNG rasters differ in size')
    stats = ImageStat.Stat(ImageChops.difference(png, jpeg))
    mse = sum(x * x for x in stats.rms) / 3
    return {'rgbPSNRdB': round(10 * math.log10(255 * 255 / mse), 2) if mse else None,
            'meanAbsoluteChannelError': round(sum(stats.mean) / 3, 4),
            'maximumChannelError': max(hi for lo, hi in stats.extrema)}


def crop_box(pdf, page, pdfinfo='pdfinfo'):
    """(width, height) in points of a page's crop box from Poppler's pdfinfo."""
    text = subprocess.run([pdfinfo, '-f', str(page), '-l', str(page), '-box', str(pdf)],
                          capture_output=True, text=True, check=True).stdout
    match = re.search(rf'^Page\s+{page}\s+CropBox:\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)', text, re.MULTILINE)
    if not match:
        raise ValueError(f'no crop box for page {page}')
    x0, y0, x1, y1 = map(float, match.groups())
    return x1 - x0, y1 - y0


def load_targets(path, manifest, cache_dir, pdfinfo='pdfinfo', box=crop_box):
    """Resolve and verify sweep targets; regions become x0,y0,x1,y1 points from the crop box's top-left."""
    cases = {case['id']: case for case in manifest['documents']}
    targets = json.loads(Path(path).read_text())
    seen = set()
    for target in targets:
        if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', target.get('id', '')) or target['id'] in seen:
            raise ValueError('target ids must be unique lowercase hyphenated words')
        seen.add(target['id'])
        case = cases[target['case']]
        source = Path(cache_dir) / case['filename']
        if source.stat().st_size != case['bytes'] or digest(source) != case['sha256']:
            raise ValueError(f'{source} differs from the pinned corpus identity')
        if not 1 <= target['page'] <= case['pages']:
            raise ValueError(f'{target["id"]}: page outside the source')
        width, height = box(source, target['page'], pdfinfo)
        if 'regionNormalized' in target:
            x, y, w, h = target['regionNormalized']
            target['region'] = [x * width, y * height, (x + w) * width, (y + h) * height]
        region = target.get('region')
        if (not isinstance(region, list) or len(region) != 4
                or not (0 <= region[0] < region[2] <= width + 1e-6 and 0 <= region[1] < region[3] <= height + 1e-6)):
            raise ValueError(f'{target["id"]}: region must be x0,y0,x1,y1 points inside the {width} x {height} crop box')
        target.update(source=str(source), sourceSHA256=case['sha256'], sourceBytes=case['bytes'],
                      cropBoxPoints=[width, height], expectedPhrases=list(target.get('expectedPhrases', [])))
        target['references'] = []  # Historical checker references are not current gates.
    return targets


def probe_targets(targets):
    return [{key: target[key] for key in ('id', 'source', 'page', 'region')} for target in targets]


def run_probe(binary, targets_json, dpi, pixels, qualities, ocr, directory):
    """One fresh probe process; returns (rows, process record)."""
    command = ['/usr/bin/time', '-l', str(binary), str(targets_json), str(dpi), str(pixels),
               ','.join(f'{q:g}' for q in qualities), 'ocr' if ocr else 'no-ocr', str(directory)]
    started = time.monotonic()
    run = subprocess.run(command, capture_output=True, text=True, timeout=3600)
    elapsed = time.monotonic() - started
    if run.returncode != 0:
        raise RuntimeError(f'probe failed at {dpi} DPI: {run.stderr[-2000:]}')
    rows = json.loads(run.stdout)
    record = {'dpi': dpi, 'maximumRasterPixels': pixels, 'command': command, 'elapsedSeconds': round(elapsed, 3),
              'peakRSSBytes': int(re.search(r'(\d+)\s+maximum resident set size', run.stderr)[1]),
              'peakPhysicalFootprintBytes': int(re.search(r'(\d+)\s+peak memory footprint', run.stderr)[1])}
    return rows, record, run.stderr


def summarize(rows, processes):
    """Per-setting totals (page/region bytes and pixels), per-DPI process memory, mean fidelity."""
    settings = sorted({(row['requestedDPI'], row['encoding']) for row in rows},
                      key=lambda item: (item[0], item[1] != 'png', item[1]))
    summary = []
    for dpi, encoding in settings:
        subset = [row for row in rows if row['requestedDPI'] == dpi and row['encoding'] == encoding]
        entry = {'dpi': dpi, 'encoding': encoding}
        for kind in ('page', 'region'):
            part = [row for row in subset if row['kind'] == kind]
            entry[kind] = {'images': len(part), 'bytes': sum(row['bytes'] for row in part),
                           'pixels': sum(row['width'] * row['height'] for row in part)}
        psnr = [row['sameDPIPNGComparison']['rgbPSNRdB'] for row in subset
                if row.get('sameDPIPNGComparison', {}).get('rgbPSNRdB') is not None]
        entry['medianRGBPSNRdB'] = round(statistics.median(psnr), 2) if psnr else None
        phrases = [row['phraseCoverage']['fraction'] for row in subset
                   if row.get('phraseCoverage', {}).get('fraction') is not None]
        entry['meanPhraseFraction'] = round(statistics.fmean(phrases), 4) if phrases else None
        summary.append(entry)
    memory = [{'dpi': p['dpi'], 'peakRSSBytes': p['peakRSSBytes'],
               'peakPhysicalFootprintBytes': p['peakPhysicalFootprintBytes'], 'elapsedSeconds': p['elapsedSeconds']}
              for p in processes]
    return {'settings': summary, 'processes': memory}


def markdown_tables(summary, rows):
    """Reviewer-facing tables: bytes by setting, memory by DPI, phrase coverage by target and setting."""
    lines = ['| DPI | Encoding | Page images | Page MiB | Page Mpx | Region KiB | Median PSNR dB | Mean phrase fraction |',
             '| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for entry in summary['settings']:
        lines.append(f"| {entry['dpi']} | {entry['encoding']} | {entry['page']['images']} | "
                     f"{entry['page']['bytes'] / 1048576:.3f} | {entry['page']['pixels'] / 1e6:.2f} | "
                     f"{entry['region']['bytes'] / 1024:.1f} | {entry['medianRGBPSNRdB'] if entry['medianRGBPSNRdB'] is not None else 'n/a'} | "
                     f"{entry['meanPhraseFraction'] if entry['meanPhraseFraction'] is not None else 'n/a'} |")
    lines += ['', '| DPI | Probe peak RSS MiB | Peak footprint MiB | Probe seconds |', '| ---: | ---: | ---: | ---: |']
    for entry in summary['processes']:
        lines.append(f"| {entry['dpi']} | {entry['peakRSSBytes'] / 1048576:.1f} | "
                     f"{entry['peakPhysicalFootprintBytes'] / 1048576:.1f} | {entry['elapsedSeconds']:.2f} |")
    settings = [(e['dpi'], e['encoding']) for e in summary['settings']]
    targets = sorted({row['target'] for row in rows if row.get('phraseCoverage', {}).get('fraction') is not None})
    if targets:
        lines += ['', '| Target | ' + ' | '.join(f'{d} {e}' for d, e in settings) + ' |',
                  '| --- | ' + ' | '.join('---:' for _ in settings) + ' |']
        for target in targets:
            cells = []
            for dpi, encoding in settings:
                row = next((r for r in rows if r['target'] == target and r['kind'] == 'region'
                            and r['requestedDPI'] == dpi and r['encoding'] == encoding), None)
                coverage = (row or {}).get('phraseCoverage', {})
                cells.append(f"{coverage['found']}/{coverage['expected']}" if coverage.get('expected') else 'n/a')
            lines.append(f'| {target} | ' + ' | '.join(cells) + ' |')
    return '\n'.join(lines) + '\n'


def render_sheets(output, targets, rows, dpis, qualities, pdftoppm):
    """Equal-area review sheets: region crops across DPIs (PNG) and across encodings (at 180 DPI)."""
    review = output / 'review'
    review.mkdir(exist_ok=True)
    references = []
    for target in targets:
        prefix = review / (target['id'] + f'-source-{SOURCE_DPI}')
        command = [pdftoppm, '-f', str(target['page']), '-l', str(target['page']), '-singlefile', '-cropbox',
                   '-r', str(SOURCE_DPI), '-png', target['source'], str(prefix)]
        subprocess.run(command, capture_output=True, text=True, check=True, timeout=300)
        x0, y0, x1, y1 = target['region']
        scale = SOURCE_DPI / 72
        with Image.open(prefix.with_suffix('.png')) as page:
            crop = page.convert('RGB').crop((round(x0 * scale), round(y0 * scale), round(x1 * scale), round(y1 * scale)))
        crop_path = review / (target['id'] + '-source-crop.png')
        crop.save(crop_path)
        prefix.with_suffix('.png').unlink()
        references.append({'target': target['id'], 'command': command, 'sourceCropSHA256': digest(crop_path)})

        def region_row(dpi, encoding):
            return next(row for row in rows if row['target'] == target['id'] and row['kind'] == 'region'
                        and row['requestedDPI'] == dpi and row['encoding'] == encoding)

        largest = region_row(max(dpis), 'png')
        width, height = largest['width'], largest['height']
        if width > SHEET_WIDTH:
            height, width = round(height * SHEET_WIDTH / width), SHEET_WIDTH
        panels = [('Independent source: Poppler %d DPI (Lanczos)' % SOURCE_DPI, crop.resize((width, height), Image.Resampling.LANCZOS))]
        for dpi in dpis:
            row = region_row(dpi, 'png')
            with Image.open(output / row['relativeFile']) as image:
                panels.append((f'{dpi} DPI png | native {row["width"]} x {row["height"]}',
                               image.convert('RGB').resize((width, height), Image.Resampling.NEAREST)))
        sheet(panels, review / (target['id'] + '-dpi-comparison.png'), target['id'] + ' region | equal source area; nearest-neighbour magnification')
        panels = [panels[0]]
        for quality in [None] + list(qualities):
            row = region_row(BASE_DPI, encoding_label(quality))
            with Image.open(output / row['relativeFile']) as image:
                panels.append((f'{BASE_DPI} DPI {row["encoding"]} | {row["bytes"]} bytes',
                               image.convert('RGB').resize((width, height), Image.Resampling.NEAREST)))
        sheet(panels, review / (target['id'] + '-encoding-comparison.png'), target['id'] + f' region at {BASE_DPI} DPI | same raster, each encoding')
    write_json(output / 'source-references.json', references)


def sheet(panels, path, title):
    width, height = panels[0][1].size
    image = Image.new('RGB', (width + 20, len(panels) * (height + 30) + 30), 'white')
    draw = ImageDraw.Draw(image)
    draw.text((10, 5), title, fill='black')
    for index, (label, panel) in enumerate(panels):
        y = 30 + index * (height + 30)
        draw.text((10, y), label, fill='black')
        image.paste(panel, (10, y + 18))
    image.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--targets', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='new output directory')
    parser.add_argument('--dpi', type=float, action='append', dest='dpis')
    parser.add_argument('--quality', type=float, action='append', dest='qualities')
    parser.add_argument('--maximum-pixels', type=int, default=12_000_000)
    parser.add_argument('--no-ocr', action='store_true')
    parser.add_argument('--no-sheets', action='store_true')
    parser.add_argument('--cache-dir', type=Path, default=ROOT / 'corpus/cache')
    parser.add_argument('--pdftoppm', default='/opt/homebrew/bin/pdftoppm')
    parser.add_argument('--pdfinfo', default='/opt/homebrew/bin/pdfinfo')
    args = parser.parse_args()
    dpis = [int(d) if float(d).is_integer() else d for d in (args.dpis or DEFAULT_DPIS)]
    qualities = args.qualities or DEFAULT_QUALITIES
    if any(not 72 <= d <= 600 for d in dpis) or any(not 0 <= q <= 1 for q in qualities):
        parser.error('DPI must be in 72...600 and JPEG quality in 0...1')
    if not 1 <= args.maximum_pixels <= 48_000_000:
        parser.error('maximum pixels must be in 1...48000000')
    if len(set(dpis)) != len(dpis) or len({encoding_label(q) for q in qualities}) != len(qualities):
        parser.error('duplicate DPI or rounded JPEG labels')
    if not args.no_sheets and BASE_DPI not in dpis:
        parser.error('review sheets require 180 DPI')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    manifest = json.loads((ROOT / 'corpus/manifest.json').read_text())
    targets = load_targets(args.targets, manifest, args.cache_dir, pdfinfo=args.pdfinfo)
    write_json(output / 'targets.json', [{k: v for k, v in t.items() if k != 'references'}
                                          | {'references': [{k: v for k, v in r.items() if k != 'data'} for r in t['references']]}
                                          for t in targets])
    targets_json = output / 'probe-targets.json'
    write_json(targets_json, probe_targets(targets))
    binary = output / 'probe'
    compile_command = ['xcrun', 'swiftc', '-O', '-parse-as-library', '-module-cache-path', str(output / 'module-cache'),
                       *map(str, RUNTIME), str(PROBE_SOURCE), '-o', str(binary)]
    subprocess.run(compile_command, check=True, timeout=600)
    identity = {'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'platform': platform.platform(), 'machine': platform.machine(),
                'hardwareModel': subprocess.check_output(['sysctl', '-n', 'hw.model'], text=True).strip(),
                'swVersion': subprocess.check_output(['sw_vers'], text=True),
                'xcodeVersion': subprocess.check_output(['xcodebuild', '-version'], text=True),
                'popplerVersion': subprocess.run([args.pdftoppm, '-v'], capture_output=True, text=True).stderr,
                'compileCommand': compile_command, 'binarySHA256': digest(binary),
                'producerSHA256': {str(p.relative_to(ROOT)): digest(p) for p in [*RUNTIME, PROBE_SOURCE, Path(__file__).resolve()]},
                'targetsSHA256': digest(args.targets), 'dpis': dpis, 'qualities': qualities,
                'maximumRasterPixels': args.maximum_pixels, 'ocr': not args.no_ocr}
    write_json(output / 'identity.json', identity)
    rows, processes = [], []
    for dpi in dpis:
        directory = output / f'dpi-{dpi:g}'
        measured, record, log = run_probe(binary, targets_json, dpi, args.maximum_pixels, qualities, not args.no_ocr, directory)
        (output / f'dpi-{dpi:g}.log').write_text(log)
        expected = len(targets) * 2 * (1 + len(qualities))
        if len(measured) != expected:
            raise RuntimeError(f'probe returned {len(measured)} images, expected {expected}')
        by_target = {target['id']: target for target in targets}
        for row in measured:
            path = directory / row['file']
            with Image.open(path) as image:
                image = image.convert('RGB')
                if list(image.size) != [row['width'], row['height']] or image.width * image.height > args.maximum_pixels:
                    raise RuntimeError(f'{path}: dimensions disagree with the probe or exceed the ceiling')
                row.update(relativeFile=str(path.relative_to(output)), sha256=digest(path), pixels=image.width * image.height)
                if row['encoding'] != 'png':
                    with Image.open(directory / (row['target'] + '-' + row['kind'] + '-png.png')) as original:
                        row['sameDPIPNGComparison'] = jpeg_metrics(original.convert('RGB'), image)
            ocr = row.get('ocr')
            if ocr and ocr.get('status') == 'succeeded':
                row['phraseCoverage'] = phrase_coverage(ocr['lines'], by_target[row['target']]['expectedPhrases'])
        rows.extend(measured)
        processes.append(record)
        print(f'PASS dpi {dpi:g}: {record["elapsedSeconds"]:.2f}s, {len(measured)} images, '
              f'peak RSS {record["peakRSSBytes"] / 1048576:.1f} MiB', flush=True)
    summary = summarize(rows, processes)
    write_json(output / 'results.json', {'identity': identity, 'processes': processes, 'images': rows, 'summary': summary})
    (output / 'summary.md').write_text(markdown_tables(summary, rows))
    if not args.no_sheets:
        render_sheets(output, targets, rows, dpis, qualities, args.pdftoppm)
        print('PASS review sheets', flush=True)


if __name__ == '__main__':
    main()
