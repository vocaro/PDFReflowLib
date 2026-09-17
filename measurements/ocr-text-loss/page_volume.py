#!/usr/bin/env python3
"""Per-page EPUB volume of two evaluations (#116): words, images and the page's text start.

usage: page_volume.py <baseline evaluation dir> <candidate evaluation dir> <page>... [--text]
"""
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from check_corpus_content import read_pages  # noqa: E402


def load(directory):
    receipt = json.loads((Path(directory) / 'result.json').read_text())
    pages, _ = read_pages(Path(directory) / (receipt['case']['id'] + '.epub'))
    warnings = {}
    for warning in receipt['conversionReport']['warnings']:
        warnings.setdefault(warning.get('page'), []).append(warning['code'])
    return pages, warnings


def main():
    args = sys.argv[1:]
    text = '--text' in args
    args = [a for a in args if a != '--text']
    (base, base_warnings), (cand, cand_warnings) = load(args[0]), load(args[1])
    for page in map(int, args[2:]):
        for label, pages, warnings in (('base', base, base_warnings), ('cand', cand, cand_warnings)):
            p = pages.get(page) or {}
            words = p.get('text', '').split()
            print(f'p{page} {label}: words {len(words)} images {len(p.get("images", []))} '
                  f'warnings {sorted(set(warnings.get(page, [])))}')
            if text:
                print('    ' + ' '.join(words[:60]))


if __name__ == '__main__':
    main()
