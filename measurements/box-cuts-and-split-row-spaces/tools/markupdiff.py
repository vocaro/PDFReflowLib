#!/usr/bin/env python3
# usage: markupdiff.py <base.epub> <cand.epub> <page>... : unified diff of normalized page markup
import sys, difflib, re
sys.path.insert(0, '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2/tools')
from compare_conversion_runs import Evaluation
base, cand = Evaluation(sys.argv[1], {}), Evaluation(sys.argv[2], {})
for p in map(int, sys.argv[3:]):
    a = re.sub(r'>', '>\n', base.pages[p]['markup']).splitlines()
    b = re.sub(r'>', '>\n', cand.pages[p]['markup']).splitlines()
    print(f'=== page {p}')
    for line in difflib.unified_diff(a, b, lineterm='', n=1):
        print(line[:200])
