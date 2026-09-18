import json, sys

path = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a1a8c9518159e03c1/corpus/regressions.json'
doc = json.load(open(path))
cases = {c['id']: c for c in doc['cases']}

MAG = 'usda-ars-agresearch-2012-11'
THM = 'ntrs-20210020887-techport-thm-2021'

additions = {
    MAG: {
        2: {"text": ["Agriculture is about producing food,",
                     "The U.S. Department of Agriculture has been extremely active for more than 100",
                     "war-fighters often find themselves in places",
                     "Daniel Strickman"],
            "orderedText": ["Agriculture is about producing food,",
                            "In 1941, the U.S. military asked USDA",
                            "Discovering new insecticides for use",
                            "Scientific evaluation of insecticide ap-"]},
        3: {"text": ["Agricultural Research is published 10 times a year by",
                     "Editor: Robert Sowers",
                     "20 Livestock Waste Management 2.0:",
                     "The dried inflorescence of the breadfruit tree is burned in some"]},
        13: {"absentWarningCodes": ["unverifiedTextLayer"]},
        14: {"text": ["Studies have shown that insecticide", "Getting Products to Troops",
                      "and sand flies in a hot, arid environment."]},
        16: {"headings": ["Finding Ways To Save Water in Peach Orchards"],
             "text": ["Agricultural engineer Huihui Zhang measures peach tree leaf"]},
        20: {"headings": ["Livestock Waste Management 2.0 Recycling Ammonia Emissions as Fertilizer"],
             "text": ["One of the costs of running a farm", "recorded an average removal rate of 45 to"],
             "absentWarningCodes": ["pageImageFallback", "unsupportedGraphics"]},
        21: {"headings": ["Eco-Based Fire Logs An Environmentally Friendly Invention From ARS"],
             "text": ["from a perhaps surprising source: grass clippings.",
                      "the eco-logs burn cleaner, emitting fewer potentially"],
             "absentWarningCodes": ["pageImageFallback", "unsupportedGraphics"]},
        22: {"headings": ["2012 INDEX"],
             "text": ["Air quality, no-till spring cereal rotations and, Jul-19",
                      "compounds in hulls may benefit health, Feb-22",
                      "ARS Scientists: All-Purpose Agronomists, Aug-2"]},
        23: {"text": ["Zoonotic diseases, leptospirosis, Jan-10",
                      "Wheat, statistical approach used in breeding, Apr-13"]},
    },
    THM: {
        1: {"headings": ["Tank Health Monitoring", "Table of Contents"],
            "text": ["Advanced Exploration Systems Division", "Project Introduction 1",
                     "Technology Maturity (TRL) 2"]},
        5: {"text": ["Existing propellant gauging", "The Basic Formula",
                     "Accurate measurement of cryogenic"]},
    },
}

basis = {
    MAG: " Pages 2, 3, 13, 14, 16 and 20-23 reviewed again at 50 DPI with every crop outlined (#158): the"
         " FORUM columns and the signature box, the masthead staff list, the contents entries, the"
         " breadfruit caption, the columns over the faded flag, the peach-orchard title and its"
         " photograph caption, both boxed-title articles over their page-wide gradient, and the 2012"
         " index entries are text; only the photographs, ornaments and the flag's own strip stay"
         " images. Page 13's photograph no longer covers the page, so its text carries no review"
         " warning. Column order on pages 14 and 20-23 is not approved (#153), so those pages are"
         " checked by phrase rather than in order.",
    THM: " Pages 1 and 5 reviewed again at 50 DPI with every crop outlined (#166): the header band's"
         " division, project title and state, the sidebar's caption and table of contents, and the"
         " gallery's three captions are text, while the insignia, the sidebar photograph and the three"
         " gallery pictures stay images. The gallery captions' order is not approved (#153).",
}

for case_id, pages in additions.items():
    case = cases[case_id]
    case['basis'] = case['basis'].rstrip() + basis[case_id]
    byPage = {p['page']: p for p in case['pages']}
    for number, checks in pages.items():
        entry = byPage.get(number)
        if entry is None:
            entry = {"page": number}
            case['pages'].append(entry)
        for key, value in checks.items():
            if key in entry and isinstance(entry[key], list):
                entry[key] = entry[key] + [v for v in value if v not in entry[key]]
            else:
                entry[key] = value
    case['pages'].sort(key=lambda p: p['page'])

open(path, 'w').write(json.dumps(doc, indent=2, ensure_ascii=False) + '\n')
print('written')
