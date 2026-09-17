"""Condenses each case's base/cand lane and comparison into measurements/.../lane/<case>.json."""
import json, os
L = '/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/i141/lane'
OUT = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a0ba3a7886d1b0e32/measurements/dga-header-and-note-columns/lane'
cases = ['dga-2025-2030', 'fed-explained-2021', 'faa-phak-8083-25c', 'cdc-zombie-pandemic-2011', 'usgs-mcs2025-copper', 'gpo-our-flag-2003']
for case in cases:
    record = {'case': case}
    for side in ('base', 'cand'):
        summary = json.load(open(f'{L}/{side}-{case}/summary.json'))['results'][0]
        result = json.load(open(f'{L}/{side}-{case}/{case}/result.json'))
        warnings = {}
        for w in result['conversionReport'].get('warnings', []):
            warnings[w['code']] = warnings.get(w['code'], 0) + 1
        record[side] = {
            'converterSHA256': result['converterSHA256'], 'passed': summary['passed'], 'contentChecks': summary['contentChecks'],
            'errors': summary['errors'], 'epubcheckExitCode': result['epubcheckExitCode'], 'runPassed': result['runPassed'],
            'converterPeakRSSMiB': round(result['converterPeakRSSBytes'] / 2**20), 'memoryLimitMiB': round(result['memoryGate']['limitBytes'] / 2**20),
            'conversionSeconds': round(result['conversionSeconds'], 1), 'warnings': warnings,
        }
    comparison = json.load(open(f'{L}/cmp-{case}.json'))
    record['comparison'] = {k: comparison[k] for k in ('passed', 'changedPages', 'changedPageFields', 'changedImages', 'navigationChanged',
                                                      'changedNavigationPages', 'changedReportFields', 'pageMarkersEqual', 'changedOCRPages')}
    record['comparison']['idOnlyShiftPages'] = comparison['idOnlyShifts']['pageCount']
    json.dump(record, open(f'{OUT}/{case}.json', 'w'), indent=1)
    print(case, record['base']['contentChecks'], record['base']['passed'], record['cand']['passed'], record['comparison']['changedPages'])
