"""Alternate fresh baseline/current complete-book conversions to investigate timing drift."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile
from collect import package_semantics

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['before', 'after', 'output']:
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    cases = {c['id']: c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
    binaries = {'before': args.before.resolve(strict=True), 'after': args.after.resolve(strict=True)}
    metadata = {'binaries': {k: {'path': str(v), 'sha256': sha(v)} for k, v in binaries.items()},
                'producerSHA256': {p: sha(ROOT / p) for p in ['tools/evaluate-real-document.py',
                    'measurements/pdfkit-concurrency/paired-timing.py', 'measurements/pdfkit-concurrency/collect.py']},
                'orderPerBook': ['before', 'after', 'after', 'before']}
    (args.output / 'identity.json').write_text(json.dumps(metadata, indent=2) + '\n')
    results = []
    for name in ['fed-explained-2021', 'faa-phak-8083-25c']:
        first_epub = None
        for index, variant in enumerate(metadata['orderPerBook'], 1):
            folder = args.output / f'{name}-{index}-{variant}'
            with (args.output / (folder.name + '.log')).open('wb') as log:
                subprocess.run([sys.executable, str(ROOT / 'tools/evaluate-real-document.py'), '--case', name,
                    '--pdf', str(ROOT / 'corpus/cache' / cases[name]['filename']), '--converter', str(binaries[variant]),
                    '--output', str(folder)], stdout=log, stderr=subprocess.STDOUT, check=True)
            result = json.loads((folder / 'result.json').read_text())
            epub = folder / f'{name}.epub'
            if first_epub is None:
                first_epub = epub
            else:
                with zipfile.ZipFile(first_epub) as left, zipfile.ZipFile(epub) as right:
                    assert left.namelist() == right.namelist()
                    for entry in left.namelist():
                        a, b = left.read(entry), right.read(entry)
                        assert (package_semantics(a) == package_semantics(b) if entry == 'EPUB/package.opf' else a == b), (name, entry)
            results.append({'case': name, 'order': index, 'variant': variant,
                'seconds': result['conversionSeconds'], 'cpuSeconds': result['converterCPUSeconds'],
                'peakRSSBytes': result['converterPeakRSSBytes'], 'epubSHA256': sha(epub),
                'resultSHA256': sha(folder / 'result.json')})
            (args.output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
            print(name, index, variant, round(result['conversionSeconds'], 2), flush=True)


if __name__ == '__main__':
    main()
