"""Stage profile of the evaluator's 100 ms footprint samples for each run.

Progress percentages map to pipeline stages through PDFConverter's composition: extraction
ends at 57%, reconstruction at 82%, writing below 100%. For each run this reports the
footprint at the end of extraction (what survives into reconstruction), the reconstruction
peak, the writing peak, and the overall peak with the progress line where it occurred.
"""
import argparse
import json
from pathlib import Path
import re
import sys

STRATEGIES = ['baseline', 'resident', 'spill', 'reextract']


def fraction(sample):
    match = re.search(r'(\d+)%', sample.get('progress', ''))
    return int(match.group(1)) / 100 if match else None


def stage(sample):
    value = fraction(sample)
    if value is None:
        return 'start'
    if value <= 0.5701:
        return 'extract'
    if value <= 0.8201:
        return 'reconstruct'
    if value < 1.0:
        return 'write'
    return 'done'


def profile(samples):
    """Return per-stage footprint statistics in bytes plus the overall peak sample."""
    stages = {}
    peak = None
    for sample in samples:
        footprint = sample.get('physicalFootprintBytes') or 0
        entry = stages.setdefault(stage(sample), {'last': 0, 'max': 0})
        entry['last'] = footprint
        entry['max'] = max(entry['max'], footprint)
        if peak is None or footprint > (peak.get('physicalFootprintBytes') or 0):
            peak = sample
    return {
        'extractionEndBytes': stages.get('extract', {}).get('last'),
        'extractionPeakBytes': stages.get('extract', {}).get('max'),
        'reconstructionPeakBytes': stages.get('reconstruct', {}).get('max'),
        'writingPeakBytes': stages.get('write', {}).get('max'),
        'peakBytes': (peak or {}).get('physicalFootprintBytes'),
        'peakProgress': (peak or {}).get('progress'),
    }


def load_samples(path):
    data = json.loads(Path(path).read_text())
    return data if isinstance(data, list) else next(value for value in data.values() if isinstance(value, list))


def mib(value):
    return '' if value is None else f'{value / 2**20:,.1f}'


def render(root):
    lines = ['| Case | Run | Extraction end MiB | Extraction peak MiB | Reconstruction peak MiB | Writing peak MiB | Peak MiB | Peak at |',
             '| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |']
    for case_dir in sorted(path for path in Path(root).iterdir() if path.is_dir()):
        for name in STRATEGIES:
            samples_path = case_dir / name / 'memory-samples.json'
            if not samples_path.exists():
                continue
            result = profile(load_samples(samples_path))
            lines.append(f"| {case_dir.name} | {name} | {mib(result['extractionEndBytes'])} | {mib(result['extractionPeakBytes'])} | "
                         f"{mib(result['reconstructionPeakBytes'])} | {mib(result['writingPeakBytes'])} | {mib(result['peakBytes'])} | "
                         f"{result['peakProgress'] or ''} |")
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path, help='run.py output directory')
    args = parser.parse_args()
    print(render(args.output))
    return 0


if __name__ == '__main__':
    sys.exit(main())
