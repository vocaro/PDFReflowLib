import json, sys
# Adds the #109 content checks to corpus/regressions.json. Run from the repository root:
#   python3 measurements/tall-rows-and-minus/tools/addcontract.py corpus/regressions.json
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
# A line whose rectangle an inline expression makes tall keeps the next line in its paragraph.
extend(page(algebra, 9), 'paragraphs', ['The second problem is a multiplication problem because there is nothing between the 3 and the parenthesis.',
                                        'but if the signs match on multiplication, the answer is positive, (− 3)(− 7) = 21.'])
extend(page(algebra, 90), 'paragraphs', ['The second point, B (− 2, 1), is left 2 (negative moves backwards), up 1.',
                                         'The third point, C (3,− 4) is right 3, down 4 (negative moves backwards).'])
extend(page(algebra, 90), 'distinctParagraphs', [{'first': 'The second point, B (− 2, 1), is left 2', 'second': 'The third point, C (3,− 4) is right 3'}])
extend(page(algebra, 120), 'paragraphs', ['Square bracket means less than or equal to'])
extend(page(algebra, 180), 'paragraphs', ['rather we multiply 5 three times, 5 × 5 × 5 = 125. This is shown in the next example.'])
extend(page(algebra, 318), 'paragraphs', ['Then if we multiply both sides of the equation again by i, the equation becomes i4',
                                          'One more time gives i6 = i2 =− 1. And if this pattern continues we see a cycle forming',
                                          'As there are 4 diﬀerent possible answers in this cycle, if we divide the exponent by 4'])
extend(page(algebra, 401), 'paragraphs', ['If we plug this output into the inverse function we get f−1(8) = (8)− 5= 3, which is the original input.',
                                          'If it is anything but x the functions are not inverses.'])
extend(page(algebra, 401), 'distinctParagraphs', [{'first': 'which is the original input.', 'second': 'Often the functions are much more involved'}])
# A joined row that opens with a minus sign before a number is prose, not a list line.
extend(page(algebra, 321), 'paragraphs', ['If i is − 1 √ , and it is in the denominator of a fraction, then we have a radical in the denominator!'])
# Controls: lines that open with a minus and are not joined rows stay list lines.
extend(page(algebra, 2), 'listItems', ['− Your fair dealing or fair use rights', '− The author’s moral rights;'])
extend(page(algebra, 9), 'listItems', ['− 24 Our Solution'])
extend(page(algebra, 120), 'listItems', ['− 18 <− 12'])
cases[algebra]['basis'] += (' Pages 2, 9, 90, 120, 180, 318, 321 and 401 source-reviewed (#109): a line holding an inline minus, '
                            'times or radical sign, whose rectangle extends 8.5 points past its type, continues its paragraph into '
                            'the next line; page 90\'s point descriptions and page 401\'s two paragraphs stay separate; page 321\'s '
                            'radicand − 1 reads inside its sentence; the license\'s minus bullets on page 2 and the derivation lines '
                            'on pages 9 and 120 stay list lines.')
with open(path, 'w') as f:
    json.dump(r, f, indent=2, ensure_ascii=False)
    f.write('\n')
