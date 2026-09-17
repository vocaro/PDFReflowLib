"""Adds #141's reviewed expectations to corpus/regressions.json (DGA page 2, Fed page 68)."""
import json
from collections import OrderedDict

path = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a0ba3a7886d1b0e32/corpus/regressions.json'
raw = open(path, encoding='utf-8').read()
data = json.loads(raw, object_pairs_hook=OrderedDict)
cases = {case['id']: case for case in data['cases']}

dga = cases['dga-2025-2030']
page = next(p for p in dga['pages'] if p['page'] == 2)
page['orderedText'] = (['Message from the Secretaries', 'Welcome to the Dietary Guidelines for Americans, 2025–2030.']
                       + page['orderedText']
                       + ['chronic-disease/data-research/facts-stats/index.html', 'nchs/fastats/obesity-overweight.htm',
                          'gis.cdc.gov/grasp/diabetes/diabetesatlas-spotlight.html', 'military-readiness/unfit-to-serve.html'])
page['headings'] = ['Message from the Secretaries']
page['paragraphs'] = ['Welcome to the Dietary Guidelines for Americans, 2025–2030.'] + page['paragraphs']
page['distinctParagraphs'] = page['distinctParagraphs'] + [
    {'first': 'Welcome to the Dietary Guidelines for Americans', 'second': 'These Guidelines mark the most significant reset'},
    {'first': 'chronic-disease/data-research/facts-stats/index.html', 'second': 'nchs/fastats/obesity-overweight.htm'},
    {'first': 'gis.cdc.gov/grasp/diabetes/diabetesatlas-spotlight.html', 'second': 'military-readiness/unfit-to-serve.html'},
]
dga['basis'] += (' Page 2 (#141) reviewed against the source: the header title and welcome line, set on a tab and a band'
                 ' across the lower edge of the header photograph, reflow as a heading and a paragraph after the'
                 ' photograph, which keeps its own crop above the tab; the four footnotes, set two to a column and'
                 ' numbered down each column, read 1, 2, 3, 4, each its own paragraph.')

fed = cases['fed-explained-2021']
assert not any(p['page'] == 68 for p in fed['pages'])
fed['pages'].append(OrderedDict([
    ('page', 68),
    ('distinctParagraphs', [{'first': 'Foreign banking organizations primarily operate in the U.S.',
                             'second': 'Edge Act and agreement corporations are subsidiaries of banks'}]),
]))
fed['basis'] += (' Page 68 (#141) reviewed against the source: Figure 5.2\'s notes 1 and 2, set on consecutive lines'
                 ' below the chart, are two paragraphs.')

indent = 2
open(path, 'w', encoding='utf-8').write(json.dumps(data, indent=indent, ensure_ascii=False) + '\n')
