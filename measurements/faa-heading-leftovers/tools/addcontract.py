import json, sys
# Adds the #97 content checks to corpus/regressions.json, preserving its formatting.
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

faa = 'faa-phak-8083-25c'
# Untagged 10-point italic titles in the book's italic title style are headings over their paragraphs.
extend(page(faa, 447), 'headings', ['Drugs', 'Exhaustion', 'Poor Physical Conditioning', 'Alcohol', 'Tobacco',
                                    'Hypoglycemia and Nutritional Deficiency', 'Motion Parallax'])
extend(page(faa, 447), 'orderedText', ['Drugs', 'Drugs can seriously degrade visual acuity', 'Exhaustion',
                                       'Pilots who become fatigued during a night flight'])
extend(page(faa, 228), 'headings', ['Southerly Turning Errors', 'Acceleration Error'])
# The PAVE mnemonic titles are text, not formula crops, and the italic titles under them (over a
# paragraph or directly over bullets) are headings.
extend(page(faa, 47), 'headings', ['A = Aircraft'])
extend(page(faa, 48), 'headings', ['V = EnVironment', 'Weather', 'Airport', 'Airspace'])
extend(page(faa, 48), 'orderedText', ['V = EnVironment', 'Weather', 'Weather is a major environmental consideration.',
                                      'Airport', 'What lights are available at the destination',
                                      'Airspace', 'If the trip is over remote areas'])
# The blank last pages of appendix A and the glossary carry no folio text.
extend(page(faa, 460), 'absentText', ['A-8'])
extend(page(faa, 512), 'absentText', ['G-36'])
# Controls: the italic `Distance` header of page 410's table, figure captions with italic text, and
# the E = External Pressures title (never a formula crop) keep their representation.
extend(page(faa, 410), 'absentHeadings', ['Distance'])
extend(page(faa, 447), 'absentHeadings', ['Figure 17-20. Self-imposed stress.'])
extend(page(faa, 48), 'headings', ['E = External Pressures'])

cases[faa]['basis'] += (' Pages 47, 48, 228, 447, 460 and 512 (#97) source-reviewed: untagged 10-point italic titles in the '
                        'book\'s recurring italic title style (pages 228, 447) and italic titles over bullet lists (48) are '
                        'headings; the PAVE titles A = Aircraft and V = EnVironment are text, not formula crops; the '
                        'blank pages 460 and 512 carry no folio. Page 410\'s italic table header Distance is not a heading.')
algebra = 'wallace-algebra-2010'
# Blank pages whose only text is the page number lose it like the FAA's blank part pages.
extend(page(algebra, 175), 'absentText', ['175'])
extend(page(algebra, 437), 'absentText', ['437'])
cases[algebra]['basis'] += (' Pages 175 and 437 (#97) source-reviewed: blank pages whose only text is the folio carry no '
                            'text once the folio run removes it.')
open(path, 'w').write(json.dumps(r, indent=2, ensure_ascii=False) + '\n')
