"""Run the final contract on base and candidate evaluations; save a compact result per side (from worktree root)."""
import json
import os
import subprocess

S = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M = 'measurements/caption-wraps-and-open-sentences/lane'
for name in os.listdir(M):
    if name.startswith('summary-base-'):
        os.remove(f'{M}/{name}')
for case, short in [('faa-phak-8083-25c', 'faa'), ('scotus-loper-bright-2024', 'scotus'), ('census-rrs2002-01', 'census')]:
    for label in ('base', 'cand'):
        r = subprocess.run(['python3', 'tools/check_corpus_content.py', '--case', case, '--evaluation', f'{S}/{label}-{case}/{case}'],
                           capture_output=True, text=True)
        d = json.loads(r.stdout)
        out = {'case': case, 'side': label, 'passed': d['passed'], 'contentChecks': d['contentChecks'], 'errors': d['errors']}
        json.dump(out, open(f'{M}/contract-{label}-{short}.json', 'w'), indent=2, ensure_ascii=False)
        print(short, label, d['passed'], d['contentChecks'], len(d['errors']))
