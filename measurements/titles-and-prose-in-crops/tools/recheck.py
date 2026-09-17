#!/usr/bin/env python3
"""Re-run the current corpus contracts against existing evaluation directories.

usage: recheck.py <case-id> <evaluation-dir>...   (each dir holds result.json, the report and the EPUB)
"""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import check_evaluation  # noqa: E402

name = sys.argv[1]
case = next(c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents'] if c['id'] == name)
contract = next(c for c in json.loads((ROOT / 'corpus/regressions.json').read_text())['cases'] if c['id'] == name)
for directory in sys.argv[2:]:
    result = check_evaluation(case, contract, Path(directory))
    print(directory.rstrip('/').split('/')[-2], 'passed' if result['passed'] else 'FAILED',
          f"checks={result.get('checks')}", f"errors={len(result.get('errors', []))}")
    for error in result.get('errors', []):
        print('   ', error)
