#!/usr/bin/env python3
"""usage: classify.py <base.epub> <cand.epub> [--show N] [--pages] [--emphasis]

Sorts the pages two conversions differ on (#133), using the comparison tool's own page parser and
identifier normalization:

- `merge-only`: the baseline's markup with adjacent same-style elements joined
  (`</strong><strong>`, `</em></strong><strong><em>`, ...) equals the candidate's;
- `emphasis-only`: the markup is equal once every `<strong>` and `<em>` tag is removed, and no other
  page field changed;
- `structural`: anything else, printed as a compact diff of block elements with those tags removed.

`--emphasis` prints, for each emphasis-only page, the text newly set in `<em>` or `<strong>`.
"""
import difflib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from compare_conversion_runs import Evaluation  # noqa: E402

STYLE = re.compile(r'</?(?:strong|em)>')
INLINE = r'(?:strong|em|sup|sub)'
BOUNDARY = re.compile(rf'((?:</{INLINE}>)+)((?:<{INLINE}>)+)')
BLOCK = re.compile(r'(<(?:p|h[1-6]|li|ul|ol|table|tr|td|th|caption|figure|figcaption|aside|div|blockquote|pre)\b[^>]*>)')
ID = re.compile(r'\s(id|href)="[^"]*"')


def joined(markup):
    """Removes a run of closing inline tags followed by the same tags reopened in nesting order."""
    def replace(match):
        closing = re.findall(r'</(\w+)>', match.group(1))
        opening = re.findall(r'<(\w+)>', match.group(2))
        return '' if closing == list(reversed(opening)) else match.group(0)
    previous = None
    while previous != markup:
        previous, markup = markup, BOUNDARY.sub(replace, markup)
    return markup


def compact(markup):
    text = ID.sub('', STYLE.sub('', markup))
    lines = [line.strip() for line in BLOCK.sub(r'\n\1', text).split('\n')]
    return [re.sub(r'\s+', ' ', line) for line in lines if line]


def styled_spans(markup, tag):
    return re.findall(rf'<{tag}>(.*?)</{tag}>', joined(markup))


def main():
    base, cand = Path(sys.argv[1]), Path(sys.argv[2])
    show = int(sys.argv[sys.argv.index('--show') + 1]) if '--show' in sys.argv else 40
    left, right = Evaluation(base, {}), Evaluation(cand, {})
    merge, emphasis, structural = [], [], []
    for number in sorted(left.pages.keys() | right.pages.keys()):
        a, b = left.pages.get(number, {}), right.pages.get(number, {})
        if a == b:
            continue
        other = sorted(k for k in a.keys() | b.keys() if k != 'markup' and a.get(k) != b.get(k))
        if not other and joined(a.get('markup', '')) == b.get('markup', ''):
            merge.append(number)
        elif not other and STYLE.sub('', a.get('markup', '')) == STYLE.sub('', b.get('markup', '')):
            emphasis.append(number)
        else:
            structural.append((number, other))
    print(f'merge-only pages ({len(merge)}): {" ".join(map(str, merge))}')
    print(f'emphasis-only pages ({len(emphasis)}): {" ".join(map(str, emphasis))}')
    print(f'structural pages ({len(structural)}): {" ".join(str(n) for n, _ in structural)}')
    if '--emphasis' in sys.argv:
        for number in emphasis:
            a, b = left.pages[number]['markup'], right.pages[number]['markup']
            for tag in ('em', 'strong'):
                old = styled_spans(a, tag)
                new = [span for span in styled_spans(b, tag)]
                added = [re.sub(r'<[^>]+>', '', s) for s in new if s not in old]
                removed = [re.sub(r'<[^>]+>', '', s) for s in old if s not in new]
                if added or removed:
                    print(f'  p{number} {tag}: +{added[:12]} -{removed[:6]}')
    for number, other in structural:
        print(f'\n=== page {number} (other fields: {", ".join(other) or "none"})')
        diff = difflib.unified_diff(compact(left.pages.get(number, {}).get('markup', '')),
                                    compact(right.pages.get(number, {}).get('markup', '')), lineterm='', n=1)
        for index, line in enumerate(list(diff)[2:]):
            if index >= show:
                print('   …')
                break
            print('  ' + line[:300])


if __name__ == '__main__':
    main()
