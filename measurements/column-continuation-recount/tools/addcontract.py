#!/usr/bin/env python3
"""Apply this change's reviewed contract edits to corpus/regressions.json (idempotent).

List-valued keys are extended (existing entries kept, duplicates skipped); `replace` swaps a key's
value (page 286's orderedText, which pinned figure 12-2's caption after the paragraph that now
continues onto page 287, #118). Every phrase was read on the rendered source page.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PATH = ROOT / 'corpus/regressions.json'

EDITS = {
    'faa-phak-8083-25c': {
        # A capital after a word that cannot end a sentence, same page (left foot, right head under the map).
        19: {'add': {'paragraphs': ['had initiated this system. The Department of Commerce made significant advances']}},
        # A caption's wrapped 9-pt line no longer competes above the column head.
        21: {'add': {'paragraphs': ['then, now, and into the future. The DOT began operation on April 1, 1967.']}},
        # Across a page holding only figure 2-6 (page 46).
        45: {'add': {'continuedParagraphs': [{'end': 'specific to the pilot and assesses health, fatigue, weather,',
                                              'next': 'capabilities, etc. The scores are added', 'nextPage': 47}]}},
        # A caption's wrapped line beside the anchor on the next page.
        68: {'add': {'continuedParagraphs': [{'end': 'percent of all GA accidents take place in the',
                                              'next': 'landing phase, one realm of flight that still does not involve'}]}},
        # A digit after an open word across the page, with nothing between.
        126: {'add': {'continuedParagraphs': [{'end': 'Propeller efficiency varies from 50 to',
                                               'next': '87 percent, depending on how much the propeller'}]}},
        # A capital after an article across the page.
        145: {'add': {'continuedParagraphs': [{'end': 'further increasing the',
                                               'next': 'AOA. In this situation, without reliable AOA information'}]}},
        # The next line of the same column, split by the figure set beside it.
        230: {'add': {'paragraphs': ['welded together in a single strip and twisted into a helix. One end is anchored']}},
        235: {'add': {'paragraphs': ['(not provided with the standard aircraft). Some of this information may be supplied']}},
        # A digit after `every`; figure 12-2 keeps page 286 ahead of the joined paragraph.
        286: {'add': {'continuedParagraphs': [{'end': 'decreases at a rate of about 2 °Celsius (C) every',
                                               'next': '1,000 feet of altitude gain, and the pressure decreases'}]},
              'replace': {'orderedText': [
                  'The atmosphere is a blanket of air made up of a mixture of gases',
                  'Life on Earth is supported by the atmosphere', 'nitrogen accounts for 78 percent',
                  'Four distinct layers or spheres of the',
                  'atmosphere have been identified using thermal characteristics',
                  'Figure 12-2. Layers of the atmosphere.', 'The first layer, known as the troposphere']}},
        341: {'add': {'paragraphs': ['relative location of the respective runway thresholds. Figure 14-10 shows']}},
        # The continuation head lies lower than the foot, beneath the figure heading its column.
        411: {'add': {'paragraphs': ['by means of the course select knob. The HSI has a fixed aircraft symbol']}},
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
            for key, value in edit.get('replace', {}).items():
                entry[key] = value
    return data


if __name__ == '__main__':
    PATH.write_text(json.dumps(apply(json.loads(PATH.read_text())), indent=2, ensure_ascii=False) + '\n')
