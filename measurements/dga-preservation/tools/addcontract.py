"""#117 DGA contract additions. Idempotent: run on the tip's regressions.json."""
import json

p = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a5c85a3e7f625e901/corpus/regressions.json'
d = json.load(open(p))
case = next(c for c in d['cases'] if c['id'] == 'dga-2025-2030')
note = (" Pages 2-8 (#117) reviewed against the source: pages 3-5 cluster section bands, icons, callout boxes and a"
        " margin timeline into a page-sized region whose crops leave only the running foot, so they reflow beside the"
        " banner, icon and footer crops without the unverified-text-layer warning or a source-page reference; the"
        " Gut Health, Added Sugars, Sodium and infant-feeding callouts reflow with their tab titles; page 6's first"
        " bullet row and page 2's footnotes 2 and 4 leave their crops. Page 1 keeps the reference and warning"
        " deliberately: its visible lettering is filled outlines over a full-page fill, and its text layer is a Type3"
        " font whose glyph procedures paint nothing.")
if note not in case['basis']:
    case['basis'] += note
pages = {item['page']: item for item in case['pages']}


def add(page, key, values):
    item = pages.get(page)
    if item is None:
        item = {'page': page}
        case['pages'].append(item)
        pages[page] = item
    if isinstance(values, list):
        existing = item.setdefault(key, [])
        for value in values:
            if value not in existing:
                existing.append(value)
    else:
        item[key] = values


add(2, 'paragraphs', ['nchs/fastats/obesity-overweight.htm', 'military-readiness/unfit-to-serve.html'])
add(3, 'absentWarningCodes', ['unverifiedTextLayer'])
add(3, 'minimumImages', 4)
add(3, 'headings', ['Eat the Right Amount for You', 'Prioritize Protein Foods at Every Meal', 'Consume Dairy', 'Gut Health'])
add(3, 'paragraphs', ['+ Your gut contains trillions of bacteria and other microorganisms called the microbiome.'])
add(4, 'absentWarningCodes', ['unverifiedTextLayer'])
add(4, 'minimumImages', 4)
add(4, 'paragraphs', ['+ If preferred, flavor with salt, spices, and herbs.'])
add(5, 'absentWarningCodes', ['unverifiedTextLayer'])
add(5, 'minimumImages', 2)
add(5, 'headings', ['Limit Highly Processed Foods, Added Sugars, & Refined Carbohydrates', 'Added Sugars'])
add(6, 'headings', ['Limit Alcoholic Beverages', 'Sodium'])
add(6, 'paragraphs', ['+ Consume less alcohol for better overall health.',
                      '+ Sodium and electrolytes are essential for hydration.'])
add(6, 'listItems', ['- Ages 1–3: less than 1,200 mg per day', '- Ages 9–13: less than 1,800 mg per day'])
add(8, 'headings', ['Introducing Food to Infants & Toddlers'])
add(8, 'paragraphs', ['+ Parents and caregivers can encourage healthy eating by offering new foods multiple times'])
add(8, 'listItems', ['- Swallows food instead of pushing it back out onto their chin'])

open(p, 'w').write(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
print('ok')
