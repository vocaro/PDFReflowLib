#!/usr/bin/env python3
"""Apply this change's reviewed contract edits to corpus/regressions.json (idempotent, #145).

List-valued keys are extended (existing entries kept, duplicates skipped). Every phrase was read on the
rendered source page.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PATH = ROOT / 'corpus/regressions.json'

EDITS = {
    'faa-phak-8083-25c': {
        # One tagged paragraph across the page, a capital after `Aid` and `Air`.
        20: {'add': {'continuedParagraphs': [{'end': 'the responsibility of administering the Federal Aid',
                                              'next': 'Airport Program. This program was designed to promote'}]}},
        21: {'add': {'continuedParagraphs': [{'end': 'An earlier period of discord between management and the Professional Air',
                                              'next': 'Traffic Controllers Organization (PATCO) culminated in'}]}},
        # One tagged paragraph from the left column's foot to the right column's head, past figure 1-13.
        24: {'add': {'paragraphs': ['through training, outreach, and education. The FAA Safety Team (FAASTeam) exemplifies this commitment.']}},
        # An open parenthesis across the page.
        169: {'add': {'continuedParagraphs': [{'end': 'Fahrenheit degrees (70 x 100/180 = 38.89',
                                               'next': 'Celsius degrees) (Remember there are 180 Fahrenheit degrees'}]}},
        # The column's last line ends short on a comma.
        221: {'add': {'continuedParagraphs': [{'end': 'Errors in the magnetic compass are numerous,',
                                               'next': 'making straight flight and precision turns to headings difficult'}]}},
        320: {'add': {'continuedParagraphs': [{'end': 'with a scattered layer at 10,000 feet AGL. After',
                                               'next': '2000Z, the forecast calls for scattered thunderstorms'}]}},
        # Whole captions release the column's next line and the page join.
        341: {'add': {'paragraphs': ['Figure 14-8. Runway safety area boundary sign and marking located on Taxiway Kilo.',
                                     'Figure 14-9. Runway holding position sign at takeoff end of Runway 14 with collocated Taxiway Alpha location sign.'],
                      'continuedParagraphs': [{'end': 'the threshold for Runway 18 is to the left and the threshold for',
                                               'next': 'Runway 36 is to the right. The sign also indicates'}]}},
        391: {'add': {'paragraphs': ['Figure 16-4. Meridians and parallels—the basis of measuring time, distance, and direction.'],
                      'continuedParagraphs': [{'end': 'must be completed before dark. Remember, an hour is lost when',
                                               'next': 'flying eastward from one time zone to another'}]}},
        397: {'add': {'paragraphs': ['Figure 16-16. Relationship between true, magnetic, and compass headings for a particular instance.'],
                      'listItems': ['• GS—rate of the aircraft’s inflight progress over the ground.']}},
        438: {'add': {'continuedParagraphs': [{'end': 'states have taken steps to allow the possession, sale,',
                                               'next': 'and use of marijuana withing their border.'}]}},
    },
    'scotus-loper-bright-2024': {
        # An open parenthesis across the page (the syllabus and the opinion).
        3: {'add': {'continuedParagraphs': [{'end': '576 U. S. 743, 750 (quoting Allentown Mack Sales &',
                                             'next': 'Service, Inc. v. NLRB, 522 U. S. 359, 374). By doing so'}]}},
        34: {'add': {'continuedParagraphs': [{'end': 'See Buffington v. McDonough, 598 U. S. ___, ___ (2022) (GORSUCH,',
                                              'next': 'J., dissenting from denial of certiorari)'}]}},
    },
}


def apply(data):
    for case in data['cases']:
        for number, edit in EDITS.get(case['id'], {}).items():
            entries = [entry for entry in case['pages'] if entry['page'] == number]
            if entries:
                entry = entries[0]
            else:
                entry = {'page': number}
                earlier = [i for i, e in enumerate(case['pages']) if e['page'] < number]
                case['pages'].insert(earlier[-1] + 1 if earlier else 0, entry)
            for key, values in edit.get('add', {}).items():
                entry[key] = entry.get(key, []) + [v for v in values if v not in entry.get(key, [])]
    return data


if __name__ == '__main__':
    PATH.write_text(json.dumps(apply(json.loads(PATH.read_text())), indent=2, ensure_ascii=False) + '\n')
