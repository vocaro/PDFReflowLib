#!/usr/bin/env python3
"""usage: survey.py probe outdir runs [case...]
Runs the pipeline probe `runs` times per English corpus document (each run a fresh process, so a
fresh hash seed) and reports pages whose block hashes differ between runs."""
import json, subprocess, sys, time, shutil
from pathlib import Path

W = Path('/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a1f4f642d57375727')
probe, out, runs = sys.argv[1], Path(sys.argv[2]), int(sys.argv[3])
wanted = sys.argv[4:]
out.mkdir(parents=True, exist_ok=True)
docs = json.loads((W / 'corpus/manifest.json').read_text())['documents']
report = {}
for d in docs:
    if d['id'] in ('uscis-m618-arabic-2015', 'irs-p596-zhs-2025') or (wanted and d['id'] not in wanted):
        continue
    if shutil.disk_usage('/System/Volumes/Data').free < 8 * 2**30:
        sys.exit('STOP: under 8 GiB free')
    load = subprocess.run(['uptime'], capture_output=True, text=True).stdout.split('averages:')[-1].strip()
    started = time.monotonic()
    outputs = []
    for r in range(runs):
        text = subprocess.run([probe, str(W / 'corpus/cache' / d['filename']), 'never'],
                              capture_output=True, text=True).stdout
        (out / f"{d['id']}-{r}.txt").write_text(text)
        outputs.append(dict(line.split('\t', 1) for line in text.splitlines() if '\t' in line))
    keys = sorted(set().union(*outputs))
    differing = [k for k in keys if len({o.get(k) for o in outputs}) > 1]
    report[d['id']] = {'seconds': round(time.monotonic() - started, 1), 'load': load, 'differing': differing}
    print(d['id'], report[d['id']], flush=True)
(out / 'report.json').write_text(json.dumps(report, indent=1))
