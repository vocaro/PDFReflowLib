"""Static count of contract checks, mirroring check_corpus_content.assess. usage: countchecks.py <regressions.json>"""
import json
import sys

LISTS = ['text', 'absentText', 'headings', 'absentHeadings', 'paragraphs', 'listItems', 'preformattedLines', 'notes',
         'distinctParagraphs', 'noteLinks', 'continuedParagraphs', 'continuedListItems', 'separateParagraphs',
         'orderedText', 'scripts', 'imageRegions', 'glyphRegions', 'imageAppearance', 'tableCells']
SCALARS = ['minimumImages', 'maximumImages', 'warningCodesAnyOf', 'absentWarningCodes']
d = json.load(open(sys.argv[1]))
cases = d['cases'] if isinstance(d, dict) else d
total = pages = documents = 0
per = {}
for case in cases:
    items = case.get('pages', [])
    if not items:
        continue
    documents += 1
    pages += len(items)
    n = sum(len(item.get(k, [])) for item in items for k in LISTS) + sum(1 for item in items for k in SCALARS if k in item)
    per[case['id']] = n
    total += n
print(total, 'checks on', pages, 'pages of', documents, 'documents')
print(per)
