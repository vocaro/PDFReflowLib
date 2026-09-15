#!/usr/bin/env python3
"""Check reviewed positive content contracts separately from EPUB/resource validation.

No conversion or downloads. Uses a complete evaluator output and the pinned corpus manifest.
Phrase checks are page-specific; whitespace and inline styling do not affect matching.
"""
import argparse
import json
from pathlib import Path, PurePosixPath
import re
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HTML = '{http://www.w3.org/1999/xhtml}'
OPF = '{http://www.idpf.org/2007/opf}'
EPUB = '{http://www.idpf.org/2007/ops}'
BLOCKS = {HTML + tag for tag in ('p', 'h1', 'h2', 'h3', 'h4', 'pre', 'figure', 'li')}


def normalized(text):
    return ' '.join(text.split())


def read_pages(path):
    pages, markers = {}, []
    current = None
    with zipfile.ZipFile(path) as archive:
        if (len(archive.infolist()) > 10_000
                or sum(e.file_size for e in archive.infolist()) > 512 * 1024 * 1024):
            raise ValueError('EPUB exceeds inspection bounds')
        if len(set(archive.namelist())) != len(archive.namelist()):
            raise ValueError('Duplicate archive entries')
        package = ET.fromstring(archive.read('EPUB/package.opf'))
        manifest = {e.get('id'): e.get('href') for e in package.find(OPF + 'manifest')}
        for reference in package.find(OPF + 'spine'):
            chapter = PurePosixPath('EPUB') / manifest[reference.get('idref')]
            tree = ET.fromstring(archive.read(str(chapter)))

            def append(text):
                if current is not None:
                    pages[current]['text'] += text or ''

            def walk(element):
                nonlocal current
                if 'pagebreak' in element.get(EPUB + 'type', '').split():
                    anchor = element.get('id', '')
                    if not re.fullmatch(r'page-[1-9]\d*', anchor):
                        raise ValueError('Invalid page boundary')
                    current = int(anchor[5:])
                    if current in pages:
                        raise ValueError('Duplicate page boundary')
                    markers.append(current)
                    pages[current] = {'text': '', 'images': []}
                if element.tag == HTML + 'img' and current is not None:
                    asset = str(chapter.parent / element.attrib['src'])
                    if asset not in archive.namelist():
                        raise ValueError('Missing image asset: ' + asset)
                    pages[current]['images'].append(asset)
                # Generic converter captions must not satisfy source-text expectations.
                if element.tag == HTML + 'figcaption':
                    return
                append(element.text)
                for child in element:
                    walk(child)
                    append(child.tail)
                if element.tag in BLOCKS:
                    append(' ')

            walk(tree.find(HTML + 'body'))
    for page in pages.values():
        page['text'] = normalized(page['text'])
    return pages, markers


def assess(case, contract, result, report, pages, markers):
    errors = []
    if (contract['sourceSHA256'] != case['sha256'] or any(
            result.get('case', {}).get(k) != case[k] for k in ('id', 'sha256', 'bytes', 'pages'))):
        errors.append('Source identity differs from the reviewed contract')
    if result.get('runPassed') is not True or result.get('conversionExitCode') != 0:
        errors.append('Conversion/resource/progress evaluation did not pass')
    if report.get('pageCount') != case['pages'] or markers != list(range(1, case['pages'] + 1)):
        errors.append('Missing, duplicated or reordered source pages')
    if any('\ufffc' in page['text'] for page in pages.values()):
        errors.append('Object placeholder in semantic text')
    expected = contract['pages']
    numbers = [item['page'] for item in expected]
    if (not expected or len(numbers) != len(set(numbers))
            or any(type(p) is not int or not 1 <= p <= case['pages'] for p in numbers)):
        raise ValueError('Contract needs distinct in-range review pages')
    checks = 0
    for item in expected:
        number = item['page']
        page = pages.get(number, {'text': '', 'images': []})
        if not any(key in item for key in ('text', 'orderedText', 'minimumImages', 'warningCodesAnyOf')):
            raise ValueError('Review page has no expectations')
        for phrase in item.get('text', []):
            if not normalized(phrase):
                raise ValueError('Empty phrase')
            checks += 1
            if normalized(phrase) not in page['text']:
                errors.append(f'Page {number}: missing text {phrase!r}')
        cursor = 0
        for phrase in item.get('orderedText', []):
            if not normalized(phrase):
                raise ValueError('Empty ordered phrase')
            checks += 1
            index = page['text'].find(normalized(phrase), cursor)
            if index < 0:
                errors.append(f'Page {number}: missing or reordered text {phrase!r}')
            else:
                cursor = index + len(normalized(phrase))
        if 'minimumImages' in item:
            minimum = item['minimumImages']
            if type(minimum) is not int or minimum < 1:
                raise ValueError('Image minimum must be positive')
            checks += 1
            if len(page['images']) < minimum:
                errors.append(f'Page {number}: missing preserved images')
        if 'warningCodesAnyOf' in item:
            codes = item['warningCodesAnyOf']
            if not codes:
                raise ValueError('Empty warning expectation')
            checks += 1
            if not any(w.get('page') == number and w.get('code') in codes for w in report.get('warnings', [])):
                errors.append(f'Page {number}: missing quality warning')
    if checks == 0:
        raise ValueError('Contract has no content checks')
    return {'case': case['id'], 'passed': not errors, 'reviewPages': numbers,
            'contentChecks': checks, 'errors': errors,
            'scope': 'Reviewed positive text/order/image-presence checks; not full-book fidelity or image legibility qualification.'}


def check_evaluation(case, contract, directory):
    result = json.loads((directory / 'result.json').read_text())
    report = json.loads((directory / 'conversion-report.json').read_text())
    pages, markers = read_pages(directory / (case['id'] + '.epub'))
    return assess(case, contract, result, report, pages, markers)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', required=True)
    parser.add_argument('--evaluation', type=Path, required=True)
    args = parser.parse_args()
    cases = json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']
    contracts = json.loads((ROOT / 'corpus/regressions.json').read_text())['cases']
    case = next((c for c in cases if c['id'] == args.case), None)
    contract = next((c for c in contracts if c['id'] == args.case), None)
    if case is None or contract is None:
        parser.error('case has no reviewed content contract')
    try:
        assessment = check_evaluation(case, contract, args.evaluation)
    except (OSError, ValueError, KeyError, TypeError, AttributeError, ET.ParseError, zipfile.BadZipFile) as error:
        assessment = {'case': args.case, 'passed': False, 'errors': [str(error)]}
    print(json.dumps(assessment, indent=2))
    return 0 if assessment['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
