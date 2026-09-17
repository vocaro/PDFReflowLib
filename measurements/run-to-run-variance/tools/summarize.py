import json, sys, re
from pathlib import Path

out = Path(sys.argv[1])
load = Path(sys.argv[2]).read_text().split('\n') if len(sys.argv) > 2 else []
r = json.loads((out / 'result.json').read_text())
rep = r.get('conversionReport', {})
warnings = rep.get('warnings', [])
retried = sorted(w['page'] for w in warnings if w.get('code') == 'ocrUsed' and 'two overlapping bands' in w.get('message', ''))
uncovered = sorted(w['page'] for w in warnings if w.get('code') == 'ocrUsed' and 'still outside' in w.get('message', ''))
ocr = sorted(w['page'] for w in warnings if w.get('code') == 'ocrUsed')
mib = lambda b: round(b / 1048576, 1) if b else None
summary = {
    'label': out.name, 'exit': r.get('conversionExitCode'), 'seconds': round(r.get('conversionSeconds', 0), 1),
    'cpu': round(r.get('converterCPUSeconds', 0), 1),
    'peakRSSMiB': mib(r.get('converterPeakRSSBytes')), 'peakFootprintMiB': mib(r.get('converterPeakPhysicalFootprintBytes')),
    'sampledFootprintMiB': mib(r.get('sampledPeakPhysicalFootprintBytes')),
    'epub': (r.get('outputSHA256') or '')[:16], 'ocrPages': len(ocr), 'retried': retried, 'retriedCount': len(retried),
    'stillUncovered': uncovered, 'programs': r['visionModelCache']['after']['programsSHA256'][:16],
    'programsChanged': r['visionModelCache']['before']['programsSHA256'] != r['visionModelCache']['after']['programsSHA256'],
    'load': [l for l in load if l],
}
(out / 'summary.json').write_text(json.dumps(summary) + '\n')
print(json.dumps(summary))
