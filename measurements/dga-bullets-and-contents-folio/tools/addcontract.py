import json, sys
# Adds the #103/#105 content checks to corpus/regressions.json, preserving its formatting.
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


faa, dga = 'faa-phak-8083-25c', 'dga-2025-2030'
# DGA page 4: the right column's last bullet keeps its two sub-items, and the next title follows them.
page(dga, 4)['orderedText'] = ['+ 100% fruit or vegetable juice', 'Vegetables and fruits serving goals',
                               '- Vegetables: 3 servings per day', '- Fruits: 2 servings per day',
                               'Incorporate Healthy Fats', '+ Healthy fats are plentiful']
# DGA page 9: Older Adults reads its left column whole, then its right column.
extend(page(dga, 9), 'orderedText', ['Older Adults', '+ Some older adults need fewer calories',
                                     'nutrient-dense foods such as dairy, meats, seafood,',
                                     'eggs, legumes, and whole plant foods'])
extend(page(dga, 9), 'paragraphs', [
    '+ Some older adults need fewer calories but still require equal or greater amounts of key nutrients such as '
    'protein, vitamin B12, vitamin D, and calcium. To meet these needs, they should prioritize nutrient-dense foods '
    'such as dairy, meats, seafood,',
    'eggs, legumes, and whole plant foods (vegetables and fruits, whole grains, nuts, and seeds). When dietary intake '
    'or absorption is insufficient, fortified foods or supplements may be needed under medical supervision.'])
# FAA front matter: bare Roman folios are furniture (numerals no other text on these pages contains).
for number, folio in [(7, 'viii'), (12, 'xiii'), (15, 'xvi')]:
    extend(page(faa, number), 'absentText', [folio])
cases[faa]['basis'] += (' Pages 7, 12 and 15 (#105) source-reviewed: the bare Roman folios at the foot of the front '
                        'matter (iii to xvi, pages 3 to 15) are furniture, not paragraphs.')
cases[dga]['basis'] += (' Pages 4 and 9 (#103) reviewed against the source: Incorporate Healthy Fats follows the right '
                        'column\'s last bullet and its two sub-items, and the Older Adults bullet reads its left column '
                        'whole before its right column.')
open(path, 'w').write(json.dumps(r, indent=2, ensure_ascii=False) + '\n')
