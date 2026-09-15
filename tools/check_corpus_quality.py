#!/usr/bin/env python3
"""Opt-in warning/refusal contract over a real-document evaluation directory.

This checks client-visible signaling, not transcription accuracy. Ordinary crashes,
resource failures and generic image-preservation warnings do not satisfy a quality refusal.
"""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def assess(case, result, report, log, *, output_exists, staging_exists):
    expected = case['qualityExpectation']
    identity_matches = all(result.get('case', {}).get(k) == case[k]
                           for k in ('id', 'sha256', 'bytes', 'pages'))
    converted = result.get('conversionExitCode') == 0
    required = expected['warningPages']
    accepted = set(expected['warningCodes'])
    if (not required or not accepted or len(set(required)) != len(required)
            or any(type(p) is not int or not 1 <= p <= case['pages'] for p in required)):
        raise ValueError('Quality expectation requires distinct in-range pages and warning codes')
    warned = sorted({w.get('page') for w in report.get('warnings', [])
                     if w.get('code') in accepted and w.get('page') in required})
    # Exact diagnostics must be explicitly approved in the manifest; no wildcard errors.
    allowed_errors = expected.get('qualityRejectionDiagnostics', [])
    lines = log.splitlines()
    errors = [line for line in lines if line in allowed_errors]
    refused = (isinstance(result.get('conversionExitCode'), int)
               and result['conversionExitCode'] == 1 and not result.get('timedOut', False)
               and len(errors) == 1 and lines[-1] == errors[0]
               and result.get('memoryGate', {}).get('passed', True) is True
               and not output_exists and not staging_exists
               and re.search(r'^\d+% completed(?:\s|$)', log, re.MULTILINE) is None)
    warned_conversion = (converted and result.get('runPassed') is True and output_exists
                         and not staging_exists and report.get('pageCount') == case['pages']
                         and set(warned) == set(required))
    return {'case': case['id'], 'passed': identity_matches and (refused or warned_conversion),
            'identityMatches': identity_matches, 'conversionSucceeded': converted,
            'explicitQualityRefusal': refused, 'requiredWarningPages': required,
            'pagesWithAcceptedWarnings': warned,
            'missingWarningPages': sorted(set(required) - set(warned)),
            'scope': 'Client-visible quality signaling only; not EPUB or transcription fidelity qualification.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', required=True)
    parser.add_argument('--evaluation', type=Path, required=True)
    args = parser.parse_args()
    cases = json.loads((ROOT / 'corpus/manifest.json').read_text())['documents']
    case = next((c for c in cases if c['id'] == args.case), None)
    if case is None or 'qualityExpectation' not in case:
        parser.error('case has no warning/refusal expectation')
    directory = args.evaluation
    result = json.loads((directory / 'result.json').read_text())
    report_path = directory / 'conversion-report.json'
    report_text = report_path.read_text()
    report = json.loads(report_text) if report_text.strip() else {}
    assessment = assess(case, result, report, (directory / 'progress.log').read_text(),
                        output_exists=(directory / (case['id'] + '.epub')).exists(),
                        staging_exists=any(directory.glob('.pdfreflow-*')))
    print(json.dumps(assessment, indent=2))
    return 0 if assessment['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
