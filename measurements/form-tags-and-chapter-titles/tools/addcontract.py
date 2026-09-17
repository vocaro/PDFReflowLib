import json, sys
# Adds the #75/#84 content checks to corpus/regressions.json, preserving its formatting.
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
# #84: chapter openers the source tags as paragraphs stay headings once their pages' tags apply.
for number, titles, first in [
    (88, ['Chapter 4', 'Principles of Flight', 'Introduction'], 'This chapter examines the fundamental physical laws'),
    (98, ['Chapter 5', 'Aerodynamics of Flight', 'Forces Acting on the Aircraft'], 'Thrust, drag, lift, and weight are forces'),
    (231, ['Chapter 9', 'Flight Manuals and Other Documents', 'Introduction'], 'Each aircraft comes with documentation'),
    (335, ['Chapter 14', 'Airport Operations', 'Introduction'], 'Each time a pilot operates an aircraft'),
]:
    entry = page(faa, number)
    extend(entry, 'headings', titles)
    extend(entry, 'orderedText', titles + [first])
# Page 203: one tagged group spans `Introduction`, its paragraph, the next title and its paragraph.
extend(page(faa, 203), 'headings', ['Chapter 8', 'Introduction', 'Pitot-Static Flight Instruments'])
extend(page(faa, 203), 'orderedText', ['Chapter 8', 'Introduction', 'In order to safely fly any aircraft',
                                       'Pitot-Static Flight Instruments', 'The pitot-static system is a combined system'])
extend(page(faa, 203), 'paragraphs', ['In order to safely fly any aircraft', 'The pitot-static system is a combined system'])
# #75: page 89's columns read in order once its tags apply.
extend(page(faa, 89), 'orderedText', ['When most people hear the word', 'Viscosity', 'All fluids are viscous',
                                      'Another factor at work when a fluid flows', 'The surface of a wing, like any other surface'])
extend(page(faa, 89), 'paragraphs', ['they usually think of liquid. However, gasses, like air, are also fluids.'])
# Paragraphs the source tags in pieces read whole.
extend(page(faa, 105), 'paragraphs', ['upon stability. The allowable location of the CG'])
extend(page(faa, 211), 'paragraphs', ['placards and in the AFM/POH. These airspeeds include:'])
extend(page(faa, 227), 'paragraphs', ['compass rose aids compensation for deviation errors.'])

dga = 'dga-2025-2030'
# #75: the two-column bullet lists on pages 3-5 read item by item once the pages' tags apply.
extend(page(dga, 3), 'paragraphs', ['+ Prioritize high-quality, nutrient-dense protein foods as part of a healthy dietary pattern.',
                                    '+ Consume meat with no or limited added sugars, refined carbohydrates or starches, or chemical additives.'])
extend(page(dga, 4), 'distinctParagraphs', [{'first': '+ Prioritize fiber-rich whole grains.',
                                             'second': '+ Significantly reduce the consumption of highly processed'}])
extend(page(dga, 5), 'distinctParagraphs', [{'first': 'or end in “-ose.”', 'second': '+ Added sugars may appear on ingredient labels'}])
extend(page(dga, 5), 'paragraphs', ['+ Limit foods and beverages that include artificial flavors'])

cases[faa]['basis'] += (' Pages 88, 98, 203, 231 and 335 (#84): chapter openers tagged P remain headings once their '
                        'text-free Form XObjects no longer discard the page tags; page 203 source-reviewed, its tagged '
                        'group spanning Introduction and the next section falls back. Page 89 (#75) source-reviewed: '
                        'the applied tags read the viscosity and friction columns in order. Pages 105, 211 and 227 '
                        'source-reviewed: paragraphs and a caption the source tags in pieces read as one element.')
cases[dga]['basis'] += (' Pages 3-5 (#75) reviewed against the source: with the page tags applied, each bullet of '
                        'the two-column lists reads whole instead of interleaving line by line.')
open(path, 'w').write(json.dumps(r, indent=2, ensure_ascii=False) + '\n')
