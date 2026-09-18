#!/usr/bin/env python3
"""Fresh-process PDFKit extraction stress checks; no crash retry or exception suppression.

Each fixture is original synthetic PDF content, with text/font assertions independent of
extracted output. A passing campaign is bounded evidence, not proof of thread safety.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    'tools/probe-pdfkit-concurrency.swift',
    'Sources/PDFReflowLib/NativeTextReader.swift',
    'Sources/PDFReflowLib/NativeSpacingReader.swift',
    'Sources/PDFReflowLib/FontWeightReader.swift',
    'Sources/PDFReflowLib/PrivateUseDecoder.swift',
    'Sources/PDFReflowLib/ColumnGrid.swift',
    'Sources/PDFReflowLib/DocumentModel.swift',
    'Sources/PDFReflowLib/ReflowDocument.swift',
    'Sources/PDFReflowLib/ConversionTypes.swift',
]


def fixture(tagged):
    """Recreate #21's RoleMap/MCR fixture, plus an identical untagged text control."""
    content = ('/P << /MCID 0 >> BDC BT /F1 12 Tf 1 0 0 1 40 700 Tm (Small heading) Tj ET EMC\n'
               '/Span << /MCID 1 >> BDC BT /F1 24 Tf 1 0 0 1 40 580 Tm (First paragraph line) Tj ET EMC\n'
               '/P << /MCID 2 >> BDC BT /F1 24 Tf 1 0 0 1 80 510 Tm (second paragraph line.) Tj ET EMC')
    objects = [
        '<< /Type /Catalog /Pages 2 0 R' + (' /StructTreeRoot 6 0 R /MarkInfo << /Marked false >>' if tagged else '') + ' >>',
        '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R'
        + (' /StructParents 0' if tagged else '') + ' >>',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        f'<< /Length {len(content.encode())} >>\nstream\n{content}\nendstream',
    ]
    if tagged:
        objects += [
            '<< /Type /StructTreeRoot /RoleMap << /Title /H3 >> /K [8 0 R 9 0 R] /ParentTree 7 0 R >>',
            '<< /Nums [0 [8 0 R 10 0 R 9 0 R]] >>',
            '<< /Type /StructElem /S /Title /P 6 0 R /K << /Type /MCR /Pg 3 0 R /MCID 0 >> >>',
            '<< /Type /StructElem /S /P /P 6 0 R /Pg 3 0 R /K [10 0 R 2] >>',
            '<< /Type /StructElem /S /Span /P 9 0 R /K 1 >>',
        ]
    data = b'%PDF-1.7\n'
    offsets = [0]
    for index, obj in enumerate(objects, 1):
        offsets.append(len(data))
        data += f'{index} 0 obj\n{obj}\nendobj\n'.encode()
    xref = len(data)
    data += f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode()
    data += b''.join(f'{offset:010d} 00000 n \n'.encode() for offset in offsets[1:])
    data += f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
    return data


def identity(path):
    return {'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def classify(returncode, timed_out, stdout, mode, workers, iterations):
    if timed_out:
        return 'timeout', None
    if returncode < 0:
        return 'signal', None
    if returncode != 0:
        return 'failed', None
    try:
        records = [json.loads(line) for line in stdout.splitlines()]
        start, result = records
        if (start['event'] != 'started' or result['event'] != 'completed'
                or any(r['mode'] != mode or r['workers'] != workers or r['iterations'] != iterations for r in records)
                or result['completed'] != max(1, workers) * iterations
                or result['failures'] != [] or type(result['peakRSSBytes']) is not int
                or result['peakRSSBytes'] <= 0):
            raise ValueError('Incomplete or inconsistent result')
    except (ValueError, KeyError, TypeError):
        return 'invalid-receipt', None
    return 'passed', result


def run_case(command, directory, timeout, mode, workers, iterations):
    directory.mkdir()
    started = time.monotonic()
    timed_out = False
    # Separate process group: on timeout the entire child group is killed and reaped.
    # Output goes to files, preserving diagnostics even when the probe aborts.
    with (directory / 'stdout.log').open('wb') as out, (directory / 'stderr.log').open('wb') as err:
        child = subprocess.Popen(command, stdout=out, stderr=err, start_new_session=True)
        try:
            child.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
        except BaseException:
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait()
            raise
    status, result = classify(child.returncode, timed_out,
        (directory / 'stdout.log').read_text(errors='replace'), mode, workers, iterations)
    receipt = {'status': status, 'returncode': child.returncode, 'timedOut': timed_out,
               'seconds': time.monotonic() - started, 'mode': mode, 'workers': workers,
               'iterations': iterations, 'command': command, 'result': result,
               'logs': {name: identity(directory / name) for name in ('stdout.log', 'stderr.log')}}
    (directory / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--trials', type=int, default=3)
    parser.add_argument('--iterations', type=int, default=100)
    parser.add_argument('--workers', type=int, nargs='+', default=[0, 1, 8], help='0=main thread; 1=serial background')
    parser.add_argument('--modes', choices=['plain', 'attributed', 'native'], nargs='+', default=None)
    parser.add_argument('--sdk-only', action='store_true', help='Compile with Apple SDKs only; native mode unavailable')
    parser.add_argument('--timeout', type=float, default=60)
    parser.add_argument('--optimization', choices=['debug', 'release'], default='release')
    args = parser.parse_args()
    if args.modes is None:
        args.modes = ['plain', 'attributed'] if args.sdk_only else ['plain', 'attributed', 'native']
    if args.sdk_only and 'native' in args.modes:
        parser.error('native mode requires the library extraction sources')
    if (not 1 <= args.trials <= 100 or not 1 <= args.iterations <= 10000
            or not 0 < args.timeout <= 600 or any(not 0 <= w <= 16 for w in args.workers)
            or len(set(args.workers)) != len(args.workers) or len(set(args.modes)) != len(args.modes)):
        parser.error('Require bounded positive trials/iterations/timeout and unique workers in 0...16/modes')
    if sys.platform != 'darwin':
        parser.error('The probe requires macOS and a full Xcode installation')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    environment = dict(os.environ)
    environment.setdefault('DEVELOPER_DIR', subprocess.check_output(['xcode-select', '-p'], text=True).strip())
    binary = output / 'probe'
    sources = SOURCES[:1] if args.sdk_only else SOURCES
    flags = [] if args.sdk_only else ['-D', 'PDFREFLOW_NATIVE']
    command = ['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', *flags,
               '-O' if args.optimization == 'release' else '-Onone', *sources, '-o', str(binary)]
    metadata = {
        'schemaVersion': 1, 'platform': platform.platform(),
        'osBuild': subprocess.check_output(['sw_vers'], text=True).strip(),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], env=environment, text=True).strip(),
        'swift': subprocess.check_output(['xcrun', 'swiftc', '--version'], env=environment, text=True).strip(),
        'gitHead': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'sources': {p: identity(ROOT / p) for p in [*sources, 'tools/check_pdfkit_concurrency.py']},
        'settings': {k: v for k, v in vars(args).items() if k != 'output'},
        'compileCommand': command,
    }
    (output / 'identity.json').write_text(json.dumps(metadata, indent=2) + '\n')
    with (output / 'build.log').open('wb') as log:
        subprocess.run(command, cwd=ROOT, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True)
    metadata['binary'] = identity(binary)
    metadata['fixtures'] = {}
    for name, tagged in [('rolemap', True), ('untagged', False)]:
        path = output / f'{name}.pdf'
        path.write_bytes(fixture(tagged))
        metadata['fixtures'][name] = identity(path)
    (output / 'identity.json').write_text(json.dumps(metadata, indent=2) + '\n')
    results = []
    for trial in range(1, args.trials + 1):
        for fixture_name in metadata['fixtures']:
            for mode in args.modes:
                for workers in args.workers:
                    name = f'{fixture_name}-{mode}-w{workers}-trial{trial}'
                    result = run_case([str(binary), str(output / f'{fixture_name}.pdf'), mode, str(workers), str(args.iterations)],
                                      output / name, args.timeout, mode, workers, args.iterations)
                    result['case'] = name
                    result['fixture'] = fixture_name
                    results.append(result)
                    # Keep every outcome, including before an interrupted campaign.
                    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
                    print(f'{name}: {result["status"]} ({result["seconds"]:.2f}s)', flush=True)
    failures = sum(r['status'] != 'passed' for r in results)
    print(f'{len(results) - failures}/{len(results)} fresh processes passed; evidence: {output}', flush=True)
    return int(failures != 0)


if __name__ == '__main__':
    sys.exit(main())
