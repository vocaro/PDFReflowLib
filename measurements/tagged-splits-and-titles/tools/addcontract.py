import json, sys
# Adds the #89/#90 content checks to corpus/regressions.json, preserving its formatting.
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
# #89: paragraphs the source tags in two pieces, one piece falling back beside a figure or the column
# spaced only around a heading, read whole; a paragraph break the page sets with space stays.
for number, joined, distinct in [
    (96, 'affected portion of the airfoil. Manufacturers have developed different methods',
     ('resulting in a measurable velocity force and direction.', 'Manufacturers have developed different methods')),
    (114, 'the horizontal tail surface. Conclusion: with CG forward of the CL',
     ('return to a safe flying attitude.', 'The following is a simple demonstration of longitudinal stability.')),
    (127, 'there is maximum thrust. After liftoff, as the speed of the aircraft increases',
     ('keeps thrust at a maximum.', 'After the takeoff climb is established')),
    (128, 'in the direction of rotation. The rotating propeller of an airplane makes a very good', None),
    (179, '[Figure 7-21] Detonation is an uncontrolled, explosive ignition', None),
    (235, 'propeller, or components. This section also describes preventive maintenance that',
     ('The Supplements section contains information', 'This section also describes preventive maintenance that')),
    (263, 'the steeper it can climb. Maximum AOC occurs at the airspeed', None),
    (360, '[Figure 14-44] In addition to basic radar service, terminal radar service',
     ('if known, are given.', 'An example would be:')),
    (366, 'heading are aligned. Under certain circumstances, it may be necessary', None),
    (412, 'older types of heading indicators. The remote compass transmitter is a separate unit', None),
]:
    entry = page(faa, number)
    extend(entry, 'paragraphs', [joined])
    if distinct:
        extend(entry, 'distinctParagraphs', [{'first': distinct[0], 'second': distinct[1]}])
# Controls: NDB table rows (page 416) and a TAF's change groups (page 319) stay separate.
extend(page(faa, 416), 'distinctParagraphs', [{'first': 'Compass Locator Under 25 15', 'second': 'MH Under 50'}])
extend(page(faa, 319), 'distinctParagraphs', [{'first': 'FM1500 16015G25KT P6SM SCT040 BKN250',
                                               'second': 'FM120000 14012KT P6SM BKN080 OVC150'}])

# #90: tagged titles are headings, each its own (page 27's stacked titles), above their paragraphs.
for number, titles in [
    (27, ['Pilot and Aeronautical Information', 'Notices to Airmen (NOTAMs)', 'NOTAM (D) Information']),
    (45, ['Likelihood of an Event', 'Severity of an Event']),
    (49, ['Managing External Pressures']),
    (54, ['PAVE Checklist: Identify Hazards and Personal Minimums']),
    (72, ['Introduction']),
    (152, ['Differential Ailerons', 'Frise-Type Ailerons', 'Coupled Ailerons and Rudder']),
    (285, ['Introduction']),
    (311, ['Introduction']),
    (383, ['Operating Rules and Pilot/Equipment Requirements']),
    (409, ['Very High Frequency (VHF) Omnidirectional Range (VOR)']),
    (429, ['Vestibular Illusions', 'The Leans', 'Coriolis Illusion', 'Graveyard Spiral']),
]:
    extend(page(faa, number), 'headings', titles)
extend(page(faa, 27), 'absentHeadings', ['Pilot and Aeronautical Information Notices to Airmen (NOTAMs)'])
# The title follows the figure its page sets beside it, directly above the paragraph it opens (#63).
extend(page(faa, 54), 'orderedText', ['Risk management processing can take place in any of three timeframes.',
                                      'PAVE Checklist: Identify Hazards and Personal Minimums',
                                      'In the first step, the goal is to develop situational awareness'])
extend(page(faa, 152), 'orderedText', ['Frise-type ailerons.', 'Coupled Ailerons and Rudder',
                                       'Coupled ailerons and rudder are linked controls.'])
for number, title, first in [(72, 'Aircraft Construction', 'An aircraft is a device that is used'),
                             (285, 'Weather Theory', 'Weather is an important factor that influences'),
                             (311, 'Aviation Weather Services', 'In aviation, weather service is a combined effort')]:
    extend(page(faa, number), 'orderedText', [title, 'Introduction', first])
# Controls: contents labels over leader entries and a centred table title are not headings.
extend(page(faa, 6), 'absentHeadings', ['Chapter 1', 'Chapter 2'])
extend(page(faa, 15), 'absentHeadings', ['Appendix A', 'Appendix B'])
extend(page(faa, 416), 'absentHeadings', ['NONDIRECTIONAL RADIO BEACON (NDB)'])
# Lettered appendix folios are furniture, never headings.
for number, folio in [(457, 'A-5'), (458, 'A-6'), (459, 'A-7'), (474, 'C-2'), (475, 'C-3'), (476, 'C-4')]:
    extend(page(faa, number), 'absentHeadings', [folio])

flag = 'gpo-our-flag-2003'
# #89: the Beecher and Wilson quotations, tagged a line at a time, read as their paragraphs.
extend(page(flag, 12), 'paragraphs', ['a symbol of Liberty and men rejoiced in it.',
                                      'As at early dawn the stars shine forth',
                                      'whether in peace or in war. And yet, though silent, it speaks to us—speaks to us of the past'])

cases[faa]['basis'] += (' Pages 96, 114, 127, 128, 179, 235, 263, 360, 366 and 412 (#89) source-reviewed: a paragraph '
                        'the source tags in two pieces, one of them falling back beside a figure or in a justified '
                        'column spaced only around a heading, reads as one paragraph; page 319\'s TAF change groups and '
                        'page 416\'s NDB table rows stay separate. Pages 27, 45, 49, 54, 72, 152, 285, 311, 383, 409 and '
                        '429 (#90) source-reviewed: tagged titles in the book\'s bold, bold-italic and italic title '
                        'styles are headings, stacked titles stay two headings, and titles on pages 54 and 152 follow '
                        'their figure directly above the paragraph they open; contents labels (pages 6, 15) and a '
                        'centred table title (416) are not headings. Lettered appendix folios A-5 to A-7 and C-2 to '
                        'C-4 are furniture, not headings.')
cases[flag]['basis'] += (' Page 12 (#89) source-reviewed: the Beecher and Wilson quotations, tagged one line per group, '
                         'join where each line wraps onto the next.')
open(path, 'w').write(json.dumps(r, indent=2, ensure_ascii=False) + '\n')
