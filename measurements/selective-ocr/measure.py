#!/usr/bin/env python3
"""Measure OCR policies on pinned Warren pages plus native-text controls (requires pypdf)."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import time
import zipfile
from pypdf import PdfReader, PdfWriter

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import read_pages

PAGES = [1, 7, 21, 30, 50, 100, 890, 910, 920]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--converter', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--epubcheck', type=Path, required=True)
    parser.add_argument('--policies', nargs=3, default=['automatic', 'image-backed', 'always'])
    args = parser.parse_args()
    assert set(args.policies) == {'automatic', 'image-backed', 'always'}
    args.output.mkdir(parents=True, exist_ok=False)
    case = next(c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']
                if c['id'] == 'gpo-warren-1964')
    source = ROOT / 'corpus/cache' / case['filename']
    assert digest(source) == case['sha256'] and source.stat().st_size == case['bytes']
    controls = ROOT / 'Tests/PDFReflowLibTests/fixtures/prose.pdf'
    reader = PdfReader(source)
    writer = PdfWriter()
    for number in PAGES:
        writer.add_page(reader.pages[number - 1])
    for page in PdfReader(controls).pages:
        writer.add_page(page)
    mixed = args.output / 'mixed-source.pdf'
    with mixed.open('xb') as stream:
        writer.write(stream)
    identity = {'sourceSHA256': case['sha256'], 'sourcePages': PAGES,
                'controlSHA256': digest(controls), 'controlPages': [1, 2, 3],
                'mixedSHA256': digest(mixed), 'mixedBytes': mixed.stat().st_size,
                'converterSHA256': digest(args.converter)}
    (args.output / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
    spec = importlib.util.spec_from_file_location('checks', ROOT / 'tools/check-epubs.py')
    checks = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(checks)
    results, output_pages = [], {}
    for policy in args.policies:
        output = args.output / (policy + '.epub')
        command = ['/usr/bin/time', '-l', str(args.converter.resolve()), str(mixed), str(output), '--ocr', policy]
        start = time.monotonic()
        run = subprocess.run(command, capture_output=True, text=True, timeout=600)
        seconds = time.monotonic() - start
        (args.output / (policy + '-progress.log')).write_text(run.stderr)
        (args.output / (policy + '-report.json')).write_text(run.stdout)
        assert run.returncode == 0, run.stderr[-3000:]
        report = json.loads(run.stdout)
        checks.check(output)
        with (args.output / (policy + '-epubcheck.log')).open('w') as log:
            subprocess.run([str(args.epubcheck), str(output)], stdout=log, stderr=subprocess.STDOUT,
                           check=True, timeout=120)
        pages, markers = read_pages(output)
        assert markers == list(range(1, 13))
        (args.output / (policy + '-pages.json')).write_text(json.dumps(pages, indent=2) + '\n')
        output_pages[policy] = pages
        progress = [(int(percent), stage, int(page) if page else None)
                    for percent, stage, page in re.findall(r'^(\d+)% (\w+)(?: page (\d+)/\d+)?$', run.stderr, re.M)]
        assert progress[-1][:2] == (100, 'completed')
        assert all(a[0] <= b[0] for a, b in zip(progress, progress[1:]))
        recognized = [page for _, stage, page in progress if stage == 'recognizing']
        expected = [1, 9] if policy == 'automatic' else list(range(1, 10 if policy == 'image-backed' else 13))
        assert recognized == expected and report['recognizedPageCount'] == len(expected)
        assert all(pages[n]['images'] for n in range(1, 10))
        assert all(not pages[n]['text'] for n in [1, 9])
        assert not list(args.output.glob('.pdfreflow-*'))
        if policy != 'automatic':
            assert 'his known contacts with the Soviet Embassy' in pages[5]['text']
            assert not any(token in pages[5]['text'] for token in ['bis known', 'witb', 'tbe Soviet'])
            assert not any(w['code'] == 'unverifiedTextLayer' for w in report['warnings'])
        else:
            assert 'bis known contacts witb tbe Soviet Embassy' in pages[5]['text']
            assert any(w['code'] == 'unverifiedTextLayer' and w['page'] == 5 for w in report['warnings'])
        with zipfile.ZipFile(output) as archive:
            images = {name: hashlib.sha256(archive.read(name)).hexdigest()
                      for name in archive.namelist() if name.startswith('EPUB/images/')}
        results.append({'policy': policy, 'command': command, 'seconds': seconds,
                        'peakRSSBytes': int(re.search(r'(\d+)\s+maximum resident set size', run.stderr)[1]),
                        'epubBytes': output.stat().st_size, 'recognizedPages': recognized,
                        'imageSHA256': images, 'report': report, 'passed': True})
        print(f'PASS {policy}: {seconds:.2f}s, OCR pages {recognized}', flush=True)
    for number in [10, 11, 12]:
        assert output_pages['automatic'][number] == output_pages['image-backed'][number]
    by_policy = {result['policy']: result for result in results}
    for number in range(1, 10):
        # The last image is the complete page reference (or sole required fallback).
        reference_hashes = {by_policy[policy]['imageSHA256'][output_pages[policy][number]['images'][-1]]
                            for policy in args.policies}
        assert len(reference_hashes) == 1
    (args.output / 'results.json').write_text(json.dumps({'identity': identity, 'results': results,
        'nativeControlPagesIdentical': True, 'warrenSourceReferencesIdentical': True, 'passed': True}, indent=2) + '\n')


if __name__ == '__main__':
    main()
