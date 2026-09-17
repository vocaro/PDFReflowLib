"""FAA joins with their class (from the traced refusals on the baseline) for the record."""
import json
import sys

CLASSES = {
    'caption-wrap (same page)': [(21, 21), (25, 25), (45, 45), (65, 65), (115, 115), (136, 136), (155, 155), (164, 164),
                                 (170, 170), (193, 193), (207, 207), (216, 216), (224, 224), (344, 344), (396, 396)],
    'caption-wrap (across pages)': [(19, 20), (68, 69), (154, 155), (158, 159), (159, 160), (217, 218), (223, 224),
                                    (259, 260), (441, 442)],
    'figure-only page between': [(45, 47), (60, 62), (106, 108), (251, 253), (292, 294), (326, 328), (329, 331),
                                 (331, 333), (405, 407)],
    'next line of the same column': [(18, 18), (230, 230), (235, 235), (341, 341), (391, 391)],
    'head below the foot under a column-head figure': [(411, 411)],
    'capital, digit or quote after an open word': [(19, 19), (109, 110), (122, 123), (126, 127), (145, 146), (251, 251),
                                                   (281, 281), (286, 287), (418, 419)],
}
joins = [j for j in json.load(open(sys.argv[1])) if j['between'] or j['next_page'] != j['end_page'] or j['end_page'] == 18]
seen = {}
for name, pairs in CLASSES.items():
    for pair in pairs:
        seen[pair] = seen.get(pair, 0) + 1
out = []
counts = {}
for j in joins:
    pair = (j['end_page'], j['next_page'])
    names = [n for n, pairs in CLASSES.items() if pair in pairs]
    if pair == (251, 251) and j['opening'] == 'digit':
        names = ['capital, digit or quote after an open word']
    if pair == (19, 19):
        names = ['capital, digit or quote after an open word']
    name = names[0] if len(names) == 1 else '|'.join(names)
    counts[name] = counts.get(name, 0) + 1
    out.append(f"p{j['end_page']}->{j['next_page']} [{j['between']}] {name}: …{j['end'][-60:]} ‖ {j['next'][:60]}…")
print(len(out), 'joins', counts)
print('\n'.join(out))
