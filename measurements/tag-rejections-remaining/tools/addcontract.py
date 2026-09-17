import json, sys
# Adds the #91 content checks to corpus/regressions.json, preserving its formatting.
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

def distinct(case, number, first, second):
    extend(page(case, number), 'distinctParagraphs', [{'first': first, 'second': second}])

faa, dga = 'faa-phak-8083-25c', 'dga-2025-2030'
# FAA: tag groups that a space-only show past a line's end used to reject now apply. Rows, address
# lines and checklist entries the source tags one per paragraph stop fusing (page 392's time-zone rows
# included); page 318's wrapped report value reads whole.
distinct(faa, 392, 'Eastern Standard Time', 'Central Standard Time')
distinct(faa, 24, '800 Independence Ave, SW', 'Washington, DC 20591')
distinct(faa, 236, 'P.O. Box 25504', 'Oklahoma City, OK 73125-0504')
distinct(faa, 55, 'Alternatives—delay until morning', 'dangers and distractions of fatigue could lead to an accident')
distinct(faa, 64, 'Shoulder harness fastened for takeoff, landing', 'Seat position adjusted and locked in place')
distinct(faa, 207, 'Abilene altimeter setting 29.69', 'Difference 0.25')
distinct(faa, 251, 'Weight of front seat occupants', 'Weight of rear seat occupants')
distinct(faa, 249, '6.5 lb/US gal', '8.35 lb/US gal')
distinct(faa, 416, 'MH Under 50', 'H 50–1999')
extend(page(faa, 318), 'paragraphs', ['25 NM out on the 090° radial, Gregg County VOR'])
# DGA: bullets and letter paragraphs the page tags apply once their trailing space shows cost nothing.
distinct(dga, 2, 'for so many Americans.', 'The United States is amid a health emergency.')
extend(page(dga, 4), 'orderedText', ['+ 100% fruit or vegetable juice', 'Vegetables and fruits serving goals',
                                     'Incorporate Healthy Fats'])
extend(page(dga, 8), 'paragraphs', [
    '+ Focus on whole, nutrient-dense foods such as protein foods, dairy, vegetables, fruits, healthy fats, and whole grains.',
    '+ Adolescents should eat nutrient-dense foods such as dairy, leafy greens, and iron-rich animal foods, while '
    'significantly limiting sugary drinks and energy drinks and avoiding highly processed foods.'])
extend(page(dga, 9), 'paragraphs', [
    '+ Pregnant women should consume diverse nutrient-dense foods, including iron-rich meats, folate-rich greens and legumes'])
cases[faa]['basis'] += (' Pages 24, 55, 64, 207, 249, 251, 318, 392 and 416 (#91) source-reviewed: with space-only shows '
                        'no longer rejecting their tag groups, tagged table rows, time-zone rows, address lines and '
                        'checklist entries stay separate paragraphs.')
cases[dga]['basis'] += (' Pages 2, 4, 8 and 9 (#91) reviewed against the source: with space-only shows no longer '
                        'rejecting their tag groups, letter paragraphs separate, the right-column bullets precede the next '
                        'section title, and two-column bullets read whole.')
open(path, 'w').write(json.dumps(r, indent=2, ensure_ascii=False) + '\n')
