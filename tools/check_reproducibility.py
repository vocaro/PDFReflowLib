#!/usr/bin/env python3
"""Convert each source twice with one converter binary and require identical output (#68).

Both conversions pin --package-identifier and --modification-date, so a deterministic
converter writes byte-identical EPUBs. The converter and source are hashed before the first
launch and after the last exit; a change refuses the case instead of comparing two builds.

Byte-identical EPUBs and equal reports (ignoring outputURL) pass. Otherwise a normalized
comparison runs: spine documents are concatenated and split at page markers, file names
are stripped from same-book links (spine packing may move), and every page's markup is
compared. Pages the report marks `ocrUsed` in both runs may differ (Vision output varies
between identical runs); they are reported, never silently ignored. Every other differing
page, ZIP entry, navigation entry, package field or report field fails.

This proves repeatability of one binary on one machine for the selected sources, not
correctness, cross-machine determinism, or determinism under every scheduling condition.
"""
import argparse
import hashlib
import html
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import time
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'Tests/PDFReflowLibTests/fixtures'
PINNED = ['--package-identifier', 'urn:uuid:00000000-0000-4000-8000-000000000001',
          '--modification-date', '2026-01-01T00:00:00Z']
OPF = '{http://www.idpf.org/2007/opf}'
PACKAGE = 'EPUB/package.opf'
REPORT_VOLATILE = {'outputURL'}
MAX_ENTRIES = 20000
MAX_UNCOMPRESSED_BYTES = 4 * 1024 ** 3
BODY = re.compile(r'^(.*?<body\b[^>]*>)(.*)(</body>.*)$', re.S)
PAGE_MARKER = re.compile(r'<[^>]*\bepub:type="[^"]*\bpagebreak\b[^"]*"[^>]*>')
MARKER_ID = re.compile(r'\bid="page-([1-9]\d*)"')
ELEMENT_ID = re.compile(r'\bid="([^"]+)"')
ANCHOR = re.compile(r'<a\b[^>]*\bhref="#([^"]*)"[^>]*>(.*?)</a>', re.S)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def ocr_pages(report):
    return {w['page'] for w in report.get('warnings') or []
            if isinstance(w, dict) and w.get('code') == 'ocrUsed' and isinstance(w.get('page'), int)}


def compare_reports(left, right, exempt):
    """Return (failures, OCR-page differences) between two CLI reports."""
    failures, allowed = [], []
    keys = sorted((left.keys() | right.keys()) - REPORT_VOLATILE - {'warnings'})
    failures += [f'report field {key}: {left.get(key)!r} vs {right.get(key)!r}'
                 for key in keys if key not in left or key not in right or left[key] != right[key]]
    def warnings(report, on_exempt):
        return [json.dumps(w, sort_keys=True) for w in report.get('warnings') or []
                if (isinstance(w, dict) and w.get('page') in exempt) == on_exempt]
    outside = warnings(left, False), warnings(right, False)
    if outside[0] != outside[1]:
        pages = sorted({json.loads(w).get('page') for w in set(outside[0]) ^ set(outside[1])}, key=str)
        failures.append(f'report warnings differ outside OCR pages (pages {pages})'
                        if pages else 'report warning order differs outside OCR pages')
    if warnings(left, True) != warnings(right, True):
        allowed.append('report warnings differ on OCR pages')
    return failures, allowed


class Package:
    """Parsed EPUB parts used by the normalized comparison."""

    def __init__(self, path):
        with zipfile.ZipFile(path) as archive:
            infos = archive.infolist()
            if len(infos) > MAX_ENTRIES or sum(i.file_size for i in infos) > MAX_UNCOMPRESSED_BYTES:
                raise ValueError('EPUB exceeds inspection bounds')
            self.names = [i.filename for i in infos]
            self.comment = archive.comment
            self.metadata = {i.filename: (i.date_time, i.compress_type, i.external_attr, i.extra) for i in infos}
            if len(set(self.names)) != len(self.names):
                raise ValueError('duplicate ZIP entries')
            self.hashes, self.entries = {}, {}
            for name in self.names:
                sha = hashlib.sha256()
                with archive.open(name) as stream:
                    while chunk := stream.read(1 << 20):
                        sha.update(chunk)
                        if name.endswith(('.xhtml', '.opf')):
                            self.entries[name] = self.entries.get(name, b'') + chunk
                self.hashes[name] = sha.hexdigest()
        package = ET.fromstring(self.entries[PACKAGE])
        items = {e.get('id'): e for e in package.find(OPF + 'manifest')}
        self.nav = next((str(PurePosixPath('EPUB') / e.get('href')) for e in items.values()
                         if 'nav' in (e.get('properties') or '').split()), None)
        self.spine = [str(PurePosixPath('EPUB') / items[r.get('idref')].get('href'))
                      for r in package.find(OPF + 'spine')]
        self.spine = [name for name in self.spine if name != self.nav]
        self.local = {PurePosixPath(name).name for name in self.spine}
        self.segments, self.wrappers = {}, []
        stream = ''
        for name in self.spine:
            match = BODY.match(self.entries[name].decode('utf-8'))
            if not match:
                raise ValueError(f'{name} has no body')
            self.wrappers.append(self.local_links(match.group(1) + match.group(3)))
            stream += self.local_links(match.group(2))
        page, start = 0, 0
        for marker in PAGE_MARKER.finditer(stream):
            number = MARKER_ID.search(marker.group(0))
            if not number:
                raise ValueError('page marker without page id')
            self.segments[page] = stream[start:marker.start()]
            page, start = int(number.group(1)), marker.start()
            if page in self.segments:
                raise ValueError(f'duplicate page marker {page}')
        self.segments[page] = stream[start:]
        self.id_pages = {m.group(1): number for number, markup in self.segments.items()
                         for m in ELEMENT_ID.finditer(markup)}

    def local_links(self, markup):
        for name in self.local:
            markup = markup.replace(f'href="{name}#', 'href="#')
        return markup

    def navigation(self, exempt):
        """Navigation skeleton and entries, omitting entries that target exempt pages."""
        if self.nav is None:
            return '', []
        markup = self.local_links(self.entries[self.nav].decode('utf-8'))
        entries = []
        for match in ANCHOR.finditer(markup):
            target = match.group(1)
            page = int(target[5:]) if re.fullmatch(r'page-[1-9]\d*', target) else self.id_pages.get(target)
            text = re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', '', match.group(2)))).strip()
            if page not in exempt or target.startswith('page-'):
                entries.append({'target': target, 'page': page, 'text': text})
        # List nesting is not compared here; heading levels are compared in the page markup.
        return re.sub(r'<a\b[^>]*>.*?</a>|</?(?:ol|li)\b[^>]*>', '', markup, flags=re.S), entries

    def package_skeleton(self):
        text = self.entries[PACKAGE].decode('utf-8')
        for name in self.spine:
            href = re.escape(str(PurePosixPath(name).relative_to('EPUB')))
            item = re.search(r'<item\b[^>]*\bhref="' + href + r'"[^>]*/>', text)
            identifier = re.search(r'\bid="([^"]+)"', item.group(0)).group(1)
            text = text.replace(item.group(0), '')
            text = re.sub(r'<itemref\b[^>]*\bidref="' + re.escape(identifier) + r'"[^>]*/>', '', text)
        return text


def compare_epubs(left_path, right_path, exempt):
    """Normalized comparison; returns failures, OCR-page differences and differing entries."""
    left, right = Package(left_path), Package(right_path)
    differing = sorted(name for name in set(left.names) | set(right.names)
                       if left.hashes.get(name) != right.hashes.get(name))
    failures, allowed = [], []
    structural = {PACKAGE, left.nav, right.nav, *left.spine, *right.spine}
    for name in differing:
        if name not in structural:
            pages = sorted({p for pkg in (left, right) for p, markup in pkg.segments.items()
                            if f'"{PurePosixPath(name).relative_to("EPUB")}"' in markup})
            failures.append(f'entry {name} differs' + (f' (referenced on pages {pages})' if pages else ''))
    if [n for n in left.names if n not in structural] != [n for n in right.names if n not in structural]:
        failures.append('non-content ZIP entry order differs')
    if left.spine == right.spine and left.names != right.names:
        failures.append('ZIP entry list or order differs')
    metadata = sorted(n for n in set(left.names) & set(right.names) if left.metadata[n] != right.metadata[n])
    if metadata:
        failures.append(f'ZIP entry metadata (date, compression, attributes) differs: {metadata[:5]}')
    if left.comment != right.comment:
        failures.append('ZIP archive comment differs')
    if left.spine != right.spine:
        allowed.append(f'spine packing differs ({len(left.spine)} vs {len(right.spine)} documents)')
        if not exempt:
            failures.append('spine packing differs without OCR pages')
    if set(left.wrappers) != set(right.wrappers):
        failures.append('spine document head/wrapper markup differs')
    if left.package_skeleton() != right.package_skeleton():
        failures.append(f'{PACKAGE} differs outside spine-document items')
    pages = sorted(left.segments.keys() | right.segments.keys())
    changed = [p for p in pages if left.segments.get(p) != right.segments.get(p)]
    if left.segments.keys() != right.segments.keys():
        failures.append('page markers differ')
    failing_pages = [p for p in changed if p not in exempt]
    ocr_changed = [p for p in changed if p in exempt]
    if failing_pages:
        failures.append(f'page markup differs on non-OCR pages {failing_pages}')
    if ocr_changed:
        allowed.append(f'page markup differs on OCR pages {ocr_changed}')
    (left_skeleton, left_nav), (right_skeleton, right_nav) = left.navigation(exempt), right.navigation(exempt)
    if left_skeleton != right_skeleton:
        failures.append('navigation document structure differs')
    if left_nav != right_nav:
        pages = sorted({e['page'] for e in left_nav + right_nav
                        if (e in left_nav) != (e in right_nav)}, key=str)
        failures.append(f'navigation entries differ outside OCR pages (pages {pages})')
    return {'differingEntries': differing, 'changedPages': changed, 'nonOCRChangedPages': failing_pages,
            'ocrChangedPages': ocr_changed, 'failures': failures, 'allowedDifferences': allowed}


def compare_runs(left_epub, right_epub, left_report, right_report):
    """Classify two conversions of one source by one binary."""
    exempt = ocr_pages(left_report)
    result = {'ocrPages': sorted(exempt | ocr_pages(right_report)),
              'epubSHA256': [digest(left_epub), digest(right_epub)]}
    failures, allowed = [], []
    if exempt != ocr_pages(right_report):
        failures.append(f'OCR page sets differ: {sorted(exempt)} vs {sorted(ocr_pages(right_report))}')
        exempt &= ocr_pages(right_report)
    report_failures, report_allowed = compare_reports(left_report, right_report, exempt)
    failures += report_failures
    allowed += report_allowed
    result['byteIdentical'] = result['epubSHA256'][0] == result['epubSHA256'][1]
    if not result['byteIdentical']:
        detail = compare_epubs(left_epub, right_epub, exempt)
        failures += detail.pop('failures')
        allowed += detail.pop('allowedDifferences')
        result.update(detail)
    result.update(failures=failures, allowedDifferences=allowed, passed=not failures)
    return result


def convert_twice(converter, source, directory, mode, timeout):
    """Launch both conversions; return per-run exit codes, seconds and paths."""
    runs = [{'epub': directory / f'run-{i}.epub', 'report': directory / f'run-{i}.json',
             'log': directory / f'run-{i}.log'} for i in (1, 2)]

    def launch(run):
        run['started'] = time.monotonic()
        with run['report'].open('w') as out, run['log'].open('w') as err:
            run['process'] = subprocess.Popen([str(converter), str(source), str(run['epub']), *PINNED],
                                              stdout=out, stderr=err)

    def finish(run):
        remaining = max(0.0, timeout - (time.monotonic() - run['started']))
        try:
            run['exitCode'] = run['process'].wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            run['process'].kill()
            run['process'].wait()
            run['exitCode'] = 'timeout'
        run['seconds'] = round(time.monotonic() - run['started'], 2)

    if mode == 'concurrent':
        for run in runs:
            launch(run)
        pending = list(runs)
        while pending:
            for run in list(pending):
                if run['process'].poll() is not None or time.monotonic() - run['started'] > timeout:
                    finish(run)
                    pending.remove(run)
            time.sleep(0.05)
    else:
        for run in runs:
            launch(run)
            finish(run)
    for run in runs:
        del run['process'], run['started']
    return runs


def check_source(label, source, converter, directory, mode, timeout, keep, expected_source=None):
    directory.mkdir()
    record = {'label': label, 'source': str(source), 'mode': mode, 'pinnedOptions': PINNED}
    record['sourceSHA256'] = digest(source)
    record['converterSHA256'] = digest(converter)
    errors = []
    if expected_source and record['sourceSHA256'] != expected_source:
        errors.append('source identity differs from its manifest')
    start = time.monotonic()
    runs = [] if errors else convert_twice(converter, source, directory, mode, timeout)
    record['wallSeconds'] = round(time.monotonic() - start, 2)
    record['runs'] = [{'exitCode': r['exitCode'], 'seconds': r['seconds']} for r in runs]
    if digest(converter) != record['converterSHA256']:
        errors.append('converter binary changed during the check; refusing to compare two builds')
    if digest(source) != record['sourceSHA256']:
        errors.append('source changed during the check')
    if not errors and any(r['exitCode'] != 0 for r in runs):
        errors.append('conversion failed; see run logs')
    if not errors:
        try:
            reports = [json.loads(r['report'].read_text()) for r in runs]
            record.update(compare_runs(runs[0]['epub'], runs[1]['epub'], *reports))
            errors += record.pop('failures')
        except (OSError, ValueError, KeyError, AttributeError, zipfile.BadZipFile) as error:
            errors.append(f'inspection failed: {error}')
    record['errors'] = errors
    record['passed'] = not errors
    if keep == 'never' or (keep == 'failed' and record['passed']):
        for run in runs:
            run['epub'].unlink(missing_ok=True)
    (directory / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--converter', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='new directory')
    parser.add_argument('--case', action='append', default=[], help='corpus case id (cached, identity-checked)')
    parser.add_argument('--pdf', action='append', type=Path, default=[], help='any PDF, labelled by file stem')
    parser.add_argument('--fixtures', action='store_true', help='the six bundled synthetic fixtures')
    parser.add_argument('--mode', choices=['concurrent', 'sequential'], default='concurrent',
                        help='launch both conversions together (default) or one after the other')
    parser.add_argument('--keep-epubs', choices=['never', 'failed', 'always'], default='failed',
                        help='EPUB retention after comparison (default: keep only failing cases)')
    parser.add_argument('--timeout', type=float, default=1800, help='seconds per conversion')
    args = parser.parse_args()
    sources = []
    if args.case:
        manifest = {c['id']: c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']}
        for name in args.case:
            if name not in manifest:
                parser.error(f'unknown corpus case {name}')
            path = ROOT / 'corpus/cache' / manifest[name]['filename']
            if not path.is_file():
                parser.error(f'missing cached PDF {path}; fetch it explicitly with tools/fetch_corpus.py')
            sources.append((name, path, manifest[name]['sha256']))
    if args.fixtures:
        for fixture in json.loads((FIXTURES / 'manifest.json').read_text())['fixtures']:
            sources.append((Path(fixture['file']).stem, FIXTURES / fixture['file'], fixture['sha256']))
    sources += [(path.stem, path.resolve(strict=True), None) for path in args.pdf]
    labels = [label for label, _, _ in sources]
    if not sources or len(labels) != len(set(labels)):
        parser.error('choose at least one source with distinct labels')
    if not args.timeout > 0:
        parser.error('timeout must be positive')
    converter = args.converter.resolve(strict=True)
    args.output.mkdir(parents=True, exist_ok=False)
    results = []
    for label, path, expected in sources:
        print(f'REPEAT {label} ({args.mode})', flush=True)
        record = check_source(label, path, converter, args.output / label, args.mode, args.timeout,
                              args.keep_epubs, expected)
        results.append(record)
        notes = '; '.join(record.get('allowedDifferences', []))
        state = 'identical bytes' if record.get('byteIdentical') else 'normalized'
        print(('PASS ' if record['passed'] else 'FAIL ') + label
              + f' in {record["wallSeconds"]}s'
              + (f' [{state}' + (f': {notes}' if notes else '') + ']' if 'byteIdentical' in record else '')
              + ''.join('\n  ' + error for error in record['errors']), flush=True)
    summary = {'passed': all(r['passed'] for r in results), 'converterSHA256': digest(converter),
               'mode': args.mode, 'results': results}
    (args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    return 0 if summary['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
