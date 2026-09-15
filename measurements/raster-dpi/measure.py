#!/usr/bin/env python3
"""Measure production raster DPI/encoding on pinned originals; no PDF derivatives or downloads."""
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

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
RUNTIME = [ROOT / 'Sources/PDFReflowLib' / name for name in
           ['PageRasterizer.swift', 'ConversionTypes.swift', 'DocumentModel.swift', 'ReflowDocument.swift']]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def pixels(path):
    with Image.open(path) as image:
        return image.convert('RGB')


def jpeg_metrics(png, jpeg):
    assert png.size == jpeg.size
    difference = ImageChops.difference(png, jpeg)
    stats = ImageStat.Stat(difference)
    mse = sum(x * x for x in stats.rms) / 3
    return {'rgbPSNRdB': 10 * math.log10(255 * 255 / mse) if mse else None,
            'meanAbsoluteChannelError': sum(stats.mean) / 3,
            'maximumChannelError': max(hi for lo, hi in stats.extrema)}


def render_reviews(output, targets, rows, pdftoppm):
    review = output / 'review'
    review.mkdir()
    references = []
    for target in targets:
        prefix = review / (target['id'] + '-source-360')
        command = [pdftoppm, '-f', str(target['page']), '-l', str(target['page']),
                   '-singlefile', '-cropbox', '-r', '360', '-png', target['source'], str(prefix)]
        run = subprocess.run(command, capture_output=True, text=True, check=True, timeout=120)
        (review / (target['id'] + '-poppler.log')).write_text(run.stderr)
        path = prefix.with_suffix('.png')
        source = pixels(path)
        x, y, w, h = target['region']
        bounds = (round(x * source.width), round(y * source.height),
                  round((x + w) * source.width), round((y + h) * source.height))
        crop = source.crop(bounds)
        crop_path = review / (target['id'] + '-source-crop.png')
        crop.save(crop_path)
        references.append({'target': target['id'], 'command': command,
                           'sourceRasterSHA256': digest(path), 'sourceCropSHA256': digest(crop_path),
                           'sourceRasterDimensions': list(source.size), 'cropPixelBounds': bounds})
        baseline = next(row for row in rows if row['target'] == target['id'] and row['kind'] == 'region'
                        and row['encoding'] == 'png' and row['requestedDPI'] == 240 and row['trial'] == 1
                        and row['maximumRasterPixels'] == 12_000_000)
        width, height = baseline['width'], baseline['height']
        # Same source area at a common 240-DPI display size. Nearest-neighbor magnification
        # leaves lower-resolution pixels visible instead of smoothing away their limitations.
        # Poppler's 360-DPI source reference is reduced with Lanczos; it is not a pixel oracle.
        for kind in ['page', 'region']:
            sheet = Image.new('RGB', (2 * width + 30, 4 * (height + 35) + 25), 'white')
            draw = ImageDraw.Draw(sheet)
            draw.text((10, 5), target['id'] + ' ' + kind + ' | fixed source area; display = 240 DPI', fill='black')
            sheet.paste(crop.resize((width, height), Image.Resampling.LANCZOS), (10, 50))
            draw.text((10, 32), 'Independent source: Poppler 360 DPI', fill='black')
            for index, dpi in enumerate([120, 180, 240], 1):
                for column, encoding in enumerate(['png', 'jpeg90']):
                    row = next(row for row in rows if row['target'] == target['id'] and row['kind'] == kind
                               and row['encoding'] == encoding and row['requestedDPI'] == dpi
                               and row['trial'] == 1 and row['maximumRasterPixels'] == 12_000_000)
                    image = pixels(output / row['relativeFile'])
                    if kind == 'page':
                        image = image.crop((round(x * image.width), round(y * image.height),
                                            round((x + w) * image.width), round((y + h) * image.height)))
                    position = (10 + column * (width + 10), 50 + index * (height + 35))
                    label = f'{dpi} DPI {encoding} | native crop {image.width} x {image.height}'
                    draw.text((position[0], position[1] - 18), label, fill='black')
                    sheet.paste(image.resize((width, height), Image.Resampling.NEAREST), position)
            sheet.save(review / (target['id'] + '-' + kind + '-comparison.png'))
    write_json(output / 'source-references.json', references)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='new output directory')
    parser.add_argument('--pdftoppm', default='/opt/homebrew/bin/pdftoppm')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    cases = {case['id']: case for case in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
    targets = json.loads((HERE / 'targets.json').read_text())
    for target in targets:
        case = cases[target['case']]
        source = ROOT / 'corpus/cache' / case['filename']
        assert source.stat().st_size == case['bytes'] and digest(source) == case['sha256'], source
        target.update(source=str(source), sourceSHA256=case['sha256'], sourceBytes=case['bytes'])
    write_json(output / 'targets.json', targets)
    binary = output / 'probe'
    compile_command = ['xcrun', 'swiftc', '-O', '-parse-as-library', '-module-cache-path',
                       str(output / 'module-cache'), *map(str, RUNTIME), str(HERE / 'probe.swift'), '-o', str(binary)]
    subprocess.run(compile_command, check=True, timeout=180)
    identity = {'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'platform': platform.platform(), 'machine': platform.machine(),
                'hardwareModel': subprocess.check_output(['sysctl', '-n', 'hw.model'], text=True).strip(),
                'swVersion': subprocess.check_output(['sw_vers'], text=True),
                'xcodeVersion': subprocess.check_output(['xcodebuild', '-version'], text=True),
                'swiftVersion': subprocess.check_output(['xcrun', 'swiftc', '--version'], text=True),
                'popplerVersion': subprocess.run([args.pdftoppm, '-v'], capture_output=True, text=True,
                                                 check=True).stderr,
                'compileCommand': compile_command, 'binarySHA256': digest(binary),
                'producerSHA256': {str(path.relative_to(ROOT)): digest(path) for path in
                                   [*RUNTIME, HERE / 'probe.swift', HERE / 'measure.py', HERE / 'targets.json']},
                'targets': targets}
    write_json(output / 'identity.json', identity)
    rows, processes = [], []
    # Rotate execution order; each process handles both encodings from each identical CGImage.
    runs = [(trial, dpi, 12_000_000) for trial, order in enumerate(
            [[180, 120, 240], [240, 180, 120], [120, 240, 180]], 1) for dpi in order]
    runs.append((1, 240, 1_000_000))  # Separate cap control, not a recommended pixel budget.
    for trial, dpi, cap in runs:
        name = f'dpi-{dpi}-cap-{cap}-trial-{trial}'
        directory = output / name
        command = ['/usr/bin/time', '-l', str(binary), str(output / 'targets.json'), str(dpi), str(cap), str(directory)]
        start = time.monotonic()
        run = subprocess.run(command, capture_output=True, text=True, timeout=180)
        elapsed = time.monotonic() - start
        (output / (name + '.json')).write_text(run.stdout)
        (output / (name + '.log')).write_text(run.stderr)
        assert run.returncode == 0, run.stderr
        measured = json.loads(run.stdout)
        assert len(measured) == len(targets) * 4
        for row in measured:
            path = directory / row['file']
            image = pixels(path)
            assert list(image.size) == [row['width'], row['height']]
            assert image.width * image.height <= cap and row['bytes'] == path.stat().st_size
            assert 0 < row['effectiveDPIX'] <= dpi and 0 < row['effectiveDPIY'] <= dpi
            row.update(trial=trial, relativeFile=str(path.relative_to(output)), sha256=digest(path))
            if row['encoding'] == 'jpeg90':
                original = pixels(directory / (row['target'] + '-' + row['kind'] + '-png.png'))
                row['sameDPIPNGComparison'] = jpeg_metrics(original, image)
        rows.extend(measured)
        processes.append({'trial': trial, 'dpi': dpi, 'maximumRasterPixels': cap, 'command': command,
                          'elapsedSeconds': elapsed,
                          'peakRSSBytes': int(re.search(r'(\d+)\s+maximum resident set size', run.stderr)[1]),
                          'peakPhysicalFootprintBytes': int(re.search(r'(\d+)\s+peak memory footprint', run.stderr)[1])})
        print(f'PASS {name}: {elapsed:.2f}s, {len(measured)} images', flush=True)
    for row in rows:
        repeats = [other for other in rows if all(other[key] == row[key] for key in
                   ['target', 'kind', 'encoding', 'requestedDPI', 'maximumRasterPixels'])]
        assert len({other['sha256'] for other in repeats}) == 1, 'Nonrepeatable image bytes'
    summary = []
    for dpi in [120, 180, 240]:
        subset = [p for p in processes if p['dpi'] == dpi and p['maximumRasterPixels'] == 12_000_000]
        summary.append({'dpi': dpi, 'freshProcesses': len(subset),
                        'medianElapsedSeconds': statistics.median(p['elapsedSeconds'] for p in subset),
                        'minimumPeakRSSBytes': min(p['peakRSSBytes'] for p in subset),
                        'maximumPeakRSSBytes': max(p['peakRSSBytes'] for p in subset),
                        'imageBytes': {kind: {encoding: sum(row['bytes'] for row in rows
                            if row['requestedDPI'] == dpi and row['maximumRasterPixels'] == 12_000_000
                            and row['trial'] == 1 and row['kind'] == kind and row['encoding'] == encoding)
                            for encoding in ['png', 'jpeg90']} for kind in ['page', 'region']}})
    write_json(output / 'results.json', {'processes': processes, 'images': rows, 'summary': summary,
                                       'repeatImageHashesIdentical': True, 'passed': True})
    render_reviews(output, targets, rows, args.pdftoppm)
    print('PASS source references and equal-area comparison sheets', flush=True)


if __name__ == '__main__':
    main()
