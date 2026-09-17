"""Versioned, per-run evidence used by the evaluator and strict drift comparison."""
import hashlib
import json
from pathlib import Path
import re

VISION_CACHE = 'com.apple.e5rt.e5bundlecache'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def vision_cache_directory(executable, home=None):
    """Where Vision's model runtime caches compiled programs for processes of this name (#94)."""
    return Path(home or Path.home()) / 'Library/Caches' / Path(executable).name / VISION_CACHE


def vision_model_cache(executable, home=None):
    """Fingerprint the compiled-model cache a process launched as `executable` inherits (#94).

    Vision keys the cache by process name, not by path or binary, and OCR text can depend on
    which compiled programs it holds. `model.anehash` is excluded: its second half changes on
    every compile. Program bytes also vary between output-equivalent compiles, so a differing
    fingerprint is a diagnostic, not proof of different recognition; the evaluator receipt's
    `mode` says whether the run started from an empty cache.
    """
    directory = vision_cache_directory(executable, home)
    programs = {}
    if directory.is_dir():
        for path in sorted(directory.rglob('*')):
            if path.is_file() and path.name != 'model.anehash':
                programs[path.relative_to(directory).as_posix()] = digest(path)
    return {'executableName': Path(executable).name, 'directory': str(directory),
            'exists': directory.is_dir(), 'programCount': len(programs),
            'programsSHA256': hashlib.sha256(json.dumps(sorted(programs.items())).encode()).hexdigest()}


def is_digest(value):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{64}', value) is not None


def probe_errors(receipt):
    """Validate a probe against identities captured by its parent evaluator."""
    errors = []
    probe = receipt.get('environmentProbe')
    capture = receipt.get('environmentProbeCapture')
    if not isinstance(probe, dict) or not isinstance(capture, dict):
        return ['capability probe or capture receipt missing']
    if type(capture.get('exitCode')) is not int or capture['exitCode'] != 0 or capture.get('error'):
        errors.append('capability probe process did not complete successfully')
    if probe.get('schemaVersion') != 1:
        errors.append('unsupported capability probe schema')
    if not receipt.get('runID') or probe.get('runID') != receipt['runID']:
        errors.append('capability probe run identity mismatch')
    if (probe.get('sourceSHA256') != receipt.get('case', {}).get('sha256')
            or probe.get('page') != 1):
        errors.append('capability probe source/page mismatch')
    if (not is_digest(capture.get('executableSHA256'))
            or probe.get('probeSHA256') != capture['executableSHA256']):
        errors.append('capability probe executable identity mismatch')
    if not is_digest(capture.get('resultSHA256')):
        errors.append('capability probe capture resultSHA256 missing or invalid')
    for field in ('sourceSHA256', 'packedPixelSHA256'):
        if not is_digest(probe.get(field)):
            errors.append(f'capability probe {field} missing or invalid')
    for field in ('width', 'height', 'bitsPerPixel', 'rasterDPI'):
        if type(probe.get(field)) not in (int, float) or not 0 < probe[field] < float('inf'):
            errors.append(f'capability probe {field} missing or invalid')
    for field in ('metalDevice', 'colorSpaceName', 'system'):
        if not isinstance(probe.get(field), str) or not probe[field].strip():
            errors.append(f'capability probe {field} missing or invalid')
    if (probe.get('colorSpaceICC_SHA256') != 'unavailable'
            and not is_digest(probe.get('colorSpaceICC_SHA256'))):
        errors.append('capability probe ICC identity missing or invalid')
    ocr = probe.get('ocr')
    if (not isinstance(ocr, dict) or ocr.get('status') != 'succeeded'
            or not isinstance(ocr.get('lines'), list)
            or not all(isinstance(line, str) for line in ocr.get('lines', []))):
        errors.append('raster/Vision capability probe missing or failed')
    return errors
