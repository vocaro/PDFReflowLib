"""Byte-level identity of two conversions.

Every archive entry must match exactly, in the same order, except for the package
identifier and modification timestamp that vary per run. The conversion reports must match
except for the output path. This is stricter than the corpus comparison: it detects any
serialization drift, not only parsed-content drift.
"""
import argparse
import json
from pathlib import Path
import re
import sys
import zipfile

VOLATILE = [
    (re.compile(rb'<dc:identifier id="book-id">[^<]*</dc:identifier>'), b'<dc:identifier id="book-id">IDENTIFIER</dc:identifier>'),
    (re.compile(rb'<meta property="dcterms:modified">[^<]*</meta>'), b'<meta property="dcterms:modified">MODIFIED</meta>'),
]
PACKAGE = 'EPUB/package.opf'
REPORT_VOLATILE = {'outputURL'}


def normalize_package(data):
    for pattern, replacement in VOLATILE:
        data, count = pattern.subn(replacement, data)
        if count != 1:
            raise ValueError(f'package document must contain exactly one {replacement!r}')
    return data


def compare_epubs(baseline, candidate):
    """Return a list of human-readable differences; an empty list means identical."""
    differences = []
    with zipfile.ZipFile(baseline) as first, zipfile.ZipFile(candidate) as second:
        names_a = [entry.filename for entry in first.infolist()]
        names_b = [entry.filename for entry in second.infolist()]
        if names_a != names_b:
            missing = sorted(set(names_a) - set(names_b))
            extra = sorted(set(names_b) - set(names_a))
            if missing:
                differences.append(f'missing in candidate: {missing[:5]}{"..." if len(missing) > 5 else ""}')
            if extra:
                differences.append(f'extra in candidate: {extra[:5]}{"..." if len(extra) > 5 else ""}')
            if not missing and not extra:
                differences.append('entry order differs')
        for name in names_a:
            if name not in names_b:
                continue
            data_a = first.read(name)
            data_b = second.read(name)
            if name == PACKAGE:
                data_a = normalize_package(data_a)
                data_b = normalize_package(data_b)
            if data_a != data_b:
                differences.append(f'{name}: {len(data_a)} vs {len(data_b)} bytes differ')
    return differences


def compare_reports(baseline, candidate):
    """Compare two CLI conversion reports (JSON) ignoring only the output path."""
    first = json.loads(Path(baseline).read_text())
    second = json.loads(Path(candidate).read_text())
    for key in REPORT_VOLATILE:
        first.pop(key, None)
        second.pop(key, None)
    differences = []
    for key in sorted(set(first) | set(second)):
        if first.get(key) != second.get(key):
            differences.append(f'report {key} differs')
    return differences


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-epub', required=True, type=Path)
    parser.add_argument('--candidate-epub', required=True, type=Path)
    parser.add_argument('--baseline-report', type=Path)
    parser.add_argument('--candidate-report', type=Path)
    args = parser.parse_args()
    differences = compare_epubs(args.baseline_epub, args.candidate_epub)
    if args.baseline_report and args.candidate_report:
        differences += compare_reports(args.baseline_report, args.candidate_report)
    for line in differences:
        print(line)
    print('identical' if not differences else f'{len(differences)} difference(s)')
    return 0 if not differences else 1


if __name__ == '__main__':
    sys.exit(main())
