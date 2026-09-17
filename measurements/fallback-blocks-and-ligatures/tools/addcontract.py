import json
import sys
# Adds the #122 and #123 (items 1–2) content checks to corpus/regressions.json. Run from the
# repository root:
#   python3 measurements/fallback-blocks-and-ligatures/tools/addcontract.py corpus/regressions.json
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


cdc = 'cdc-zombie-pandemic-2011'
# #122: a balloon beside a caption box reads whole, the left unit first. The inherited text
# layer's damaged spelling is quoted as extracted (#7).
extend(page(cdc, 14), 'paragraphs', ['le t \'s tr y the radio...'])
extend(page(cdc, 14), 'orderedText', ['Nothing eut snow .', 'le t \'s tr y the radio...', 'sray in your Homes.',
                                      'slow bo MovBMenr', 'thbm ro a secure area', 'sray runed For more'])
extend(page(cdc, 23), 'paragraphs', ['aLm ost a week, todd, and we haven\'t le f t the'])
extend(page(cdc, 23), 'orderedText', ['w e\'re aLmosT', 'H o u s e !', '...coNr/Nues ro spreAd.', 'cdc is ure/Ne',
                                      'stay in your Homes.', 'ro a des/eNAred'])
extend(page(cdc, 34), 'paragraphs', ['wow... THAT o ld THINg STILL'])
extend(page(cdc, 34), 'orderedText', ['wow... THAT', 'w o r k s !', '.severe TttuaeesTom', 'in effect fo r THe'])
# #122: the rotated OCR caption reads in line order. OCR transcription depends on the compiled
# Vision models (#94); the phrases are the lines' opening words only.
extend(page(cdc, 17), 'orderedText', ['SEVERAL DAYS LATER', 'DISEASE CONTROL', 'ATLANTA'])

algebra = 'wallace-algebra-2010'
# #123 item 1: `dif-` + `ferent` joins on the book's ligature spelling `diﬀerent`.
extend(page(algebra, 50), 'paragraphs', ['just written in a different form because we solved them in'])
extend(page(algebra, 50), 'absentText', ['dif-ferent'])
extend(page(algebra, 218), 'paragraphs', ['more than just the signs are different. In this case'])
extend(page(algebra, 218), 'absentText', ['dif-ferent'])
# #123 item 2: the spaced example lines are paragraphs of their own, not part of the list items.
extend(page(algebra, 64), 'paragraphs', ['Three more than a number becomes x + 3', 'Four less than a number becomes x− 4'])

def note(case, text):
    if text not in cases[case]['basis']:
        cases[case]['basis'] += ' ' + text


note(cdc, 'Pages 14, 23, 34 and 17 source rasters reviewed (#122): a speech balloon beside a caption box reads '
     'whole, the left unit first (page 14 `Nothing but snow. Let\'s try the radio...` before the broadcast, page 23 '
     'the left-panel balloon before the right-panel broadcast, page 34 `wow... that old thing still works!` before '
     'the storm warning); the rotated OCR caption on page 17 reads its three lines in order. Balloon order across '
     'panels (#18) is not blessed.')
note(algebra, 'Pages 50, 218 and 64 source rasters reviewed (#123): `dif-` + `ferent` joins as `different`, which the '
     'book prints with the U+FB00 ligature; the spaced example lines `Three more than a number becomes x + 3` and '
     '`Four less than a number becomes x− 4` are paragraphs of their own after their list items. The `Is` bullet '
     'inside page 64\'s formula crop is not blessed.')


json.dump(r, open(path, 'w'), indent=2, ensure_ascii=False)
open(path, 'a').write('\n')
