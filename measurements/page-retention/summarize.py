"""Render results.json from run.py as Markdown tables for the record."""
import argparse
import json
from pathlib import Path
import sys

STRATEGIES = ['baseline', 'resident', 'spill', 'reextract']


def mib(value):
    return '' if value is None else f'{value / 2**20:,.1f}'


def seconds(value):
    return '' if value is None else f'{value:,.2f}'


def per_case_table(case, entry):
    lines = [f'### {case}', '',
             '| Run | Seconds | CPU s | Peak RSS MiB | Sampled footprint MiB | Peak run directory MiB | Identical | EPUBCheck |',
             '| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |']
    for name in STRATEGIES:
        run = entry['runs'].get(name)
        if not run:
            continue
        identical = 'reference' if name == 'baseline' else ('yes' if run.get('identical') else 'NO')
        epubcheck = {0: 'pass', None: ''}.get(run.get('epubcheckExitCode'), f"exit {run.get('epubcheckExitCode')}")
        lines.append(f"| {name} | {seconds(run.get('conversionSeconds'))} | {seconds(run.get('converterCPUSeconds'))} | "
                     f"{mib(run.get('converterPeakRSSBytes'))} | {mib(run.get('sampledPeakPhysicalFootprintBytes'))} | "
                     f"{mib(run.get('peakEvaluationDirectoryBytes'))} | {identical} | {epubcheck} |")
    return lines


def overview_table(cases, metric, label, formatter):
    lines = [f'| Case | ' + ' | '.join(STRATEGIES) + ' |', '| --- | ' + ' | '.join('---:' for _ in STRATEGIES) + ' |']
    for case, entry in cases.items():
        cells = [formatter(entry['runs'].get(name, {}).get(metric)) for name in STRATEGIES]
        lines.append(f'| {case} | ' + ' | '.join(cells) + ' |')
    return [f'**{label}**', ''] + lines


def render(results):
    cases = results['cases']
    lines = ['Identity and success: ' + ('all candidate outputs byte-identical to the baseline and all conversions succeeded'
                                          if results.get('allIdenticalAndSuccessful') else 'FAILURES recorded'), '']
    lines += overview_table(cases, 'sampledPeakPhysicalFootprintBytes', 'Sampled peak physical footprint, MiB', mib) + ['']
    lines += overview_table(cases, 'converterPeakRSSBytes', 'Peak RSS, MiB', mib) + ['']
    lines += overview_table(cases, 'conversionSeconds', 'Conversion seconds', seconds) + ['']
    lines += overview_table(cases, 'peakEvaluationDirectoryBytes', 'Peak run-directory bytes, MiB', mib) + ['']
    for case, entry in cases.items():
        lines += per_case_table(case, entry) + ['']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('results', type=Path)
    args = parser.parse_args()
    print(render(json.loads(args.results.read_text())))
    return 0


if __name__ == '__main__':
    sys.exit(main())
