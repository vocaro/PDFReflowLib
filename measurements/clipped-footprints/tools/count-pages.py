#!/usr/bin/env python3
"""Per-page reflowed word and image counts from converted EPUBs, for before/after comparison."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import read_pages  # noqa: E402


def counts(epub):
    pages, _ = read_pages(epub, max_entries=20000, max_uncompressed_bytes=4294967296)
    return {str(n): [len(p['text'].split()), len(p['images'])] for n, p in pages.items()}


def main():
    out = {}
    root = Path(sys.argv[1])
    for directory in sorted(root.iterdir()):
        if not directory.is_dir():
            continue
        epubs = list(directory.glob('*.epub'))
        if not epubs:
            continue
        try:
            out[directory.name] = {'pages': counts(epubs[0]), 'bytes': epubs[0].stat().st_size}
        except Exception as exc:  # noqa: BLE001 - recorded, not raised, so one bad case does not hide the rest
            out[directory.name] = {'error': repr(exc)}
    Path(sys.argv[2]).write_text(json.dumps(out, indent=1, sort_keys=True) + '\n')
    print('wrote', sys.argv[2], 'cases', len(out))


main()
