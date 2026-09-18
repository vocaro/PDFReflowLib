import json, sys
from collections import Counter

# usage: classify.py <cmp.json>: changed pages split into heading-rank-only and content changes.
d = json.load(open(sys.argv[1]))
f = d['changedPageFields']
rank = sorted(int(p) for p, v in f.items() if set(v) <= {'headingRanks'})
content = sorted(int(p) for p, v in f.items() if not set(v) <= {'headingRanks'})
print('rank-only', len(rank), 'content', len(content))
print('content pages', content)
print(Counter(tuple(sorted(set(v) - {'headingRanks', 'paragraphIDs', 'anchors'})) for p, v in f.items() if int(p) in content).most_common(25))
print('report fields', d['changedReportFields'])
print('navigation pages', d.get('changedNavigationPages'))
