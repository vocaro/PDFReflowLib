import json, sys
path = sys.argv[1]
r = json.load(open(path))
additions = {
    'faa-phak-8083-25c': ' Pages 136, 159 and 340 source rasters reviewed, with pages 91, 156, 165, 199 and 262 checked against extracted geometry (#76, #82): a 10-point bold or 11-point bold-italic sub-heading on its own line is a heading followed by its paragraph, not the paragraph\'s opening words; page 159\'s unpainted `Figure 5-16.` caption text ends at its own last line; page 340\'s two column titles on one row are two headings.',
    'arxiv-replay-clocks-2023': ' Page 6 source raster reviewed (#83): the section 6 title, whose second line hangs under the title text past its number, is one heading.',
    'gpo-911-2004': ' Page 91 checked against extracted geometry (#83): `3.2 ADAPTATION—AND NONADAPTATION—IN THE` and its hanging second line `LAW ENFORCEMENT COMMUNITY` are one heading.',
}
for case in r['cases']:
    if case['id'] in additions and additions[case['id']] not in case['basis']:
        case['basis'] += additions[case['id']]
open(path, 'w').write(json.dumps(r, indent=2, ensure_ascii=False) + '\n')
