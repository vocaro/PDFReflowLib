"""usage: lane.py <case> <label> [--compare-only]  (run from the worktree root)
Runs one corpus case with bin/pdf-reflow-<label>; for labels other than base, compares with base.
"""
import json
import os
import shutil
import subprocess
import sys

S = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
case, label = sys.argv[1], sys.argv[2]
out = f'{S}/{label}-{case}'
if '--compare-only' not in sys.argv:
    st = os.statvfs('/System/Volumes/Data')
    free = st.f_bavail * st.f_frsize / 2**30
    print(f'free {free:.1f} GB')
    if free < 5:
        sys.exit('STOP: under 5 GB free')
    shutil.rmtree(out, ignore_errors=True)
    r = subprocess.run(['python3', 'tools/run_corpus_regressions.py', '--converter', f'{S}/bin/{label}/pdf-reflow',
                        '--epubcheck', '/opt/homebrew/bin/epubcheck', '--output', out, '--case', case,
                        '--environment-probe', '.build/raster-environment/probe', '--execution-context', 'host-terminal'],
                       capture_output=True, text=True)
    lines = [l for l in (r.stdout + r.stderr).splitlines() if 'NOT RUN' not in l and 'NOT COVERED' not in l]
    print('\n'.join(lines[-15:]))
if label != 'base':
    cmp = f'{S}/cmp-{case}.json'
    subprocess.run(['python3', 'tools/compare_conversion_runs.py', '--baseline', f'{S}/base-{case}/{case}',
                    '--candidate', f'{out}/{case}', '--output', cmp, '--allow-different-converters'],
                   capture_output=True)
    d = json.load(open(cmp))
    keep = ['passed', 'provenanceErrors', 'changedPages', 'changedImages', 'navigationChanged',
            'changedNavigationPages', 'pageMarkersEqual', 'changedReportFields']
    print({k: d.get(k) for k in keep})
    with open(f'{S}/pagediff-{case}.txt', 'w') as f:
        subprocess.run(['python3', f'{S}/tools/pagediff.py', os.getcwd(), f'{S}/base-{case}/{case}/{case}.epub',
                        f'{out}/{case}/{case}.epub', '--width', '400'], stdout=f)
    print(open(f'{S}/pagediff-{case}.txt').read().splitlines()[-1])
