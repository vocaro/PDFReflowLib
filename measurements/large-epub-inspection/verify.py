#!/usr/bin/env python3
"""Check the shared reader against retained full NOAA outputs; no conversion or downloads."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import read_pages


def verify(directory):
    receipts = json.loads((ROOT / 'measurements/noaa-output-policies/comparison.json').read_text())
    results = {}
    for policy in ('png', 'jpeg'):
        path = directory / policy / 'noaa-nca5-2023.epub'
        previous = json.loads((directory / policy / 'inspection.json').read_text())
        with path.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        assert digest == receipts[policy]['epubSHA256'] == previous['epubSHA256']
        with zipfile.ZipFile(path) as archive:
            entries = len(archive.infolist())
            expanded = sum(entry.file_size for entry in archive.infolist())
        assert expanded == receipts[policy]['entryBytes'] == previous['entryBytes']
        rejections = []
        for limits in [{}, dict(max_entries=20000), dict(max_uncompressed_bytes=4 * 1024**3)]:
            try:
                read_pages(path, **limits)
            except ValueError as error:
                assert str(error) == 'EPUB exceeds inspection bounds'
                rejections.append(limits)
            else:
                raise AssertionError('Expected inspection bounds rejection')
        pages, markers = read_pages(path, max_entries=20000, max_uncompressed_bytes=4 * 1024**3)
        assert markers == list(range(1, 1835))
        assert sum(len(page['images']) for page in pages.values()) == 11245
        for number, page in pages.items():
            prior = previous['pages'][str(number)]
            assert page['images'] == prior['images'], number
            # Existing readers separate list/figure whitespace differently; preserve every
            # non-whitespace character and page assignment without equating their formatting.
            assert ''.join(page['text'].split()) == ''.join(prior['text'].split()), number
        results[policy] = dict(epubSHA256=digest, entries=entries, uncompressedBytes=expanded,
                               pages=len(pages), images=11245, rejectedLimits=rejections,
                               successfulLimits=dict(max_entries=20000, max_uncompressed_bytes=4 * 1024**3),
                               allPageTextAndImageOwnershipMatchesPrevious=True)
    return results


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--outputs', type=Path, required=True)
    print(json.dumps(verify(parser.parse_args().outputs), indent=2))
