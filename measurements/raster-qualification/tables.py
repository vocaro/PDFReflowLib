#!/usr/bin/env python3
"""Render the record's tables from a raster sweep's results.json (tools/raster_sweep.py).

Usage: python3 measurements/raster-qualification/tables.py --results RUN/results.json --targets targets.json
Prints Markdown; every number comes from the retained results, so the record can be regenerated.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import statistics

BASE = 180


def by_key(rows, **match):
    return [row for row in rows if all(row.get(key) == value for key, value in match.items())]


def one(rows, **match):
    found = by_key(rows, **match)
    return found[0] if len(found) == 1 else None


def fmt(value, digits=3):
    if value is None:
        return 'n/a'
    if isinstance(value, bool):
        return 'yes' if value else 'no'
    if isinstance(value, float):
        return f'{value:.{digits}f}'
    return str(value)


def storage_by_dpi(rows, classes, dpis):
    lines = ['| Class (pages) | ' + ' | '.join(f'{d} DPI' for d in dpis) + ' |', '| --- | ' + ' | '.join('---:' for _ in dpis) + ' |']
    for label, ids in classes.items():
        cells = []
        for dpi in dpis:
            part = [r for r in by_key(rows, kind='page', encoding='png', requestedDPI=dpi) if r['target'] in ids]
            total = sum(r['bytes'] for r in part)
            base = sum(r['bytes'] for r in by_key(rows, kind='page', encoding='png', requestedDPI=BASE) if r['target'] in ids)
            cells.append(f'{total / 1048576:.2f} ({100 * total / base - 100:+.0f}%)' if base else 'n/a')
        lines.append(f'| {label} ({len(ids)}) | ' + ' | '.join(cells) + ' |')
    cells = []
    for dpi in dpis:
        part = by_key(rows, kind='page', encoding='png', requestedDPI=dpi)
        total, pixels = sum(r['bytes'] for r in part), sum(r['pixels'] for r in part)
        base = sum(r['bytes'] for r in by_key(rows, kind='page', encoding='png', requestedDPI=BASE))
        cells.append(f'{total / 1048576:.2f} ({100 * total / base - 100:+.0f}%), {pixels / 1e6:.1f} Mpx')
    lines.append(f'| All ({len(set(r["target"] for r in rows))}) | ' + ' | '.join(cells) + ' |')
    return '\n'.join(lines)


def storage_by_encoding(rows, classes, encodings, dpi=BASE):
    lines = ['| Class (pages) | ' + ' | '.join(encodings) + ' |', '| --- | ' + ' | '.join('---:' for _ in encodings) + ' |']
    for label, ids in list(classes.items()) + [('All', None)]:
        cells = []
        for encoding in encodings:
            part = [r for r in by_key(rows, kind='page', encoding=encoding, requestedDPI=dpi) if ids is None or r['target'] in ids]
            png = [r for r in by_key(rows, kind='page', encoding='png', requestedDPI=dpi) if ids is None or r['target'] in ids]
            total, base = sum(r['bytes'] for r in part), sum(r['bytes'] for r in png)
            cells.append(f'{total / 1048576:.2f}' + ('' if encoding == 'png' else f' ({100 * total / base - 100:+.0f}%)'))
        lines.append(f'| {label}{"" if ids is None else f" ({len(ids)})"} | ' + ' | '.join(cells) + ' |')
    return '\n'.join(lines)


def per_target_bytes(rows, targets, encodings, dpi=BASE):
    lines = ['| Target | Page px | ' + ' | '.join(encodings) + ' | Region ' + ' | Region '.join(encodings) + ' |',
             '| --- | --- | ' + ' | '.join('---:' for _ in encodings * 2) + ' |']
    for target in targets:
        page = one(rows, target=target['id'], kind='page', encoding='png', requestedDPI=dpi)
        cells = [f"{page['width']} x {page['height']}"]
        for kind in ('page', 'region'):
            for encoding in encodings:
                row = one(rows, target=target['id'], kind=kind, encoding=encoding, requestedDPI=dpi)
                cells.append(f"{row['bytes']:,}")
        lines.append(f"| {target['id']} | " + ' | '.join(cells) + ' |')
    return '\n'.join(lines)


def fidelity_entry(row, kind):
    return next((f for f in row.get('fidelity', []) if f['kind'] == kind), None)


def glyph_table(rows, targets, settings, metric, view='normalized', kind='region'):
    lines = ['| Target | ' + ' | '.join(settings_label(s) for s in settings) + ' |',
             '| --- | ' + ' | '.join('---:' for _ in settings) + ' |']
    for target in targets:
        cells = []
        for dpi, encoding in settings:
            row = one(rows, target=target['id'], kind=kind, encoding=encoding, requestedDPI=dpi)
            entry = fidelity_entry(row, 'glyph') if row else None
            cells.append(fmt(entry[view].get(metric)) if entry else 'n/a')
        if any(cell != 'n/a' for cell in cells):
            lines.append(f"| {target['id']} | " + ' | '.join(cells) + ' |')
    return '\n'.join(lines)


def appearance_table(rows, targets, settings, metric, view='normalized', kind='region', kinds=('region', 'color')):
    lines = ['| Target (reference) | ' + ' | '.join(settings_label(s) for s in settings) + ' |',
             '| --- | ' + ' | '.join('---:' for _ in settings) + ' |']
    for target in targets:
        for reference in target['references']:
            if reference['kind'] not in kinds:
                continue
            cells = []
            for dpi, encoding in settings:
                row = one(rows, target=target['id'], kind=kind, encoding=encoding, requestedDPI=dpi)
                entry = next((f for f in (row or {}).get('fidelity', []) if f['reference'] == reference['reference']), None)
                cells.append(fmt(entry[view].get(metric)) if entry else 'n/a')
            if any(cell != 'n/a' for cell in cells):
                name = Path(reference['reference']).stem
                lines.append(f"| {target['id']} ({name}) | " + ' | '.join(cells) + ' |')
    return '\n'.join(lines)


def settings_label(setting):
    dpi, encoding = setting
    return f'{dpi} {encoding}'


def gate_view(rows, targets, dpis, kind='page'):
    """Raw checker pass counts (what the corpus gate would see) per DPI for PNG page images."""
    lines = ['| DPI | region passes | glyph passes | appearance passes | scale range |', '| ---: | ---: | ---: | ---: | --- |']
    for dpi in dpis:
        counts = defaultdict(lambda: [0, 0])
        scales = []
        for target in targets:
            row = one(rows, target=target['id'], kind=kind, encoding='png', requestedDPI=dpi)
            for entry in (row or {}).get('fidelity', []):
                raw = entry['raw']
                if 'regionPassed' in raw:
                    counts['region'][1] += 1
                    counts['region'][0] += bool(raw['regionPassed'])
                if entry['kind'] == 'glyph':
                    counts['glyph'][1] += 1
                    counts['glyph'][0] += bool(raw['passed'])
                if 'appearancePassed' in raw:
                    counts['appearance'][1] += 1
                    counts['appearance'][0] += bool(raw['appearancePassed'])
                    scales.append(raw['scale'])
        lines.append(f"| {dpi} | {counts['region'][0]}/{counts['region'][1]} | {counts['glyph'][0]}/{counts['glyph'][1]} | "
                     f"{counts['appearance'][0]}/{counts['appearance'][1]} | {min(scales):.3f}–{max(scales):.3f} |")
    return '\n'.join(lines)


def phrase_table(rows, targets, settings):
    lines = ['| Target (phrases) | ' + ' | '.join(settings_label(s) for s in settings) + ' |',
             '| --- | ' + ' | '.join('---:' for _ in settings) + ' |']
    for target in targets:
        if not target['expectedPhrases']:
            continue
        cells = []
        for dpi, encoding in settings:
            row = one(rows, target=target['id'], kind='region', encoding=encoding, requestedDPI=dpi)
            coverage = (row or {}).get('phraseCoverage')
            cells.append(str(coverage['found']) if coverage else 'n/a')
        lines.append(f"| {target['id']} ({len(target['expectedPhrases'])}) | " + ' | '.join(cells) + ' |')
    return '\n'.join(lines)


def psnr_table(rows, targets, encodings, dpi=BASE):
    lines = ['| Target | ' + ' | '.join(encodings) + ' |', '| --- | ' + ' | '.join('---:' for _ in encodings) + ' |']
    for target in targets:
        cells = []
        for encoding in encodings:
            row = one(rows, target=target['id'], kind='page', encoding=encoding, requestedDPI=dpi)
            cells.append(fmt(row['sameDPIPNGComparison']['rgbPSNRdB'], 1) if row else 'n/a')
        lines.append(f"| {target['id']} | " + ' | '.join(cells) + ' |')
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results', type=Path, required=True)
    args = parser.parse_args()
    results = json.loads(args.results.read_text())
    rows = results['images']
    targets = json.loads((args.results.parent / 'targets.json').read_text())
    dpis = results['identity']['dpis']
    encodings = ['png'] + [f'jpeg{round(q * 100)}' for q in results['identity']['qualities']]
    classes = defaultdict(list)
    for target in targets:
        classes[target['class']].append(target['id'])
    dpi_settings = [(d, 'png') for d in dpis]
    encoding_settings = [(BASE, e) for e in encodings]
    print('## Full-page PNG MiB by class and DPI (change relative to 180)\n')
    print(storage_by_dpi(rows, classes, dpis))
    print('\n## Full-page MiB at 180 DPI by encoding (change relative to PNG)\n')
    print(storage_by_encoding(rows, classes, encodings))
    print('\n## Per-target bytes at 180 DPI\n')
    print(per_target_bytes(rows, targets, encodings))
    print('\n## Same-raster RGB PSNR (dB) of full-page JPEGs at 180 DPI\n')
    print(psnr_table(rows, targets, encodings[1:]))
    print('\n## Probe process memory\n')
    print('| DPI | Peak RSS MiB | Peak footprint MiB | Seconds |\n| ---: | ---: | ---: | ---: |')
    for p in results['processes']:
        print(f"| {p['dpi']} | {p['peakRSSBytes'] / 1048576:.1f} | {p['peakPhysicalFootprintBytes'] / 1048576:.1f} | {p['elapsedSeconds']:.1f} |")
    print('\n## Glyph coverage (minimum tile ink ratio) of the region crop, resampled to 180 DPI, PNG by DPI\n')
    print(glyph_table(rows, targets, dpi_settings, 'coverage'))
    print('\n## Glyph extra ink of the region crop, resampled to 180 DPI, PNG by DPI\n')
    print(glyph_table(rows, targets, dpi_settings, 'extraInk'))
    print('\n## Glyph sharpness (median peak stroke darkness ratio), region crop resampled to 180 DPI, PNG by DPI\n')
    print(glyph_table(rows, targets, dpi_settings, 'sharpness'))
    print('\n## Glyph coverage at 180 DPI by encoding (region crop)\n')
    print(glyph_table(rows, targets, encoding_settings, 'coverage'))
    print('\n## Glyph extra ink at 180 DPI by encoding (region crop)\n')
    print(glyph_table(rows, targets, encoding_settings, 'extraInk'))
    print('\n## Ink contrast (2nd–98th percentile spread) of the region crop, resampled to 180 DPI, PNG by DPI\n')
    print(appearance_table(rows, targets, dpi_settings, 'contrast'))
    print('\n## Ink contrast at 180 DPI by encoding (region crop)\n')
    print(appearance_table(rows, targets, encoding_settings, 'contrast'))
    print('\n## Color agreement of the region crop, resampled to 180 DPI, PNG by DPI\n')
    print(appearance_table(rows, targets, dpi_settings, 'colorAgreement', kinds=('color',)))
    print('\n## Color agreement at 180 DPI by encoding (region crop)\n')
    print(appearance_table(rows, targets, encoding_settings, 'colorAgreement', kinds=('color',)))
    print('\n## Region correlation of the page image, resampled to 180 DPI, PNG by DPI\n')
    print(appearance_table(rows, targets, dpi_settings, 'correlation', kind='page', kinds=('region',)))
    print('\n## Corpus checkers applied raw to PNG page images (what the gate would see)\n')
    print(gate_view(rows, targets, dpis))
    print('\n## Reviewed phrases found by Vision in the region crop, PNG by DPI\n')
    print(phrase_table(rows, targets, dpi_settings))
    print('\n## Reviewed phrases found by Vision in the region crop at 180 DPI by encoding\n')
    print(phrase_table(rows, targets, encoding_settings))
    for dpi in [d for d in dpis if d != BASE]:
        print(f'\n## Reviewed phrases found at {dpi} DPI by encoding\n')
        print(phrase_table(rows, targets, [(dpi, e) for e in encodings]))


if __name__ == '__main__':
    main()
