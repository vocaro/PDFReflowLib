#!/usr/bin/env python3
# Adds the #177 expectations to corpus/regressions.json, merging into each page's one entry.
import json
from collections import OrderedDict
PATH = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a8f4ce138eaeafac2/corpus/regressions.json'
raw = open(PATH).read()
d = json.loads(raw, object_pairs_hook=OrderedDict)
cases = {c['id']: c for c in d['cases']}


def entry(case, page):
    pages = cases[case]['pages']
    found = [p for p in pages if p['page'] == page]
    assert len(found) <= 1, (case, page)
    if found:
        return found[0]
    item = OrderedDict(page=page)
    pages.append(item)
    return item


def add(case, page, key, values):
    item = entry(case, page)
    item.setdefault(key, [])
    for value in values:
        if value not in item[key]:
            item[key].append(value)


def replace(case, page, key, old, new):
    item = entry(case, page)
    item[key] = [new if value == old else value for value in item[key]]
    assert new in item[key], (case, page, old)


FED, NINE, FLAG = 'fed-explained-2021', 'gpo-911-2004', 'gpo-our-flag-2003'
# Item 1: paragraphs a box at the page's foot cuts, continued on the next page.
for page, end, nxt in [
    (47, 'key line items of the Federal Reserve’s balance sheet.) The vast major', 'ity of the Federal Reserve’s assets are securities holdings'),
    (98, 'all output files be delivered electronically. That is, all institu', 'tions dealing with the Federal Reserve directly were required'),
    (40, 'guaranteed by the U.S. Treasury or U.S. government agencies. When the', 'securities are bought or sold, reserves in the banking system'),
    (46, 'significantly boosted the level of reserves', 'in the banking system. (See subsection'),
    (55, 'the Dodd-Frank Act stress tests for large banking', 'institutions and the Financial Stability Report'),
    (93, 'used primarily for transactions between banks (interbank transactions)', 'and between businesses. The check-collection system'),
    (97, 'payroll payments, and consumer mortgage and utility payments. Much of the recent', 'growth in ACH payments has resulted from one-time transactions'),
    (100, 'now opens at 9:00 p.m. eastern time (ET) on the night before a business', 'day and closes at 7:00 p.m.'),
    (105, 'the First Liberty Loan—bonds issued to help finance the', 'United States’ World War I effort.'),
]:
    add(FED, page, 'continuedParagraphs', [OrderedDict(end=end, next=nxt)])
# Item 2 and the same shape elsewhere: a paragraph wrapped around a box inset into its column.
add(FED, 28, 'paragraphs', ['for the federal funds rate. Short-term interest rates would decline if the FOMC reduced its',
                            'lower than previously expected. Conversely, short-term interest rates would rise if the FOMC increased'])
add(FED, 28, 'distinctParagraphs', [OrderedDict(first='short-term interest rates would rise if the FOMC increased',
                                                second='The FOMC changes monetary policy primarily by raising or lowering')])
add(FED, 20, 'paragraphs', ['to achieve these dual objectives. At times, as an additional policy measure, the FOMC has used forward guidance'])
add(FED, 34, 'paragraphs', ['the risks and uncertainties attending the outlook, and the reasons for the Committee’s decisions.'])
add(FED, 60, 'paragraphs', ['the pernicious spillovers of distress at or between individual institutions and from those institutions to the broader economy.'])
add(FED, 84, 'paragraphs', ['with significant U.S. operations. These standards require these institutions to maintain a minimum liquidity buffer'])
add(FED, 84, 'absentText', ['mini- mum'])
add(FED, 92, 'paragraphs', ['carrying out monetary, supervisory, and lending responsibilities.'])
add(FED, 94, 'paragraphs', ['the practice of paying checks at less than their full face value. This practice of not remitting payment'])
add(FED, 122, 'paragraphs', ['including its consumer compliance culture and how effectively it identifies and manages consumer compliance risk, to tailor the scope and resources needed'])
# Item 4: word spaces the reader had for a row PDFKit split into pieces.
replace(NINE, 254, 'paragraphs', 'check with Atta to confirm that each had arrived.Hawsawi told',
        'check with Atta to confirm that each had arrived. Hawsawi told')
add(NINE, 254, 'absentText', ['arrived.Hawsawi'])
replace(NINE, 259, 'paragraphs', 'the 9/11 attack.At the time of their travel through Iran, the al Qaeda operatives',
        'the 9/11 attack. At the time of their travel through Iran, the al Qaeda operatives')
add(NINE, 259, 'absentText', ['attack.At'])
add(NINE, 438, 'paragraphs', ['master the subject and the agencies, to conduct oversight of the intelligence establishment'])
add(NINE, 438, 'absentText', ['agencies,to'])
add(NINE, 455, 'text', ['Mohamedou Ould Slahi (a.k.a. Abu Musab) Mauritanian'])
add(NINE, 455, 'absentText', ['(a.k.a.Abu Musab)'])
# Item 3: the soft hyphen the page draws at a line's end.
item = entry(FLAG, 47)
item['text'] = [t for t in item['text'] if t != 'did not become a real ity']
if not item['text']:
    del item['text']
add(FLAG, 47, 'paragraphs', ['did not become a reality until June 20, 1782.', 'White signifies purity and innocence, Red, hardiness'])
add(FLAG, 47, 'absentText', ['real ity', 'inno cence'])
add(FLAG, 8, 'paragraphs', ['brought to the attention of the public in 1870'])
add(FLAG, 8, 'absentText', ['pub lic'])
add(FLAG, 25, 'paragraphs', ['fastened to a staff or halyard from which the flag is to be flown'])
add(FLAG, 25, 'absentText', ['hal yard', 'addi tional'])
add(FLAG, 52, 'paragraphs', ['TO SUPPORT ITS CONSTITUTION; TO OBEY ITS LAWS'])
add(FLAG, 52, 'absentText', ['CONSTITU TION'])
add(FLAG, 15, 'paragraphs', ['signing of the Declaration of Independence in 1826'])
add(FLAG, 15, 'absentText', ['Independ ence', 'uni form'])
open(PATH, 'w').write(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
