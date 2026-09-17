import json, sys
# Adds the #76/#82/#83 content checks to corpus/regressions.json, preserving its formatting.
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
# #76: body-size sub-headings in the book's repeated bold styles open their paragraphs.
for number, pairs in [
    (136, [('Radius of Turn', 'The radius of turn is directly linked to the ROT')]),
    (156, [('Rudder', 'The rudder controls movement of the aircraft about its vertical axis'),
           ('V-Tail', 'The V-tail design utilizes two slanted tail surfaces'),
           ('Secondary Flight Controls', 'Secondary flight control systems may consist of wing flaps'),
           ('Flaps', 'Flaps are the most common high-lift devices')]),
    (159, [('Balance Tabs', 'The control forces may be excessively high'),
           ('Servo Tabs', 'Servo tabs are very similar in operation')]),
    (165, [('Fixed-Pitch Propeller', 'A propeller with fixed blade angles is a fixed-pitch propeller.')]),
    (262, [('Climb Performance', 'If an aircraft is to move, fly, and perform')]),
    (91, [('Pressure Altitude', 'Pressure altitude is the height above a standard datum plane'),
          ('Effect of Pressure on Density', 'Since air is a gas, it can be compressed or expanded.')]),
    (199, [('Pulse Oximeters', 'A pulse oximeter is a device that measures the amount of')]),
]:
    entry = page(faa, number)
    extend(entry, 'headings', [title for title, _ in pairs])
    # The paragraph opens with its own first words, not the sub-heading's.
    extend(entry, 'paragraphs', [opening for _, opening in pairs])
# #82: the unpainted `Figure 5-16.` caption ends at its own last line.
extend(page(faa, 159), 'distinctParagraphs', [{
    'first': 'Figure 5-16. The movement of the elevator is opposite to the direction of movement of the elevator trim tab.',
    'second': 'control pressures that may exist for that flight condition.'}])
# Two columns' titles on one row stay two headings.
entry = page(faa, 340)
extend(entry, 'headings', ['Runway Safety Area', 'Runway Safety Area Boundary Sign'])
extend(entry, 'absentHeadings', ['Runway Safety Area Runway Safety Area Boundary Sign'])

# #83: a numbered title's second line hanging under its text continues it.
entry = page('arxiv-replay-clocks-2023', 6)
extend(entry, 'headings', ['6 REPRESENTATION OF REPCL AND ITS OVERHEAD', '7 SIMULATION RESULTS'])
extend(entry, 'absentHeadings', ['OVERHEAD', '6 REPRESENTATION OF REPCL AND ITS'])
entry = page('gpo-911-2004', 91)
extend(entry, 'headings', ['3.2 ADAPTATION—AND NONADAPTATION—IN THE LAW ENFORCEMENT COMMUNITY'])
extend(entry, 'absentHeadings', ['LAW ENFORCEMENT COMMUNITY', '3.2 ADAPTATION—AND NONADAPTATION—IN THE'])

open(path, 'w').write(json.dumps(r, indent=2, ensure_ascii=False) + '\n')
