import json, glob, os

L = '/private/tmp/claude-501/i158/lane'
print('case, side, passed, checks, errors, seconds, peak RSS MB')
for side in ('base', 'cand'):
    for path in sorted(glob.glob(os.path.join(L, f'{side}-*'))):
        case = os.path.basename(path).split('-', 1)[1]
        try:
            summary = json.load(open(os.path.join(path, 'summary.json')))['results'][0]
            result = json.load(open(os.path.join(path, case, 'result.json')))
            print(f'{case}, {side}, {summary["passed"]}, {summary.get("contentChecks")}, '
                  f'{len(summary["errors"])}, {result["conversionSeconds"]:.1f}, '
                  f'{result["converterPeakRSSBytes"] / 1e6:.0f}')
        except Exception as error:
            print(case, side, 'unavailable', error)
print()
for path in sorted(glob.glob(os.path.join(L, 'cmp-*.json'))):
    d = json.load(open(path))
    print(os.path.basename(path), 'passed', d['passed'], 'changedPages', d['changedPages'][:14],
          'changedImages', len(d['changedImages']))
