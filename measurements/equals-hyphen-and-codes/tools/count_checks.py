"""Contract totals by type, counted as tools/check_corpus_content.py counts them (one per list entry,
one per minimumImages/maximumImages/warningCodesAnyOf/absentWarningCodes key)."""
import json, sys, collections

path = sys.argv[1]
data = json.load(open(path))
lists = {
    'orderedText': 'ordered-text', 'text': 'text', 'paragraphs': 'paragraph', 'absentText': 'absent-text',
    'headings': 'heading', 'absentHeadings': 'absent-heading', 'listItems': 'list-item',
    'preformattedLines': 'preformatted-lines', 'scripts': 'script', 'notes': 'footnote', 'noteLinks': 'note-link',
    'continuedParagraphs': 'paragraph-continuation', 'continuedListItems': 'list-item-continuation',
    'separateParagraphs': 'paragraph-separation', 'distinctParagraphs': 'distinct-paragraph',
    'imageRegions': 'source-region', 'glyphRegions': 'glyph-structure', 'imageAppearance': 'image-appearance',
    'tableCells': 'table-cell',
}
singles = {'minimumImages': 'image-presence', 'maximumImages': 'image-presence',
           'warningCodesAnyOf': 'warning', 'absentWarningCodes': 'absent-warning'}
counts = collections.Counter()
pages = 0
per_case = {}
for case in data['cases']:
    n = 0
    for item in case['pages']:
        pages += 1
        for key, name in lists.items():
            k = len(item.get(key, []))
            counts[name] += k
            n += k
        for key, name in singles.items():
            if key in item:
                counts[name] += 1
                n += 1
    per_case[case['id']] = n
order = ['ordered-text', 'text', 'paragraph', 'absent-text', 'heading', 'absent-heading', 'list-item',
         'preformatted-lines', 'script', 'footnote', 'note-link', 'paragraph-continuation', 'list-item-continuation',
         'paragraph-separation', 'distinct-paragraph', 'image-presence', 'warning', 'absent-warning',
         'source-region', 'glyph-structure', 'image-appearance', 'table-cell']
assert set(counts) <= set(order), set(counts) - set(order)
print('documents', len(data['cases']), 'pages', pages, 'checks', sum(counts.values()))
print(', '.join(f'{counts[k]} {k}' for k in order))
print(per_case)
