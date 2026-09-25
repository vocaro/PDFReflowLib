#!/usr/bin/env python3
"""Run the prebuilt RasterHost on an explicitly available physical device, one process per setting.

Device ownership must be coordinated before invoking. Copies all evidence before the next launch
replaces the host's previous output. Never substitutes a simulator or retries a failed conversion.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from check_corpus_content import check_evaluation
from pdfreflow_tools.corpus import manifest_cases, regression_contracts

BUNDLE = 'com.vocaro.pdfreflow.rasterhost'


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def run(command, log):
    with log.open('w') as output:
        return subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=3600).returncode


def physical_identity(result, udid):
    properties = result.get('properties', {})
    hardware = properties.get('hardware', result.get('hardwareProperties', {}))
    if hardware.get('reality') != 'physical' or hardware.get('udid') != udid:
        raise ValueError('an exact physical-device UDID is required; simulator/unknown devices are not evidence')
    software = properties.get('software', {})
    legacy = result.get('deviceProperties', {})
    return {**{key: hardware.get(key) for key in ('marketingName', 'productType', 'reality')},
            'osVersion': software.get('osVersionNumber', {}).get('stringValue', legacy.get('osVersionNumber')),
            'osBuild': software.get('osBuildVersions', {}).get('buildVersion', {}).get('name', legacy.get('osBuildUpdate'))}


def validate_metrics(metrics, name, dpi, pixels, source_hash, ocr, references):
    expected = (name, dpi, pixels, source_hash, ocr, references)
    actual = tuple(metrics.get(key) for key in ('case', 'rasterDPI', 'maximumRasterPixels', 'sourceSHA256', 'ocr', 'referenceImages'))
    if actual != expected:
        raise ValueError('stale or incorrect device output')


def validate_console(log, metrics):
    # A copy of a previous result can match all settings on a repeat. Require the fresh
    # launch's console result too; this log is truncated before every process launch.
    records = [json.loads(line.split('RASTER_RESULT ', 1)[1]) for line in log.splitlines()
               if line.startswith('RASTER_RESULT ')]
    if not records or records[-1] != metrics:
        raise ValueError('copied metrics do not match a fresh console result')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--plan', type=Path, help='explicit derivative stress-source manifest and contracts')
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--case', action='append', required=True, dest='cases')
    parser.add_argument('--dpi', type=int, action='append', dest='dpis')
    parser.add_argument('--pixels', type=int, default=12_000_000)
    parser.add_argument('--maximum-output-bytes', type=int, default=512 * 1024 * 1024)
    parser.add_argument('--ocr', choices=['automatic', 'always', 'never'], default='automatic')
    parser.add_argument('--references', choices=['automatic', 'always'], default='automatic')
    args = parser.parse_args()
    if args.maximum_output_bytes <= 0:
        parser.error('output budget must be positive')
    if not 1 <= args.pixels <= 48_000_000 or any(not 72 <= dpi <= 600 for dpi in args.dpis or []):
        parser.error('raster settings outside library bounds')
    if len(set(args.cases)) != len(args.cases) or len(set(args.dpis or [])) != len(args.dpis or []):
        parser.error('duplicate case or DPI would overwrite evidence')
    cases = {case['id']: case for case in manifest_cases(ROOT)}
    contracts = {case['id']: case for case in regression_contracts(ROOT)['cases']}
    if args.plan:
        plan = json.loads(args.plan.read_text())
        cases.update({case['id']: case for case in plan['documents']})
        contracts.update({case['id']: case for case in plan['cases']})
    for name in args.cases:
        source = args.app / (name + '.pdf')
        if name not in cases or digest(source) != cases[name]['sha256']:
            parser.error(f'bundled source does not match the corpus: {name}')
    build_receipt = json.loads((args.app.parents[3] / 'build-receipt.json').read_text())
    if build_receipt['binarySHA256'] != digest(args.app / 'RasterHost'):
        raise ValueError('app executable differs from its build receipt')
    args.output.mkdir(parents=True, exist_ok=False)
    details = args.output / 'device-info.json'
    subprocess.run(['xcrun', 'devicectl', 'device', 'info', 'details', '--device', args.device,
                    '--json-output', str(details), '--quiet'], check=True)
    hardware = physical_identity(json.loads(details.read_text())['result'], args.device)
    details.unlink()
    identity = {'hardware': hardware, 'baseCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                'binarySHA256': digest(args.app / 'RasterHost'), 'settings': vars(args) | {'app': str(args.app), 'output': str(args.output), 'plan': str(args.plan) if args.plan else None},
                'hostSourceSHA256': build_receipt['hostSourceSHA256'], 'build': build_receipt}
    save(args.output / 'identity.json', identity)
    subprocess.run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', args.device, str(args.app), '--quiet'], check=True)
    results = []
    for name in args.cases:
        for dpi in args.dpis or [180, 96, 150, 300]:
            directory = args.output / f'{name}-{dpi}-{args.pixels}'
            env = {'RASTER_CASE': name, 'RASTER_DPI': str(dpi), 'RASTER_PIXELS': str(args.pixels),
                   'RASTER_OCR': args.ocr, 'RASTER_REFERENCES': args.references,
                   'RASTER_OUTPUT_BUDGET': str(args.maximum_output_bytes)}
            log = args.output / (directory.name + '.log')
            status = run(['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', args.device,
                          '--console', '--terminate-existing', '--environment-variables', json.dumps(env), BUNDLE], log)
            copy_status = run(['xcrun', 'devicectl', 'device', 'copy', 'from', '--device', args.device,
                              '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE,
                              '--source', 'Documents/current', '--destination', str(directory)],
                             args.output / (directory.name + '-copy.log'))
            if copy_status:
                raise RuntimeError(f'cannot retrieve {directory.name}; see logs')
            metrics = json.loads((directory / 'metrics.json').read_text())
            validate_metrics(metrics, name, dpi, args.pixels, cases[name]['sha256'], args.ocr, args.references)
            if metrics.get('maximumOutputBytes', 512 * 1024 * 1024) != args.maximum_output_bytes:
                raise ValueError('device output budget differs from requested settings')
            validate_console(log.read_text(), metrics)
            completed = status == 0 and metrics['status'] == 'completed'
            receipt = {'case': cases[name], 'conversionExitCode': 0 if completed else 1,
                       'runPassed': completed, 'scope': 'Device conversion completed; no memory or fidelity gate implied.'}
            save(directory / 'result.json', receipt)
            assessment = None
            if completed:
                try:
                    assessment = check_evaluation(cases[name], contracts[name], directory,
                                                  max_uncompressed_bytes=args.maximum_output_bytes)
                except (ValueError, OSError) as error:
                    assessment = {'case': name, 'passed': False, 'errors': [str(error)]}
            if assessment: save(directory / 'content.json', assessment)
            report = json.loads((directory / 'conversion-report.json').read_text()) if completed else None
            row = {'metrics': metrics, 'launchExitCode': status, 'content': assessment, 'report': report}
            results.append(row); save(args.output / 'results.json', results)
            print(f'{name} dpi={dpi} status={metrics["status"]} seconds={metrics.get("seconds")} content={assessment and assessment["passed"]}', flush=True)
    return 0 if all(row['launchExitCode'] == 0 and row['metrics']['status'] == 'completed' for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
