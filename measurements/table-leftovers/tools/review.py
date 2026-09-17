#!/usr/bin/env python3
"""usage: review.py base.epub cand.epub page [page...]

For each page, whether the candidate's full markup equals the baseline's once the intended #124
rewrites are undone: a section row's `<th colspan="N" scope="rowgroup">…</th>` back to
`<td colspan="N">…</td>`, the `<tbody>` each section opens merged back into one, and a row header
after a row's first cell (Table A's liabilities labels) back to `<td>`. Prints the rowgroup headers,
row headers, tbody elements and tables per page, and the first remaining difference when the
markup is not otherwise equal."""
import re
import sys
from pathlib import Path

source = Path(__file__).with_name('pagediff.py').read_text()
# pagediff.py runs its diff at import; reuse only its page splitter.
namespace = {}
exec(source.split('\nbase, cand = ')[0], namespace)
pages = namespace['pages']


def undo(markup):
    markup = re.sub(r'<th colspan="(\d+)" scope="rowgroup">(.*?)</th>', r'<td colspan="\1">\2</td>', markup)
    markup = re.sub(r'</tbody>\n?<tbody>', '', markup)

    def row(match):
        cells = re.findall(r'<t[hd]\b[^>]*>.*?</t[hd]>', match.group(1))
        rest = [re.sub(r'^<th scope="row">(.*)</th>$', r'<td>\1</td>', cell) for cell in cells[1:]]
        return '<tr>' + ''.join(cells[:1] + rest) + '</tr>'
    return re.sub(r'<tr>(.*?)</tr>', row, markup)


base, cand = pages(sys.argv[1]), pages(sys.argv[2])
for page in map(int, sys.argv[3:]):
    a, b = base.get(page, ''), cand.get(page, '')
    restored = undo(b)
    same = restored.replace('\n', '') == a.replace('\n', '')
    print(f'page {page}: rowgroup headers {b.count("scope=" + chr(34) + "rowgroup")} (base {a.count("scope=" + chr(34) + "rowgroup")}), '
          f'row headers {b.count("scope=" + chr(34) + "row" + chr(34))} (base {a.count("scope=" + chr(34) + "row" + chr(34))}), '
          f'tbody {b.count("<tbody>")} (base {a.count("<tbody>")}), tables {b.count("<table>")} (base {a.count("<table>")}), '
          f'equal after undoing #124 rewrites: {same}')
    if not same:
        x, y = a.replace('\n', ''), restored.replace('\n', '')
        i = next((k for k in range(min(len(x), len(y))) if x[k] != y[k]), min(len(x), len(y)))
        print('   base:', x[max(0, i - 120):i + 200])
        print('   cand:', y[max(0, i - 120):i + 200])
