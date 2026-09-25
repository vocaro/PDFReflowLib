#!/usr/bin/env python3
"""Stage verified corpus PDFs, generate the ceiling stress source, build RasterHost, then unstage.

Building does not install or launch on a device. The separate runner requires coordinated access.
The generated stress-plan records the exact derivative bytes for this build.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
STAGING = HERE / 'host/RasterHost'
CASES = ['cdc-zombie-pandemic-2011', 'fed-explained-2021', 'cia-blue-book-14-1955',
         'wallace-algebra-2010', 'faa-phak-8083-25c', 'noaa-nca5-2023', 'gpo-warren-1964']


def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--team', required=True)
    parser.add_argument('--derived-data', type=Path, required=True)
    parser.add_argument('--stress-plan', type=Path, required=True, help='record this build\'s derivative identity')
    args = parser.parse_args()
    cases = {c['id']: c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
    staged = []
    try:
        for name in CASES:
            case = cases[name]
            source = ROOT / 'corpus/cache' / case['filename']
            if source.stat().st_size != case['bytes'] or digest(source) != case['sha256']:
                raise ValueError(f'corpus identity mismatch: {name}')
            target = STAGING / (name + '.pdf')
            if target.exists(): raise ValueError(f'refusing to replace staged source: {target}')
            shutil.copyfile(source, target); staged.append(target)
        stress = STAGING / 'raster-ceiling-stress.pdf'
        if stress.exists(): raise ValueError(f'refusing to replace staged source: {stress}')
        staged.append(stress)
        subprocess.run(['xcrun', 'swift', '-module-cache-path', str(args.derived_data / 'stress-module-cache'),
                        str(HERE / 'make-stress.swift'), str(STAGING / 'cia-blue-book-14-1955.pdf'),
                        str(STAGING / 'faa-phak-8083-25c.pdf'), str(stress)], check=True)
        case = {'id': 'raster-ceiling-stress', 'filename': stress.name, 'pages': 2,
                'bytes': stress.stat().st_size, 'sha256': digest(stress)}
        plan = {'documents': [case], 'cases': [{'id': case['id'], 'sourceSHA256': case['sha256'],
                'pages': [{'page': 1, 'minimumImages': 1}, {'page': 2, 'minimumImages': 1}]}],
                'parents': [{key: cases[name][key] for key in ('id', 'sha256', 'bytes')}
                            for name in ('cia-blue-book-14-1955', 'faa-phak-8083-25c')],
                'recipe': 'make-stress.swift: Blue Book page 74, FAA page 121, each enlarged 3x'}
        args.stress_plan.write_text(json.dumps(plan, indent=2) + '\n')
        subprocess.run(['xcodebuild', 'build', '-project', str(HERE / 'host/RasterHost.xcodeproj'),
                        '-scheme', 'RasterHost', '-configuration', 'Release', '-destination', 'generic/platform=iOS',
                        '-derivedDataPath', str(args.derived_data), '-allowProvisioningUpdates',
                        'DEVELOPMENT_TEAM=' + args.team], check=True)
        receipt = {
            'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'binarySHA256': digest(args.derived_data / 'Build/Products/Release-iphoneos/RasterHost.app/RasterHost'),
            'hostSourceSHA256': digest(STAGING / 'AppDelegate.swift'),
            'librarySourceSHA256': {str(p.relative_to(ROOT)): digest(p) for p in sorted((ROOT / 'Sources/PDFReflowLib').rglob('*.swift'))},
            'packageResolvedSHA256': digest(ROOT / 'Package.resolved'),
        }
        (args.derived_data / 'build-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    finally:
        for path in staged: path.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
