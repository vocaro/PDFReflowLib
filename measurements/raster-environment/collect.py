"""Retain issue #26's controlled 2-build x 2-context x 2-document experiment.

Run from the repository root after the commands in record.md. Requires Pillow.
This is investigation evidence, not a rule that sandbox output is correct.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import platform
import shutil
import sys
import zipfile

from PIL import Image, ImageChops, ImageStat
import io

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import read_pages


def digest(data):
    return hashlib.sha256(data).hexdigest()


def capture(epub):
    pages, markers = read_pages(epub)
    images = {}
    with zipfile.ZipFile(epub) as archive:
        for name in archive.namelist():
            if not name.startswith('EPUB/images/'):
                continue
            data = archive.read(name)
            with Image.open(io.BytesIO(data)) as image:
                rgb = image.convert('RGB')
                images[name] = {'encodedSHA256': digest(data), 'rgbSHA256': digest(rgb.tobytes()),
                                'size': list(rgb.size)}
    return {'epubSHA256': digest(epub.read_bytes()), 'markers': markers,
            'pages': {str(k): digest(json.dumps(v, sort_keys=True).encode()) for k, v in pages.items()},
            'images': images}


def differences(left, right):
    return {
        'changedPages': sorted(int(k) for k in left['pages'].keys() | right['pages'].keys()
                               if left['pages'].get(k) != right['pages'].get(k)),
        'changedEncodedImages': sorted(k for k in left['images'].keys() | right['images'].keys()
                                 if left['images'].get(k, {}).get('encodedSHA256') != right['images'].get(k, {}).get('encodedSHA256')),
        'changedPixelImages': sorted(k for k in left['images'].keys() | right['images'].keys()
                               if left['images'].get(k, {}).get('rgbSHA256') != right['images'].get(k, {}).get('rgbSHA256')),
        'markersEqual': left['markers'] == right['markers'],
        'imageInventoryEqual': left['images'].keys() == right['images'].keys(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, default=ROOT / '.build/raster-drift-investigation')
    parser.add_argument('--output', type=Path, default=Path(__file__).parent)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    def save(name, value):
        data = (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()
        if name.endswith('.gz'):
            data = gzip.compress(data, mtime=0)
        (args.output / name).write_bytes(data)

    manifest = json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']
    cases = {'cdc': 'cdc-zombie-pandemic-2011', 'dga': 'dga-2025-2030'}
    sources = {}
    for short, case in cases.items():
        entry = next(item for item in manifest if item['id'] == case)
        actual = digest((ROOT / 'corpus/cache' / entry['filename']).read_bytes())
        assert actual == entry['sha256']
        sources[short] = {'id': case, 'sha256': actual, 'pages': entry['pages']}
    binaries = {build: digest((ROOT / f'.build/endnotes-clean-{build}/release/pdf-reflow').read_bytes())
                for build in ['baseline', 'candidate']}
    runs, comparisons = {}, []
    for short, case in cases.items():
        historical = {name: capture(ROOT / '.build' / folder / case / (case + '.epub'))
                      for name, folder in [('baseline', 'endnotes-clean-before'),
                                           ('candidate', 'endnotes-clean-candidate-output')]}
        for name, value in historical.items():
            runs[f'historical-{name}-{short}'] = value
        for build in binaries:
            for context in ['sandbox', 'host']:
                label = f'{build}-{context}-{short}'
                runs[label] = capture(args.work / (label + '.epub'))
                report = json.loads((args.work / (label + '.json')).read_text())
                runs[label].update(converterSHA256=binaries[build], executionContext=context,
                    recognizedPageCount=report['recognizedPageCount'], source=sources[short],
                    conversionReport={k: v for k, v in report.items() if k != 'outputURL'})
                save(label + '-report.json.gz', report)
                (args.output / (label + '-progress.log.gz')).write_bytes(
                    gzip.compress((args.work / (label + '.log')).read_bytes(), mtime=0))
                reference = 'baseline' if context == 'sandbox' else 'candidate'
                delta = differences(runs[label], historical[reference])
                assert not delta['changedPages'] and not delta['changedEncodedImages'] and not delta['changedPixelImages']
                comparisons.append({'left': label, 'right': f'historical-{reference}-{short}', **delta})
        for context in ['sandbox', 'host']:
            a, b = f'baseline-{context}-{short}', f'candidate-{context}-{short}'
            delta = differences(runs[a], runs[b])
            assert not delta['changedPages'] and not delta['changedEncodedImages']
            assert runs[a]['conversionReport'] == runs[b]['conversionReport']
            delta['conversionReportsEqual'] = True
            comparisons.append({'left': a, 'right': b, **delta})
        for build in binaries:
            a, b = f'{build}-sandbox-{short}', f'{build}-host-{short}'
            delta = differences(runs[a], runs[b])
            assert delta['changedPages'] == ([13, 15, 16, 17, 36] if short == 'cdc' else [])
            assert len(delta['changedPixelImages']) == (36 if short == 'cdc' else 1)
            comparisons.append({'left': a, 'right': b, **delta})
    save('runs.json.gz', runs)
    save('comparisons.json', comparisons)
    save('identity.json', {'sourceRevision': '7f0e25d', 'historicalBaselineRevision': '0eba8d4',
                         'system': platform.platform(), 'systemBuild': platform.version(),
                         'binaries': binaries, 'sources': sources,
                         'collectorSHA256': digest(Path(__file__).read_bytes()),
                         'legacyProbeSHA256': digest((args.work / 'probe').read_bytes()),
                         'currentProbeSourceSHA256': digest((ROOT / 'tools/probe-raster-environment.swift').read_bytes())})
    for context in ['sandbox', 'host']:
        save(f'probe-{context}.json', json.loads((args.work / f'probe-{context}.json').read_text()))
    probes = [json.loads((args.work / f'probe-{context}.json').read_text()) for context in ['sandbox', 'host']]
    assert probes[0]['probeSHA256'] == probes[1]['probeSHA256'] == digest((args.work / 'probe').read_bytes())
    assert probes[0]['metalDevice'] == 'unavailable' and probes[1]['metalDevice'] == 'Apple M5 Max'
    assert probes[0]['ocr']['description'] == 'Failed to create CVPixelBuffer'
    assert probes[1]['ocr']['status'] == 'succeeded'
    samples = []
    for short, image_name in [('cdc', 'image-1.png'), ('dga', 'image-3.png')]:
        images = []
        for context in ['sandbox', 'host']:
            with zipfile.ZipFile(args.work / f'baseline-{context}-{short}.epub') as archive:
                images.append(Image.open(io.BytesIO(archive.read('EPUB/images/' + image_name))).convert('RGB'))
        delta = ImageChops.difference(*images)
        samples.append({'case': short, 'image': image_name, 'size': list(images[0].size),
                        'meanAbsoluteRGBDifference': ImageStat.Stat(delta).mean,
                        'changedPixelBounds': delta.getbbox()})
    save('pixel-samples.json', samples)
    for folder in ['main-evaluations', 'baseline-evaluations', 'verified-main-host', 'verified-baseline-host',
                   'verified-main-sandbox']:
        if not (args.work / folder).exists():
            continue
        for file in (args.work / folder).rglob('*'):
            if file.suffix not in {'.json', '.log'}:
                continue
            target = args.output / folder / file.relative_to(args.work / folder)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.with_suffix(target.suffix + '.gz').write_bytes(gzip.compress(file.read_bytes(), mtime=0))
    for file in args.work.glob('*comparison.json'):
        shutil.copyfile(file, args.output / file.name)
    for name in ['fast-gate.log', 'main-build.log', 'python-tests-v1.log']:
        path = args.work / name
        if path.exists():
            (args.output / (name + '.gz')).write_bytes(gzip.compress(path.read_bytes(), mtime=0))
    print('Verified all eight factorial cells and retained complete parsed/pixel identities.')


if __name__ == '__main__':
    main()
