#!/usr/bin/env python3
"""usage: review.py base.epub cand.epub page [page...]

For each page, whether the candidate's full markup equals the baseline's once the intended #121
rewrites are undone: `<th scope="row">…</th>` back to `<td>…</td>`, and a `<thead>` header row back
to the first `<tbody>` row of `<td>` cells. Prints the number of row-header cells, header rows and
tables per page, and the first remaining difference when the markup is not otherwise equal."""
import re
import sys
from pathlib import Path

source = Path(__file__).with_name('pagediff.py').read_text()
# pagediff.py runs its diff at import; reuse only its page splitter.
namespace = {}
exec(source.split('\nbase, cand = ')[0], namespace)
pages = namespace['pages']


def undo(markup, headers):
    markup = re.sub(r'<th scope="row">(.*?)</th>', r'<td>\1</td>', markup)
    markup = re.sub(r'<th colspan="(\d+)" scope="row">(.*?)</th>', r'<td colspan="\1">\2</td>', markup)

    def header(match):
        cells = re.sub(r'<th(\b[^>]*)>(.*?)</th>', r'<td\1>\2</td>', match.group(1))
        return '<tbody>' + cells.replace('\n', '')
    if not headers:
        return markup
    return re.sub(r'<thead>(<tr>(?:(?!</tr>).)*</tr>)\n?</thead>\n?<tbody>', header, markup, flags=re.S)


base, cand = pages(sys.argv[1]), pages(sys.argv[2])
for page in map(int, sys.argv[3:]):
    a, b = base.get(page, ''), cand.get(page, '')
    restored = undo(b, headers="<thead>" not in a)
    same = restored.replace('\n', '') == a.replace('\n', '')
    print(f'page {page}: row headers {b.count(chr(34) + "row" + chr(34))}, thead {b.count("<thead>")} (base {a.count("<thead>")}), '
          f'tables {b.count("<table>")} (base {a.count("<table>")}), equal after undoing #121 rewrites: {same}')
    if not same:
        x, y = a.replace('\n', ''), restored.replace('\n', '')
        i = next((k for k in range(min(len(x), len(y))) if x[k] != y[k]), min(len(x), len(y)))
        print('   base:', x[max(0, i - 120):i + 200])
        print('   cand:', y[max(0, i - 120):i + 200])
