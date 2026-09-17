import json
path = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a11a7ffaa3ea102c4/corpus/regressions.json'
d = json.load(open(path))
case = next(c for c in d['cases'] if c['id'] == 'nbs-jres-geltman-1977')
R = 'corpus/references/nbs-jres-geltman-1977/'
case['basis'] = (
    "Source pages 1-7 visually reviewed against renders. Pages 1-6 carry Adobe Paper Capture inline images over "
    "what its OCR could not transcribe; they are evidence, not crop bounds (#37). Every page reflows with the "
    "unverified-text warning and its source-page reference. Figures 1 and 2 are each one whole crop ending above "
    "their captions, which stay text; their OCR labels do not reflow. Display equations with evidence, and those "
    "the formula heuristic crops, grow to their whole display row with the equation number; the region references "
    "exclude the source-page image, which contains every region. Unboxed equation (8) remains OCR text. "
    "Page 7 protects the unverified-text warning over its inherited Paper Capture OCR and the reference heading. "
    "After #36 the closing left-column prose must reflow as text in source order, ending with its final line inside "
    "one paragraph; the inline equation `u0 = eE0/mω` inside a justified line earlier in the column is prose, not a "
    "displayed formula, so that line and its neighbours reflow in the paragraph instead of a three-line crop (#51). "
    "Reference transcriptions are noisy and are not asserted.")
scan = {'warningCodesAnyOf': ['unverifiedTextLayer'], 'absentWarningCodes': ['pageImageFallback', 'unsupportedGraphics']}
pages = [
    {'page': 1,
     'text': ['Stimulated Multiphoton Bremsstrahlung', 'instantaneous resultant velocity'],
     'orderedText': ['1. Introduction', '2. Classical Picture', 'In such an impact model'],
     'imageRegions': [{'reference': R + 'page-1-page.png'},
                      {'reference': R + 'page-1-equation-4.png', 'excludePageReference': True}],
     'minimumImages': 2, **scan},
    {'page': 2,
     'orderedText': ['Trajectory of an electron', 'from which we see it depends upon the wave phase'],
     'absentText': ['--.t - - -'],
     'imageRegions': [{'reference': R + 'page-2-figure-1.png', 'excludePageReference': True},
                      {'reference': R + 'page-2-equation-11.png', 'excludePageReference': True}],
     'minimumImages': 2, **scan},
    {'page': 3,
     'orderedText': ['Cycle-averaged rate of classical energy', 'A more complete classical treatment'],
     'absentText': ['Uo ~ ~ (a . u . )'],
     'imageRegions': [{'reference': R + 'page-3-figure-2.png', 'excludePageReference': True},
                      {'reference': R + 'page-3-equation-15.png', 'excludePageReference': True}],
     'minimumImages': 2, **scan},
    {'page': 4, 'text': ['where the sums include all bound and continuum states'], 'minimumImages': 2, **scan},
    {'page': 5, 'text': ['Weingartshofer et al. [25} data'], 'absentText': ['E;\'" eV'], 'minimumImages': 3, **scan},
    {'page': 6, 'text': ['Factor representing multiphoton contribution'], 'absentText': ['O·tt:----+----+----I'],
     'minimumImages': 2, **scan},
]
old7 = next(p for p in case['pages'] if p['page'] == 7)
case['pages'] = pages + [old7]
open(path, 'w').write(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
