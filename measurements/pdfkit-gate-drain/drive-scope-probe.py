"""Run a probe binary repeatedly per mode, counting crashes; stop after a time budget.

usage: drive.py binary fixture iterations budget_seconds mode [mode...]
Modes run round-robin so machine load affects each equally. Appends to drive-log.jsonl.
"""
import json, os, subprocess, sys, time
here = os.path.dirname(os.path.abspath(__file__))
binary, fixture, iterations, budget = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])
modes = sys.argv[5:]
stats = {m: {'runs': 0, 'crashes': 0, 'failures': 0, 'seconds': 0.0} for m in modes}
start = time.monotonic()
while time.monotonic() - start < budget:
    for m in modes:
        t = time.monotonic()
        p = subprocess.run([binary, fixture, m, str(iterations)], capture_output=True, text=True, timeout=600)
        s = stats[m]
        s['runs'] += 1
        s['seconds'] += time.monotonic() - t
        if p.returncode != 0:
            s['crashes'] += 1
            tail = p.stderr.strip().splitlines()[-3:] if p.stderr else []
            print(f'CRASH {m} rc={p.returncode} {tail}', flush=True)
        elif 'failures=0' not in p.stdout:
            s['failures'] += 1
            print(f'FAIL {m} {p.stdout.strip()}', flush=True)
load = os.getloadavg()
record = {'binary': os.path.basename(binary), 'fixture': os.path.basename(fixture), 'iterations': iterations,
          'load': load, 'stats': stats, 'time': time.strftime('%Y-%m-%dT%H:%M:%S')}
with open(os.path.join(here, 'drive-log.jsonl'), 'a') as f:
    f.write(json.dumps(record) + '\n')
print(json.dumps(record, indent=1))
