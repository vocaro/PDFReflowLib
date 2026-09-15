#!/usr/bin/env python3
"""Create a local nine-page review derivative of the pinned Warren corpus (requires pypdf)."""
import argparse
import hashlib
import json
from pathlib import Path
from pypdf import PdfReader, PdfWriter

ROOT = Path(__file__).resolve().parents[2]
PAGES = [1, 7, 21, 30, 50, 100, 890, 910, 920]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pdf', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    case = next(item for item in json.loads((ROOT / 'Corpus/manifest.json').read_text())['documents']
                if item['id'] == 'gpo-warren-1964')
    if args.pdf.stat().st_size != case['bytes'] or digest(args.pdf) != case['sha256']:
        parser.error('Source differs from the pinned corpus PDF')
    if args.output.exists():
        parser.error('Output already exists')
    reader = PdfReader(args.pdf)
    writer = PdfWriter()
    for page in PAGES:
        writer.add_page(reader.pages[page - 1])
    writer.add_metadata({'/Title': 'Warren Commission Report - nine-page development excerpt (not the complete report)'})
    with args.output.open('xb') as stream:
        writer.write(stream)
    assert len(PdfReader(args.output).pages) == len(PAGES)
    print(json.dumps({'sourceSHA256': case['sha256'], 'excerptSHA256': digest(args.output),
                      'excerptBytes': args.output.stat().st_size,
                      'pageMap': [{'excerptPage': i, 'sourcePage': n} for i, n in enumerate(PAGES, 1)]}, indent=2))


if __name__ == '__main__':
    main()
