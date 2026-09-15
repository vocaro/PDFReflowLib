#!/usr/bin/env python3
"""Full pinned NOAA conversions with explicit policies; no downloads or runtime changes.

Run PNG then JPEG sequentially in fresh converter processes. Existing default failure
receipts are measured separately. Requires the development Pillow dependency for image QA.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[2]
CASE = 'noaa-nca5-2023'
SOURCE_SHA256 = '1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf'
BUDGET = 4 * 1024**3
MAXIMUM_ENTRIES = 20_000
HTML = '{http://www.w3.org/1999/xhtml}'
OPF = '{http://www.idpf.org/2007/opf}'
EPUB = '{http://www.idpf.org/2007/ops}'
REVIEW_PAGES = [48, 80, 1619, 1834]
# These phrases are read from independent source-page rasters, not converter output.
PHRASES = {48: ['How the United States Is Experiencing Climate Change'],
           80: ['Climate Trends'], 1619: ['Mitigation']}
# The source's last page visibly has these phrases, but output preserves it as a
# warned full-page image. Keep that missing reflow explicit, never as a text pass.
UNREFLOWED_SOURCE = {1834: ['nca2023.globalchange.gov', 'U.S. Global Change Research Program']}


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def check_default(directory):
    result = json.loads((directory / 'result.json').read_text())
    assert result['case']['sha256'] == SOURCE_SHA256 and result['case']['pages'] == 1834
    log = (directory / 'progress.log').read_text()
    events = [(int(fraction), stage, int(page) if page else None)
              for fraction, stage, page in re.findall(r'^(\d+)% (\w+)(?: page (\d+)/1834)?$', log, re.M)]
    assert result['conversionExitCode'] == 1 and result['runPassed'] is False
    assert result['options'] == 'library defaults' and not result.get('timedOut')
    assert 'Conversion resource limit: image output bytes' in log
    assert [page for _, stage, page in events if stage == 'extracting'] == list(range(1, 1835))
    assert events and all(a[0] <= b[0] for a, b in zip(events, events[1:]))
    assert all(fraction < 100 and stage != 'completed' for fraction, stage, _ in events)
    assert not (directory / (CASE + '.epub')).exists()
    assert not list(directory.glob('.pdfreflow-*'))
    return {'expectedImageBudgetFailure': True, 'all1834PagesExtracted': True,
            'lastCompletedReconstructionPage': max(page for _, stage, page in events if stage == 'reconstructing'),
            'noPublicationOrFalseCompletion': True, 'stagingRemoved': True,
            'rawResultSHA256': digest(directory / 'result.json')}


def check_cancellation(directory):
    checked = {}
    for stage in ['reconstructing', 'writing']:
        result = json.loads((directory / f'cancel-{stage}.json').read_text())
        assert result['sourceSHA256'] == SOURCE_SHA256 and result['sourcePages'] == 1834
        assert result['cancelled'] and result['outputAbsent'] and result['stagingRemoved']
        log = (directory / f'cancel-{stage}.log').read_text()
        events = [(float(fraction), value, int(page), cancel == 'true')
                  for fraction, value, page, cancel in re.findall(
                      r'^([0-9.]+) (\w+) page (\d+)/1834 cancel=(true|false)$', log, re.M)]
        assert events and all(a[0] <= b[0] for a, b in zip(events, events[1:]))
        assert all(fraction < 1 and value != 'completed' for fraction, value, _, _ in events)
        assert [(value, page) for _, value, page, cancel in events if cancel] == [
            (stage, 900 if stage == 'reconstructing' else 0)]
        assert [page for _, value, page, _ in events if value == 'extracting'] == list(range(1, 1835))
        assert not list((directory / f'cancel-{stage}').iterdir())
        if stage == 'writing':
            assert [page for _, value, page, _ in events if value == 'reconstructing'] == list(range(1, 1835))
        checked[stage] = result | {'progressMonotonic': True, 'triggerVerified': True,
                                    'noFalseCompletion': True}
    return checked


def inspect(epub):
    """Bounded chapter-at-a-time inspection; images are hashed without expanding all assets."""
    pages, markers, page = {}, [], None
    with zipfile.ZipFile(epub) as archive:
        entries = archive.infolist()
        assert len(entries) <= MAXIMUM_ENTRIES and sum(e.file_size for e in entries) <= BUDGET
        assert len({e.filename for e in entries}) == len(entries)
        package = ET.fromstring(archive.read('EPUB/package.opf'))
        manifest = {n.get('id'): n.get('href') for n in package.find(OPF + 'manifest')}
        chapter_hashes = []
        for item in package.find(OPF + 'spine'):
            name = 'EPUB/' + manifest[item.get('idref')]
            data = archive.read(name)
            # Image format alone may change. The entire remaining XHTML must match.
            chapter_hashes.append(hashlib.sha256(data.replace(b'.jpg"', b'.png"')).hexdigest())
            body = ET.fromstring(data).find(HTML + 'body')

            def walk(node, caption=False):
                nonlocal page
                if 'pagebreak' in node.get(EPUB + 'type', '').split():
                    page = int(node.attrib['id'].removeprefix('page-'))
                    assert page not in pages
                    markers.append(page)
                    pages[page] = {'text': '', 'images': []}
                caption = caption or node.tag == HTML + 'figcaption'
                if page is not None and node.tag == HTML + 'img':
                    pages[page]['images'].append('EPUB/' + node.attrib['src'])
                if page is not None and not caption:
                    pages[page]['text'] += node.text or ''
                for child in node:
                    walk(child, caption)
                    if page is not None and not caption:
                        pages[page]['text'] += child.tail or ''
                if page is not None and node.tag in {HTML + t for t in ['p', 'pre', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6']}:
                    pages[page]['text'] += ' '

            walk(body)
        assert markers == list(range(1, 1835)), 'Missing/reordered source anchors'
        for number, phrases in PHRASES.items():
            text = ' '.join(pages[number]['text'].split())
            assert all(p in text for p in phrases), (number, text)
        for number in REVIEW_PAGES:
            assert pages[number]['images'], ('Missing reviewed image', number)
        images = {}
        for entry in entries:
            if not entry.filename.startswith('EPUB/images/'):
                continue
            with archive.open(entry) as stream:
                sha = hashlib.file_digest(stream, 'sha256').hexdigest()
            with archive.open(entry) as stream, Image.open(stream) as image:
                size, format_name = image.size, image.format
            images[entry.filename] = {'sha256': sha, 'bytes': entry.file_size,
                                       'size': size, 'format': format_name}
    return {'entryBytes': sum(e.file_size for e in entries), 'epubBytes': epub.stat().st_size,
            'epubSHA256': digest(epub), 'chapterHashesIgnoringImageExtension': chapter_hashes,
            'pages': pages, 'images': images}


def compare(before, after):
    assert before['chapterHashesIgnoringImageExtension'] == after['chapterHashesIgnoringImageExtension']
    assert set(before['pages']) == set(after['pages'])
    same, changed = 0, 0
    for number, page in before['pages'].items():
        other = after['pages'][number]
        assert page['text'] == other['text'], ('Text differs', number)
        assert [Path(p).stem for p in page['images']] == [Path(p).stem for p in other['images']]
        for first, second in zip(page['images'], other['images']):
            a, b = before['images'][first], after['images'][second]
            assert a['size'] == b['size'], ('Raster size differs', number, first)
            if second.endswith('.png'):
                assert a['sha256'] == b['sha256'], ('PNG crop differs', number, first)
                same += 1
            else:
                assert b['format'] == 'JPEG'
                changed += 1
    return {'all1834OrderedPageAnchors': True, 'allSpineXHTMLIdenticalExceptImageExtensions': True,
            'allImageOrderAndDimensionsIdentical': True, 'unchangedPNGImages': same,
            'fullPageJPEGImages': changed, 'sourceReviewedTextChecks': sum(map(len, PHRASES.values())),
            'sourceReviewedImagePresenceChecks': len(REVIEW_PAGES)}


def review_images(before, after, work):
    """Write only actual EPUB assets, plus numerical differences for manual source review."""
    review = work / 'review'
    review.mkdir(exist_ok=True)
    samples = []
    with zipfile.ZipFile(work / 'png' / (CASE + '.epub')) as original, \
         zipfile.ZipFile(work / 'jpeg' / (CASE + '.epub')) as candidate:
        for page in REVIEW_PAGES:
            for index, (a, b) in enumerate(zip(before['pages'][page]['images'], after['pages'][page]['images'])):
                for label, archive, name in [('png', original, a), ('jpeg', candidate, b)]:
                    (review / f'page-{page}-{index}-{label}{Path(name).suffix}').write_bytes(archive.read(name))
                with original.open(a) as stream, Image.open(stream) as image:
                    first = image.convert('RGB')
                with candidate.open(b) as stream, Image.open(stream) as image:
                    second = image.convert('RGB')
                difference = ImageStat.Stat(ImageChops.difference(first, second))
                mse = sum(v * v for v in difference.rms) / 3
                samples.append({'page': page, 'index': index, 'original': a, 'candidate': b,
                                'dimensions': first.size, 'meanAbsoluteChannelError': difference.mean,
                                'PSNRdB': 10 * math.log10(255**2 / mse) if mse else None,
                                'identicalPixels': mse == 0})
    save(work / 'image-review.json', samples)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--converter', type=Path, required=True)
    parser.add_argument('--epubcheck', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--inspect-only', action='store_true')
    parser.add_argument('--default-evaluation', type=Path)
    parser.add_argument('--cancellation-evaluation', type=Path)
    args = parser.parse_args()
    converter = args.converter.resolve(strict=True)
    case = next(c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents'] if c['id'] == CASE)
    assert case['sha256'] == SOURCE_SHA256 and case['bytes'] == 219876258 and case['pages'] == 1834
    source = ROOT / 'corpus/cache' / case['filename']
    assert digest(source) == case['sha256'] and source.stat().st_size == case['bytes']
    with source.open('rb') as stream:
        assert hashlib.file_digest(stream, 'sha512').hexdigest() == case['publisherSHA512']
    work = args.output.resolve()
    if not args.inspect_only:
        work.mkdir(parents=True, exist_ok=False)
        assert shutil.disk_usage(work).free >= 12 * 1024**3, 'Need 12 GiB free for full-book trials'
        save(work / 'identity.json', {'source': case, 'converterSHA256': digest(converter),
                                      'measurementScriptSHA256': digest(Path(__file__))})
        for policy in ['png', 'jpeg']:
            flags = ['--full-page-image-encoding', 'png' if policy == 'png' else 'jpeg:0.9',
                     '--maximum-output-bytes', str(BUDGET), '--maximum-epub-bytes', str(BUDGET)]
            launcher = work / (policy + '.sh')
            launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(str(converter)) + ' "$@" ' + shlex.join(flags) + '\n')
            launcher.chmod(0o700)
            with (work / (policy + '-evaluation.log')).open('w') as log:
                run = subprocess.run([sys.executable, str(ROOT / 'tools/evaluate-real-document.py'),
                    '--case', CASE, '--pdf', str(source), '--converter', str(launcher),
                    '--output', str(work / policy), '--epubcheck', str(args.epubcheck.resolve()),
                    '--timeout', '1800'], stdout=log, stderr=subprocess.STDOUT)
            raw = work / policy / 'result.json'
            result = json.loads(raw.read_text())
            result.pop('conversionReport', None)
            result['rawResultSHA256'] = digest(raw)
            result['launcherSHA256'] = result.pop('converterSHA256')
            result['converterSHA256'] = digest(converter)
            result['options'] = {'referenceImages': 'automatic', 'fullPageImageEncoding': flags[1],
                'regionImageEncoding': 'png', 'rasterDPI': 180, 'maximumRasterPixels': 12000000,
                'maximumOutputBytes': BUDGET, 'maximumEPUBBytes': BUDGET, 'ocr': 'automatic'}
            result['receiptNote'] = 'The raw evaluator assumes defaults; this receipt records the explicit launcher flags and actual executable identity.'
            save(work / policy / 'effective-result.json', result)
            assert run.returncode == 0, (policy, result)
            assert not list((work / policy).glob('.pdfreflow-*'))
            print(f'PASS {policy}: {result["conversionSeconds"]:.2f}s; {result["outputBytes"]} bytes', flush=True)
    if args.default_evaluation:
        save(work / 'default-failure.json', check_default(args.default_evaluation))
    if args.cancellation_evaluation:
        save(work / 'cancellation-checks.json', check_cancellation(args.cancellation_evaluation))
    inspected = {}
    assert json.loads((work / 'identity.json').read_text())['converterSHA256'] == digest(converter)
    for policy in ['png', 'jpeg']:
        assert json.loads((work / policy / 'effective-result.json').read_text())['runPassed'] is True
        inspected[policy] = inspect(work / policy / (CASE + '.epub'))
        save(work / policy / 'inspection.json', inspected[policy])
    summary = compare(inspected['png'], inspected['jpeg'])
    for policy in ['png', 'jpeg']:
        report = json.loads((work / policy / 'conversion-report.json').read_text())
        summary[policy] = {k: inspected[policy][k] for k in ['epubBytes', 'entryBytes', 'epubSHA256']}
        summary[policy].update({k: report[k] for k in ['pageCount', 'reflowedPageCount', 'recognizedPageCount', 'imageCount']})
    first_report = json.loads((work / 'png/conversion-report.json').read_text())
    second_report = json.loads((work / 'jpeg/conversion-report.json').read_text())
    assert first_report['warnings'] == second_report['warnings']
    summary['warningsIdentical'] = True
    for number in UNREFLOWED_SOURCE:
        assert not inspected['png']['pages'][number]['text'].strip()
        assert len(inspected['png']['pages'][number]['images']) == 1
        assert any(w['code'] == 'pageImageFallback' and w['page'] == number for w in first_report['warnings'])
    summary['reviewedSourceTextPreservedOnlyAsImage'] = UNREFLOWED_SOURCE
    review_images(inspected['png'], inspected['jpeg'], work)
    save(work / 'comparison.json', summary)
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
