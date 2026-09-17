import json, sys
# Adds the #100/#102 content checks to corpus/regressions.json, preserving its formatting.
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

fed = 'fed-explained-2021'
# The narrow sidebars' titles are headings over the box's first paragraph (#100): one-line titles,
# a two-line title, a question, and page 63's two boxes, the second breaking its paragraphs with
# the same space its title sets.
extend(page(fed, 27), 'headings', ['A fresh look at the monetary policy framework'])
extend(page(fed, 27), 'orderedText', ['A fresh look at the monetary policy framework', 'In 2019, the Fed launched a comprehensive'])
extend(page(fed, 19), 'headings', ['Want to learn more about Reserve Bank directors?'])
extend(page(fed, 26), 'headings', ['FOMC composition helps ensure broad perspective', 'Fed Chair on accountability and transparency'])
extend(page(fed, 37), 'headings', ['Large-Scale Asset Purchase (LSAP) programs supported credit for households and businesses'])
extend(page(fed, 37), 'absentHeadings', ['Large-Scale Asset Purchase (LSAP) programs', 'supported credit for households and businesses'])
extend(page(fed, 63), 'headings', ['Regular reporting on FSOC activities', 'Central banks around the world'])
extend(page(fed, 63), 'absentHeadings', ['The central bank concept dates to 1668 when Swe-den’s Riksbank was formed.'])
extend(page(fed, 95), 'headings', ['What is check truncation?'])
cases[fed]['basis'] += (' Pages 19, 26, 27, 37, 54, 63 and 95 source rasters reviewed (#100): each narrow sidebar opens with a '
                        'demibold title in the box\'s own 8-point size, set off by extra space; the title is a heading over '
                        'the box\'s first paragraph, a two-line title is one heading, and page 63\'s second paragraph break '
                        'inside its box is no title.')

faa = 'faa-phak-8083-25c'
# Untagged sub-headings set over two lines in the book's 10-point bold style are one heading (#102).
extend(page(faa, 21), 'headings', ['The Professional Air Traffic Controllers Organization (PATCO) Strike'])
extend(page(faa, 21), 'absentHeadings', ['The Professional Air Traffic Controllers', 'Organization (PATCO) Strike'])
extend(page(faa, 404), 'headings', ['Use of Chart Supplement U.S. (formerly Airport/Facility Directory)'])
extend(page(faa, 404), 'orderedText', ['Use of Chart Supplement U.S. (formerly Airport/Facility Directory)',
                                       'Study available information about each airport'])
# Contents entries naming the PAVE letters are text, not a formula crop (#102).
extend(page(faa, 6), 'text', ['A = Aircraft', 'V = EnVironment', 'E = External Pressures', 'Human Factors'])
cases[faa]['basis'] += (' Pages 6, 21 and 404 source-reviewed (#102): the two-line bold sub-headings The Professional Air '
                        'Traffic Controllers / Organization (PATCO) Strike and Use of Chart Supplement U.S. (formerly Airport/ '
                        '/ Facility Directory) are one heading each; page 6\'s contents entries A = Aircraft through Human '
                        'Factors are text, not a preserved region.')

algebra = 'wallace-algebra-2010'
# The chapter contents entry `6.3 Trinomials where a =1 ....221` is text, not a formula crop.
extend(page(algebra, 211), 'text', ['6.3 Trinomials where a'])
extend(page(algebra, 5), 'text', ['6.3 Trinomials where a'])
cases[algebra]['basis'] += (' Pages 5 and 211 source-reviewed (#102): the contents entry 6.3 Trinomials where a = 1 with its '
                            'leader is text, not a preserved region.')

report = 'gpo-911-2004'
# Control: a sidebar paragraph ending in a note marker over an indented paragraph is no box title.
extend(page(report, 348), 'absentHeadings', ['FBI was aware of the flights of Saudi nationals and was able to screen the passengers before they were allowed to depart.30'])
extend(page(report, 348), 'paragraphs', ['FBI was aware of the flights of Saudi nationals'])
cases[report]['basis'] += (' Page 348 source-reviewed (#100 control): the framed sidebar opens with a two-line paragraph ending '
                           'in note 30 over a first-line-indented paragraph; it has no title.')
open(path, 'w').write(json.dumps(r, indent=2, ensure_ascii=False) + '\n')
