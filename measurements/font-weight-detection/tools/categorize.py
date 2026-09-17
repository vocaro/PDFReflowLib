#!/usr/bin/env python3
"""usage: categorize.py <base.epub> <cand.epub> [--list KIND]

Categorizes every changed block run on the structural pages `classify.py` finds. Each diff hunk's
removed and added blocks (with `<strong>` removed) are compared as text:

- `heading-split`: the same text, with blocks added and at least one new heading element whose
  text opened a removed block (a subhead fused into its paragraph now stands alone);
- `paragraph-split`: the same text in more blocks, no heading added or removed;
- `heading-lost` / `heading-gained`: the same text with a heading element removed or added in
  place (retagged, not split);
- `merge`: the same text in fewer blocks;
- `other`: the text differs (reordering, a block moved across pages) or any other change.

Prints counts by kind and the pages of each; `--list KIND` prints that kind's hunks in full.
"""
import difflib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from classify import compact, STRONG  # noqa: E402
from compare_conversion_runs import Evaluation  # noqa: E402

TAGS = re.compile(r'<[^>]+>')
HEADING = re.compile(r'^<h([1-6])\b')


def text(lines):
    return re.sub(r'\s+', '', TAGS.sub('', ''.join(lines)))


def kind(removed, added):
    if text(removed) != text(added):
        return 'other'
    old_heads = [l for l in removed if HEADING.match(l)]
    new_heads = [l for l in added if HEADING.match(l)]
    if len(added) > len(removed):
        if len(new_heads) > len(old_heads):
            return 'heading-split'
        if len(new_heads) == len(old_heads):
            return 'paragraph-split'
        return 'other'
    if len(added) < len(removed):
        return 'merge'
    if len(new_heads) > len(old_heads):
        return 'heading-gained'
    if len(new_heads) < len(old_heads):
        return 'heading-lost'
    return 'retagged'


def main():
    base, cand = Path(sys.argv[1]), Path(sys.argv[2])
    listing = sys.argv[sys.argv.index('--list') + 1] if '--list' in sys.argv else None
    left, right = Evaluation(base, {}), Evaluation(cand, {})
    pages, examples = {}, {}
    for number in sorted(left.pages.keys() | right.pages.keys()):
        a = left.pages.get(number, {}).get('markup', '')
        b = right.pages.get(number, {}).get('markup', '')
        if STRONG.sub('', a) == STRONG.sub('', b):
            continue
        before, after = compact(a), compact(b)
        matcher = difflib.SequenceMatcher(a=before, b=after, autojunk=False)
        for tag, i1, i2, j1, j2 in matcher.get_opcodes():
            if tag == 'equal':
                continue
            k = kind(before[i1:i2], after[j1:j2])
            pages.setdefault(k, set()).add(number)
            examples.setdefault(k, []).append((number, before[i1:i2], after[j1:j2]))
    for k in sorted(pages):
        print(f'{k}: {len(examples[k])} hunks on {len(pages[k])} pages: {" ".join(map(str, sorted(pages[k])))}')
    if listing:
        for number, removed, added in examples.get(listing, []):
            print(f'\n=== page {number}')
            for line in removed:
                print('  - ' + line[:260])
            for line in added:
                print('  + ' + line[:260])


if __name__ == '__main__':
    main()
