#!/usr/bin/env python3
"""usage: case.py <case-id> [base] [cand] [compare]  lanes for one corpus case, then compare them.

With no labels: base, cand, then compare. `compare` alone compares lanes left by earlier calls."""
import json, os, shutil, subprocess, sys, time
from pathlib import Path
# Work directory holding bin/{base,cand,probe}; lane outputs are written there and deleted.
S = os.environ['SYMBOL_FONTS_WORK']
W = str(Path(__file__).resolve().parents[3])
KEEP = W + '/measurements/symbol-fonts-and-script-bases/lane-summaries'
case = sys.argv[1]
labels = sys.argv[2:] or ["base", "cand", "compare"]
os.makedirs(KEEP, exist_ok=True); os.makedirs(S + '/lane', exist_ok=True)
for label in [l for l in labels if l != "compare"]:
    free = shutil.disk_usage('/System/Volumes/Data').free / 2**30
    if free < 8:
        print(f'only {free:.1f} GB free; stopping'); sys.exit(3)
    out = f'{S}/lane/{label}-{case}'
    shutil.rmtree(out, ignore_errors=True)
    start = time.time()
    with open(out + '.log', 'w') as log:
        rc = subprocess.run(['python3', 'tools/run_corpus_regressions.py', '--converter', f'{S}/bin/{label}',
                             '--epubcheck', '/opt/homebrew/bin/epubcheck', '--output', out, '--case', case,
                             '--environment-probe', f'{S}/bin/probe', '--execution-context', 'host-terminal'],
                            cwd=W, stdout=log, stderr=subprocess.STDOUT).returncode
    summary = json.load(open(out + '/summary.json'))
    print(f'{label}: rc={rc} free={free:.0f}G secs={time.time() - start:.0f} passed={summary.get("passed")}')
    for result in summary['results']:
        for error in result['errors']:
            print('   ', error[:400])
    shutil.copy(out + '/summary.json', f'{KEEP}/{label}-{case}.json')
if "compare" not in labels:
    sys.exit()
cmp = f'{S}/lane/cmp-{case}'
shutil.rmtree(cmp, ignore_errors=True)
with open(f'{KEEP}/compare-{case}.json', 'w') as out, open(f'{S}/lane/compare-{case}.err', 'w') as err:
    rc = subprocess.run(['python3', 'tools/compare_conversion_runs.py', '--baseline', f'{S}/lane/base-{case}/{case}',
                         '--candidate', f'{S}/lane/cand-{case}/{case}', '--output', cmp, '--allow-different-converters'],
                        cwd=W, stdout=out, stderr=err).returncode
print('compare rc', rc, open(f'{S}/lane/compare-{case}.err').read()[:500])
comparison = json.load(open(f'{KEEP}/compare-{case}.json'))
for key, value in comparison.items():
    text = json.dumps(value)
    print(' ', key, len(value) if isinstance(value, list) else '', text[:600])
shutil.rmtree(cmp, ignore_errors=True)
