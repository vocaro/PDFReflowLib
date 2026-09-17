#!/usr/bin/env python3
"""usage: imagecounts.py <baseline.epub> <candidate.epub> <page>...  image counts per page, both runs."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from check_corpus_content import read_pages  # noqa: E402

base, _ = read_pages(sys.argv[1])
cand, _ = read_pages(sys.argv[2])
for number in map(int, sys.argv[3:]):
    print(number, len(base.get(number, {}).get('images', [])), '->', len(cand.get(number, {}).get('images', [])))
