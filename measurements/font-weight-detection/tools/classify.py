#!/usr/bin/env python3
"""usage: classify.py <base.epub> <cand.epub> [--show N]

Sorts the pages two conversions differ on into emphasis-only (the markup is equal once every
`<strong>` tag is removed and adjacent text rejoined) and structural (anything else), using the
comparison tool's own page parser and identifier normalization. Structural pages print a compact
diff of their block elements with `<strong>` removed, so a heading or paragraph change is visible.
"""
import difflib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from compare_conversion_runs import Evaluation  # noqa: E402

STRONG = re.compile(r'</?strong>')
# Block-level tags that start a new line of the compact rendering.
BLOCK = re.compile(r'(<(?:p|h[1-6]|li|ul|ol|table|tr|td|th|caption|figure|figcaption|aside|div|blockquote|pre)\b[^>]*>)')
ID = re.compile(r'\s(id|href)="[^"]*"')


def compact(markup):
    text = ID.sub('', STRONG.sub('', markup))
    lines = [line.strip() for line in BLOCK.sub(r'\n\1', text).split('\n')]
    return [re.sub(r'\s+', ' ', line) for line in lines if line]


def main():
    base, cand = Path(sys.argv[1]), Path(sys.argv[2])
    show = int(sys.argv[sys.argv.index('--show') + 1]) if '--show' in sys.argv else 40
    left, right = Evaluation(base, {}), Evaluation(cand, {})
    emphasis, structural = [], []
    for number in sorted(left.pages.keys() | right.pages.keys()):
        a, b = left.pages.get(number, {}), right.pages.get(number, {})
        if a == b:
            continue
        other = sorted(k for k in a.keys() | b.keys() if k != 'markup' and a.get(k) != b.get(k))
        if not other and STRONG.sub('', a.get('markup', '')) == STRONG.sub('', b.get('markup', '')):
            emphasis.append(number)
        else:
            structural.append((number, other))
    print(f'emphasis-only pages ({len(emphasis)}): {" ".join(map(str, emphasis))}')
    print(f'structural pages ({len(structural)}): {" ".join(str(n) for n, _ in structural)}')
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
