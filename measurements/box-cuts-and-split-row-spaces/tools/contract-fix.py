import json
from collections import OrderedDict
PATH = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2/corpus/regressions.json'
d = json.loads(open(PATH).read(), object_pairs_hook=OrderedDict)
cases = {c['id']: c for c in d['cases']}
flag = {p['page']: p for p in cases['gpo-our-flag-2003']['pages']}
fixes = {
    15: ('signing of the Declaration of Independence in 1826',
         'the 50th anniversary of the Declaration of Independence in 1826. Its design is typical of the exuberant'),
    25: ('fastened to a staff or halyard from which the flag is to be flown',
         'Advertising signs should not be fastened to a staff or halyard from which the flag is flown.'),
}
for page, (old, new) in fixes.items():
    flag[page]['paragraphs'] = [new if p == old else p for p in flag[page]['paragraphs']]
    assert new in flag[page]['paragraphs']
flag[15]['absentText'].append('ex uberant')
flag[25]['paragraphs'].append('embroidered on such articles as cushions or handkerchiefs')
flag[25]['absentText'].append('cush ions')
wallace = {p['page']: p for p in cases['wallace-algebra-2010']['pages']}
page = wallace[24]
page.setdefault('paragraphs', []).append('Combine like terms 10x − 24x and − 16 − 18'); page.setdefault('absentText', []).append('10x− 16− 24x− 18')
open(PATH, 'w').write(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
