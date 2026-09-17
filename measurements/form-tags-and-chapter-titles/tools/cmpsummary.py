import json, sys, glob, os
log, base, cand = sys.argv[1:4]
text = open(log).read()
try:
    report = json.loads(text[text.index('{'):])
except Exception:
    print(text[-1500:]); report = {}
def short(v):
    s = json.dumps(v); return s if len(s) < 400 else s[:400] + '…'
for k, v in report.items():
    if isinstance(v, list): print(f'  {k}: {len(v)} {short(v[:30])}')
    else: print(f'  {k}: {short(v)}')
for label, d in (('base', base), ('cand', cand)):
    r = json.load(open(os.path.join(d, 'result.json')))
    peak = r.get('converterPeakRSSBytes') or next((v for k, v in r.items() if 'PeakRSS' in k), None)
    rep = json.load(open(os.path.join(d, 'conversion-report.json')))
    w = rep.get('warnings', [])
    fb = {x['page'] for x in w if x.get('code') == 'structureFallback'}
    print(f'  {label}: passed={r.get("passed")} peakRSS={peak and round(peak / 1048576)}MiB warnings={len(w)} fallbackPages={len(fb)} images={rep.get("imageCount")}')
