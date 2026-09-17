"""usage: timing.py <label> <pdf> [rounds]: wall time of base, bounded and unbounded conversions, back to back."""
import os
import subprocess
import sys
import time

S = '/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue117'
label, pdf = sys.argv[1], sys.argv[2]
rounds = int(sys.argv[3]) if len(sys.argv) > 3 else 2
times = {'base': [], 'bounded': [], 'unbounded': []}
binaries = {'base': 'pdf-reflow-base', 'bounded': 'pdf-reflow-cand', 'unbounded': 'pdf-reflow-unbounded'}
for r in range(rounds):
    order = ['base', 'bounded', 'unbounded'] if r % 2 == 0 else ['unbounded', 'bounded', 'base']
    for name in order:
        out = f'{S}/cost/{label}-{name}.epub'
        if os.path.exists(out):
            os.remove(out)
        start = time.monotonic()
        run = subprocess.run([f'{S}/bin/{binaries[name]}', pdf, out, '--ocr', 'never',
                              '--package-identifier', 'urn:uuid:00000000-0000-4000-8000-000000000001',
                              '--modification-date', '2026-01-01T00:00:00Z'], capture_output=True)
        elapsed = time.monotonic() - start
        times[name].append(elapsed if run.returncode == 0 else float('nan'))
        if os.path.exists(out):
            os.remove(out)
print(label, ' '.join(f'{k} {min(v):.2f}s' for k, v in times.items()), '| runs', {k: [round(x, 2) for x in v] for k, v in times.items()})
