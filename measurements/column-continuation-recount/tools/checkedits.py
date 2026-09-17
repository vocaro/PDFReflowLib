#!/usr/bin/env python3
"""Check only the page entries addcontract.py edits against EPUBs (warning keys, which need the
conversion report, are left to the lane).

usage: checkedits.py <case-id> <epub>...
"""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from addcontract import EDITS  # noqa: E402
from check_corpus_content import assess, read_pages  # noqa: E402

name = sys.argv[1]
case = next(c for c in json.loads((ROOT / 'corpus/manifest.json').read_text())['documents'] if c['id'] == name)
contract = next(c for c in json.loads((ROOT / 'corpus/regressions.json').read_text())['cases'] if c['id'] == name)
edited = [dict((k, v) for k, v in entry.items() if k not in ('warningCodesAnyOf', 'absentWarningCodes'))
          for entry in contract['pages'] if entry['page'] in EDITS[name]]
mini = {'sourceSHA256': case['sha256'], 'pages': edited}
for path in sys.argv[2:]:
    pages, markers = read_pages(path, max_uncompressed_bytes=4 << 30, max_entries=100000)
    result = assess(case=case, contract=mini, result={'case': case, 'runPassed': True, 'conversionExitCode': 0},
                    report={'pageCount': case['pages'], 'warnings': []}, pages=pages, markers=markers)
    print(Path(path).name, 'passed' if result['passed'] else 'FAILED', f"checks={result.get('checks')}",
          f"errors={len(result['errors'])}")
    for error in result['errors']:
        print('   ', error)
