#!/usr/bin/env python3
"""Apply this change's reviewed contract edits to corpus/regressions.json (idempotent).

List-valued keys are extended (existing phrases kept, duplicates skipped); `replace` swaps a key's
value outright (the three FAA orderedText checks that pinned a caption between a column's foot and
the next column's head, #111) and `drop` removes phrases that described the old split.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PATH = ROOT / 'corpus/regressions.json'

EDITS = {
    'faa-phak-8083-25c': {
        # Title art (#112): titles reflow as headings, the drop shadow is not an image.
        3: {'add': {'headings': ['Preface']}, 'set': {'maximumImages': 0}},
        453: {'add': {'headings': ['Performance Data for Cessna Model 172R and Challenger 605']},
              'set': {'minimumImages': 1}},
        461: {'add': {'headings': ['Acronyms, Abbreviations, and NOTAM Contractions'],
                      'paragraphs': ['This is a list of common acronyms and abbreviations used in the aviation '
                                     'industry as well as NOTAM contractions. For a more complete list']},
              'set': {'maximumImages': 0}},
        473: {'add': {'headings': ['Airport Signs and Markings']}, 'set': {'minimumImages': 1}},
        477: {'add': {'headings': ['Glossary']}, 'set': {'maximumImages': 0}},
        # Worked-example prose beside formula crops (#112).
        251: {'add': {'listItems': ['2. Enter the moment for each item listed. Remember “weight x arm = moment.”',
                                    '3. Find the total weight and total moment.']},
              'set': {'minimumImages': 2}},
        298: {'add': {'paragraphs': ['The height of the cloud base is 3,180 feet AGL.']},
              'set': {'minimumImages': 2}},
        # Same-page column continuations (#111).
        17: {'add': {'paragraphs': ['the balloon was little more than a billowing heap of cloth']}},
        103: {'add': {'paragraphs': ['until it eventually rejoins downstream. Form drag is the easiest to reduce']}},
        211: {'add': {'listItems': ['its upper limit provides the maximum flap speed. Approaches and landings']}},
        350: {'add': {'paragraphs': ['The system configuration depends on whether the runway is a precision']}},
        165: {'replace': {'orderedText': [
            'Figure 7-6. Changes in propeller blade angle from hub to tip.', 'Fixed-Pitch Propeller',
            'simplicity, and low cost are needed.',
            'Whether the airplane has a climb or cruise propeller installed depends upon its intended use.',
            'Figure 7-7. Relationship of travel distance and speed',
            'In a fixed-pitch propeller, the tachometer is the indicator of',
            'When operating altitude increases, the tachometer may not']}},
        199: {'replace': {'orderedText': [
            'Figure 7-45. Continuous flow mask and rebreather bag.', 'A pulse oximeter is a device that measures the amount of',
            # The joined paragraph also continues onto page 200, so #45 places the page's captions
            # ahead of it and of the heading directly above it.
            'within one percent of directly measured blood oxygen.',
            'Figure 7-46. EDS-011 portable pulse-demand oxygen system.', 'Servicing of Oxygen Systems',
            'Certain precautions should be observed whenever aircraft oxygen systems are to be serviced.',
            'Personal cleanliness and good housekeeping']}},
        262: {'replace': {'orderedText': [
            'Figure 11-5. Drag versus speed.', 'When an aircraft is in steady, level flight, the condition of',
            'The maximum level flight speed for the aircraft is obtained', 'Climb Performance',
            'Mechanical energy comes in two forms: (1) Kinetic Energy (KE), the',
            'Figure 11-6. Power versus speed.', 'We sometimes use the terms',
            'As an example of factor 2, an aircraft is flying level at 120']}},
    },
    'dga-2025-2030': {
        7: {'add': {'headings': ['Infancy & Early Childhood (Birth–4 Years)'],
                    'listItems': ['peanut introduction as early as 4 to 6 months']}},
        8: {'add': {'headings': ['Middle Childhood (5–10 Years)', 'Adolescence (11–18 Years)']}},
        9: {'add': {'headings': ['Young Adulthood', 'Pregnant Women', 'Lactating Women', 'Older Adults'],
                    'paragraphs': ['nutrient-dense foods such as dairy, meats, seafood, eggs, legumes, and whole plant foods']},
            'drop': {'paragraphs': [
                '+ Some older adults need fewer calories but still require equal or greater amounts of key nutrients such '
                'as protein, vitamin B12, vitamin D, and calcium. To meet these needs, they should prioritize '
                'nutrient-dense foods such as dairy, meats, seafood,',
                'eggs, legumes, and whole plant foods (vegetables and fruits, whole grains, nuts, and seeds). When dietary '
                'intake or absorption is insufficient, fortified foods or supplements may be needed under medical supervision.']}},
        10: {'add': {'headings': ['Individuals with Chronic Disease', 'Vegetarians & Vegans'],
                     'paragraphs': ['whereas vegan diets show broader shortfalls']}},
    },
}


def main():
    data = json.loads(PATH.read_text())
    for case in data['cases']:
        for number, edit in EDITS.get(case['id'], {}).items():
            entries = [entry for entry in case['pages'] if entry['page'] == number]
            if entries:
                entry = entries[0]
            else:
                entry = {'page': number}
                earlier = [i for i, e in enumerate(case['pages']) if e['page'] < number]
                case['pages'].insert(earlier[-1] + 1 if earlier else 0, entry)
            for key, phrases in edit.get('drop', {}).items():
                entry[key] = [p for p in entry.get(key, []) if p not in phrases]
            for key, phrases in edit.get('add', {}).items():
                entry[key] = entry.get(key, []) + [p for p in phrases if p not in entry.get(key, [])]
            for key, value in edit.get('set', {}).items():
                entry[key] = value
            for key, value in edit.get('replace', {}).items():
                entry[key] = value
    PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
