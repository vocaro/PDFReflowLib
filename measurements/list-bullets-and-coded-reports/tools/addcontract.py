import json, sys
# Adds the #115 and #96 content checks to corpus/regressions.json. Run from the repository root:
#   python3 measurements/list-bullets-and-coded-reports/tools/addcontract.py corpus/regressions.json
path = sys.argv[1]
r = json.load(open(path))
cases = {c['id']: c for c in r['cases']}

def page(case, number):
    pages = cases[case]['pages']
    for p in pages:
        if p['page'] == number:
            return p
    p = {'page': number}
    pages.append(p)
    return p

def extend(entry, key, values):
    entry.setdefault(key, [])
    for v in values:
        if v not in entry[key]:
            entry[key].append(v)

algebra = 'wallace-algebra-2010'
# #115: a tall marker line keeps its wrapped line in the item.
extend(page(algebra, 2), 'listItems', [
    '• Attribution: You must attribute the work in the manner specified by the author or licensor (but not in any way',
    '• Waiver: Any of the above conditions can be waived if you get permission from the copyright holder.',
    '• Public Domain: Where the work or any of its elements is in the public domain under applicable law,',
    '− Your fair dealing or fair use rights, or other applicable copyright exceptions and limitations;',
    '− Rights other persons may have either in the work itself or in how the work is used such as publicity or privacy rights',
    '• Notice: For any reuse or distribution, you must make clear to others the license term of this work. The best way',
])
extend(page(algebra, 64), 'listItems', [
    '• More than often represents addition and is usually built backwards, writing the second part plus the first',
    '• Less than often represents subtraction and is usually built backwards as well, writing the second part minus the first',
])
# #115: the book's other forms of `separates` vouch for the join.
extend(page(algebra, 9), 'paragraphs', ['is subtraction because the subtraction separates the 3 from what comes after it.'])
extend(page(algebra, 9), 'absentText', ['sep-arates'])

faa = 'faa-phak-8083-25c'
metar = 'METAR KGGG 161753Z AUTO 14021G26KT 3/4SM +TSRA BR BKN008 OVC012CB 18/17 A2970 RMK PRESFR'
# #96: a coded report set over several lines is one element.
extend(page(faa, 316), 'listItems', [metar])
extend(page(faa, 317), 'listItems', [metar])
extend(page(faa, 318), 'listItems', ['UA/OV GGG 090025/TM 1450/FL 060/TP C182/SK 080 OVC/WX FV04SM RA/TA 05/WV 270030KT/TB LGT/RM HVY RAIN'])
# Control: the TAF's change groups stay separate lines, now of one block. This replaces the
# page's `distinctParagraphs` pair, which read the same separation from paragraphs.
taf = page(faa, 319)
taf['distinctParagraphs'] = [d for d in taf.get('distinctParagraphs', [])
                             if d != {'first': 'FM1500 16015G25KT P6SM SCT040 BKN250', 'second': 'FM120000 14012KT P6SM BKN080 OVC150'}]
if not taf['distinctParagraphs']:
    del taf['distinctParagraphs']
extend(taf, 'preformattedLines', [[
    'TAF', 'KPIR 111130Z 1112/1212', 'TEMPO 1112/1114 5SM BR', 'FM1500 16015G25KT P6SM SCT040 BKN250',
    'FM120000 14012KT P6SM BKN080 OVC150 PROB30 1200/1204 3SM TSRA BKN030CB', 'FM120400 1408KT P6SM SCT040 OVC080',
    'TEMPO 1204/1208 3SM TSRA OVC030CB']])
# Controls: the explanation's prose around the reports keeps its paragraphs.
extend(page(faa, 316), 'paragraphs', ['A typical METAR report contains the following information in sequential order:'])
extend(page(faa, 318), 'paragraphs', ['Explanation:'])

with open(path, 'w') as f:
    json.dump(r, f, indent=2, ensure_ascii=False)
    f.write('\n')
