"""usage: cmp.py <case>: compare base vs cand lane outputs, write cmp/pagediff, print a summary."""
import json
import subprocess
import sys

S = '/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/issue117'
W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a5c85a3e7f625e901'
case = sys.argv[1]
base, cand = f'{S}/lane/base-{case}/{case}', f'{S}/lane/cand-{case}/{case}'
out = f'{S}/lane/cmp-{case}.json'
subprocess.run(['python3', 'tools/compare_conversion_runs.py', '--baseline', base, '--candidate', cand, '--output', out,
                '--allow-different-converters'], cwd=W, capture_output=True, text=True)
d = json.load(open(out))
keep = ['passed', 'provenanceErrors', 'sameConverter', 'changedPages', 'changedImages', 'navigationChanged',
        'changedNavigationPages', 'pageMarkersEqual', 'changedReportFields', 'changedOCRPages']
print(json.dumps({k: d.get(k) for k in keep if k in d})[:3000])
for label in ('base', 'cand'):
    summary = json.load(open(f'{S}/lane/{label}-{case}/summary.json'))
    r = summary['results'][0]
    print(label, 'passed', summary['passed'], 'checks', r.get('contentChecks'), 'errors', r.get('errors'))
    report = json.load(open(f'{S}/lane/{label}-{case}/{case}/conversion-report.json'))
    codes = {}
    for w in report.get('warnings', []):
        codes[w['code']] = codes.get(w['code'], 0) + 1
    res = json.load(open(f'{S}/lane/{label}-{case}/{case}/result.json'))
    mem = {k: v for k, v in res.items() if 'memory' in k.lower() or 'rss' in k.lower() or 'footprint' in k.lower()}
    print(label, 'reflowed', report.get('reflowedPageCount'), 'warnings', codes, 'memory', json.dumps(mem)[:400])
diff = subprocess.run(['python3', f'{S}/pagediff.py', W, f'{base}/{case}.epub', f'{cand}/{case}.epub', '--width', '200'],
                      capture_output=True, text=True).stdout
open(f'{S}/lane/pagediff-{case}.txt', 'w').write(diff)
print(diff.splitlines()[-1] if diff else 'no diff output')
