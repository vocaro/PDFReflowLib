"""Versioned, per-run evidence used by the evaluator and strict drift comparison."""
import re


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
