"""Run the repository's native probe (base vs fix builds) round-robin under a time budget.

usage: drive2.py tag workers iterations budget_seconds variant [variant...]
Each run: probe-<variant> <fixture> native <workers> <iterations>, alternating the rolemap and
untagged fixtures. A run counts as a crash when it dies on a signal or exits non-zero.
Appends a record to drive2-log.jsonl.
"""
import json, os, subprocess, sys, time
here = os.path.dirname(os.path.abspath(__file__))
tag, workers, iterations, budget = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4])
variants = sys.argv[5:]
fixtures = [os.path.join(here, 'size1', f) for f in ('rolemap.pdf', 'untagged.pdf')]
stats = {v: {'runs': 0, 'crashes': 0, 'extractions': 0, 'seconds': 0.0} for v in variants}
start, n = time.monotonic(), 0
while time.monotonic() - start < budget:
    fixture = fixtures[n % 2]
    n += 1
    for v in variants:
        t = time.monotonic()
        p = subprocess.run([os.path.join(here, f'probe-{v}'), fixture, 'native', str(workers), str(iterations)],
                           capture_output=True, text=True, timeout=600)
        s = stats[v]
        s['runs'] += 1
        s['seconds'] += time.monotonic() - t
        if p.returncode != 0:
            s['crashes'] += 1
            reason = [l for l in p.stderr.splitlines() if 'reason' in l or 'NSFont' in l][:1]
            print(f'CRASH {v} {os.path.basename(fixture)} rc={p.returncode} {reason}', flush=True)
        else:
            s['extractions'] += max(1, workers) * iterations
record = {'tag': tag, 'workers': workers, 'iterations': iterations, 'load': os.getloadavg(),
          'stats': stats, 'time': time.strftime('%Y-%m-%dT%H:%M:%S')}
with open(os.path.join(here, 'drive2-log.jsonl'), 'a') as f:
    f.write(json.dumps(record) + '\n')
print(json.dumps(record))
