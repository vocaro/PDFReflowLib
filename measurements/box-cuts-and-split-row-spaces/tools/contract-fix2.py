import json
from collections import OrderedDict
PATH = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2/corpus/regressions.json'
d = json.loads(open(PATH).read(), object_pairs_hook=OrderedDict)
cases = {c['id']: c for c in d['cases']}
pages = cases['gpo-911-2004']['pages']


def entry(number):
    found = [p for p in pages if p['page'] == number]
    assert len(found) <= 1
    if found:
        return found[0]
    item = OrderedDict(page=number)
    pages.append(item)
    return item


def add(number, key, values):
    item = entry(number)
    item.setdefault(key, [])
    item[key] += [v for v in values if v not in item[key]]


# Rows of the appendix's name lists, one show across the name and description columns (#177).
add(450, 'text', ['Director, Federal Bureau of Investigation, 1993–2001'])
add(450, 'absentText', ['Director,Federal'])
add(452, 'text', ['(a.k.a. Abu Hafs al Masri) Egyptian; al Qaeda military commander'])
add(452, 'absentText', ['(a.k.a.Abu Hafs'])
add(455, 'text', ['Jordanian; Virginia resident who helped Hazmi'])
add(455, 'absentText', ['Jordanian;Virginia'])
open(PATH, 'w').write(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
