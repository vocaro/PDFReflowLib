#!/usr/bin/env python3
# usage: compare.py <case>... : compare_conversion_runs (base vs cand, --allow-different-converters --detail)
import sys, json, subprocess
S = '/private/tmp/claude-501/i177'
W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2'
for case in sys.argv[1:]:
    out = f'{S}/compare-{case}.json'
    subprocess.run(['python3', f'{W}/tools/compare_conversion_runs.py', '--baseline', f'{S}/base-{case}/{case}',
                    '--candidate', f'{S}/cand-{case}/{case}', '--output', out, '--allow-different-converters', '--detail'],
                   capture_output=True)
    d = json.load(open(out))
    images = d['changedImages']
    print(case, 'passed', d['passed'], 'changed', d['changedPages'],
          'images', images.get('count') if isinstance(images, dict) else images, 'nav', d['navigationChanged'],
          d.get('changedNavigationPages'), 'markers', d['pageMarkersEqual'], 'report', d['changedReportFields'],
          'prov', d['provenanceErrors'], 'ocr', d['changedOCRPages'])
