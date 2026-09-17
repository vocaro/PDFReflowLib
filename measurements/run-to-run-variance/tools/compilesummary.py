import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text().splitlines()
name, verdicts, out = None, {}, []
for line in text:
    if line.startswith('== '):
        if name and verdicts:
            out.append((name, dict(verdicts)))
        name, verdicts = line[3:].split()[0], {}
    m = re.match(r'^(\d+)\t.*?first=(\d+)/(\w+)/.*?f=([\d.]+) loss=(\w+)', line)
    if m:
        verdicts[int(m[1])] = (m[3], float(m[4]), m[5] == 'true')
    m = re.match(r'programsSHA256 (\w+)', line)
    if m and name:
        verdicts['programs'] = m[1]
if name and verdicts:
    out.append((name, dict(verdicts)))
seen = {}
for name, v in out:
    print(name, 'programs', v.get('programs'),
          ' | '.join(f"p{p}: {v[p][0]} f={v[p][1]:.3f} retry={v[p][2]}" for p in sorted(k for k in v if isinstance(k, int))))
    key = v.get('programs')
    reads = tuple((p, v[p]) for p in sorted(k for k in v if isinstance(k, int)))
    seen.setdefault(key, set()).add(reads)
print()
for key, reads in seen.items():
    print('fingerprint', key, 'distinct reads', len(reads))
print('distinct fingerprints', len(seen), 'distinct read sets', len({r for s in seen.values() for r in s}))
