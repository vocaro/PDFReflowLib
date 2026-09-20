#!/usr/bin/env python3
"""Converts one cached corpus source and reports which pages recognition replaced.

Writes the EPUB to a temporary directory and deletes it immediately; only the conversion
report's warnings are kept. Used to choose the pages `probe-ocr-text-loss.swift` measures
(#116), so the measurement covers the pages the conversion actually recognizes rather than
every page of every book.

Usage: recognized_pages.py <converter> <pdf> [--ocr POLICY]
"""
import json
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path


def main():
    converter, source = sys.argv[1], sys.argv[2]
    extra = sys.argv[3:]
    with tempfile.TemporaryDirectory() as directory:
        out = Path(directory) / 'out.epub'
        finished = subprocess.run([converter, source, str(out), *extra],
                                  capture_output=True, text=True)
        if finished.returncode != 0:
            sys.exit(finished.stderr[-2000:])
        report = json.loads(finished.stdout)
    codes = Counter(w['code'] for w in report['warnings'])
    print(json.dumps({
        'source': Path(source).name,
        'options': extra,
        'pageCount': report['pageCount'],
        'recognizedPageCount': report['recognizedPageCount'],
        'warningCounts': dict(sorted(codes.items())),
        'ocrUsedPages': sorted({w['page'] for w in report['warnings'] if w['code'] == 'ocrUsed'}),
        'incompleteRecognitionPages': sorted({w['page'] for w in report['warnings']
                                              if w['code'] == 'incompleteRecognition'}),
        'incompleteRecognitionMessages': sorted({w['message'] for w in report['warnings']
                                                 if w['code'] == 'incompleteRecognition'}),
    }, indent=1))


if __name__ == '__main__':
    main()
