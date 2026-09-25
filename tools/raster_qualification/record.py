#!/usr/bin/env python3
"""Extract small repository summaries from an externally retained device capture archive."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    rows = json.loads(gzip.decompress((args.capture / 'comparison.json.gz').read_bytes()))
    for row in rows:
        row.pop('textDrift', None)  # Counts/page numbers suffice; full transcripts stay external.
    args.destination.mkdir(parents=True, exist_ok=False)
    identity = json.loads((args.capture / 'identity.json').read_text())
    identity['settings'].pop('device', None)
    identity['deviceIdentifierRedacted'] = True
    (args.destination / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
    (args.destination / 'summary.json').write_text(json.dumps(rows, indent=2) + '\n')
    captures = []
    for path in sorted(args.capture.glob('*.gz')):
        data = path.read_bytes()
        captures.append({'file': path.name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    (args.destination / 'capture-digests.json').write_text(json.dumps(captures, indent=2) + '\n')
    table = ['| Book | DPI | Seconds | EPUB MiB | Peak RSS MiB | Sampled footprint MiB | OCR pages | Reflow pages | Images | Text pages changed vs baseline | Raw errors | Normalized errors |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for row in rows:
        m = row['metrics']
        if m['status'] != 'completed':
            seconds = f'{m["seconds"]:.1f}' if 'seconds' in m else 'unmeasured'
            rss = f'{m["peakRSSBytes"]/1048576:.1f}' if 'peakRSSBytes' in m else 'unmeasured'
            footprint = f'{m["sampledPeakFootprintBytes"]/1048576:.1f}' if 'sampledPeakFootprintBytes' in m else 'unmeasured'
            table.append(f'| {m["case"]} | {m["rasterDPI"]} | {seconds} | {m["status"]} | {rss} | {footprint} | — | — | — | — | — | — |')
            continue
        normalized = row.get('normalizedImageDiagnostic')
        cells = [m['case'], str(m['rasterDPI']), f'{m["seconds"]:.1f}', f'{m["epubBytes"]/1048576:.1f}',
                 f'{m["peakRSSBytes"]/1048576:.1f}', f'{m["sampledPeakFootprintBytes"]/1048576:.1f}',
                 str(row['recognizedPages']), str(row['reflowedPages']), str(row['images']),
                 str(len(row['changedTextPages'])), str(len(row['rawContent']['errors'])),
                 str(len(normalized['errors'])) if normalized else '—']
        table.append('| ' + ' | '.join(cells) + ' |')
    (args.destination / 'table.md').write_text('\n'.join(table) + '\n')


if __name__ == '__main__':
    main()
