#!/usr/bin/env python3
"""usage: fusions.py <lines.tsv|text> [list-class]  counts punctuation-capital runs with no space
(`casualties.The`) in survey-lines column 3 (or plain text), classified like the #128 rule's exclusions."""
import re, sys
from collections import Counter
RUN = re.compile(r'(\S*?)([.,;:?!][”’)\]]*)([A-Z“‘])(\S?)')
counts, rows = Counter(), []
for line in open(sys.argv[1], encoding='utf-8'):
    f = line.rstrip('\n').split('\t')
    text = f[-1]
    for m in RUN.finditer(text):
        # word before, from the last space
        start = text.rfind(' ', 0, m.start(2)) + 1
        word = text[start:m.end(2)]
        punct = m.group(2)
        body = text[start:m.start(2)]
        right, nxt = m.group(3), m.group(4)
        if re.search(r'[/@=\\]|www', body, re.I): c = 'address'
        elif right not in '“‘' and nxt == '.': c = 'initial'
        elif punct[0] == '.' and body.endswith('.'): c = 'ellipsis'
        elif body[-1:] == '’' or (len(punct) > 1 and not punct[0] in '.,;:?!'): c = 'apostrophe'
        elif punct == '’' or body == '': c = 'other'
        elif punct[0] == '.' and body.isdigit() and start == 0: c = 'number-at-line-start'
        elif not re.search(r'[A-Za-z0-9)\]”’]$', body): c = 'other'
        else: c = 'sentence'
        counts[c] += 1
        if len(sys.argv) > 2 and sys.argv[2] == c:
            rows.append((f[0] if len(f) >= 3 else '', text[max(0, start - 30):m.end() + 25]))
print(dict(sorted(counts.items())))
for r in rows: print('\t'.join(r))
