#!/usr/bin/env python3
"""usage: classify.py <base.epub> <cand.epub> [--show N] [--spans] [--pages]

Sorts the pages two conversions differ on (#142) by what changed in their inline markup, using
the comparison tool's own page parser and identifier normalization. Each page's markup is read
as a stream of characters, each carrying the set of inline elements enclosing it
(`strong`, `em`, `i`, `sup`, `sub`); every other tag stays in the stream as an opaque token, so a
block or attribute change is never mistaken for a styling change.

- `bracket-only`: the same characters carry the same styles (emphasis on a space excepted: it is
  invisible, and a joining space now takes the style around it), written with different elements
  (`<strong><em>a</em></strong><strong> b</strong>` as `<strong><em>a</em> b</strong>`, and a
  joining space taken inside the style around it);
- `math-italic`: the same as the baseline once `<i>` is dropped from the candidate, so the page
  changed only by variables gaining their slope (with or without re-bracketing);
- `structural`: anything else, printed as a compact diff.

`--spans` prints each page's added `<i>` spans and any span whose other styles changed.
"""
import difflib
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from compare_conversion_runs import Evaluation  # noqa: E402

STYLES = ('strong', 'em', 'i', 'sup', 'sub')
TOKEN = re.compile(r'<(/?)([a-zA-Z0-9:_-]+)((?:[^>"\']|"[^"]*"|\'[^\']*\')*?)(/?)>')
ID = re.compile(r'\s(id|href)="[^"]*"')
BLOCK = re.compile(r'(<(?:p|h[1-6]|li|ul|ol|table|tr|td|th|caption|figure|figcaption|aside|div|blockquote|pre)\b[^>]*>)')


def styled(markup):
    """[(character or opaque tag, frozenset of enclosing inline elements)] for one page."""
    markup, stream, stack, position = ID.sub('', markup), [], [], 0
    for match in TOKEN.finditer(markup):
        for character in markup[position:match.start()]:
            stream.append((character, frozenset(stack)))
        position = match.end()
        closing, name, empty = match.group(1), match.group(2).lower(), match.group(4)
        if name in STYLES and not empty:
            if closing:
                if stack and stack[-1] == name:
                    stack.pop()
                elif name in stack:            # malformed nesting: report it as a difference
                    stream.append(('</%s!>' % name, frozenset(stack)))
                    stack.remove(name)
            else:
                stack.append(name)
        else:
            stream.append((match.group(0), frozenset(stack)))
    for character in markup[position:]:
        stream.append((character, frozenset(stack)))
    return stream


def without(stream, tag):
    return [(value, style - {tag}) for value, style in stream]


INVISIBLE = frozenset({'strong', 'em', 'i'})


def normalized(stream):
    """Emphasis on a space is invisible, and a joining space now takes the style around it
    (#142), so a whitespace character's bold and italic elements are not a difference. A space
    moving into or out of a `<sup>` still is: raising it would move it."""
    return [(value, style - INVISIBLE if not value.startswith('<') and value.isspace() else style)
            for value, style in stream]


def spans(stream, tag):
    """The text of each maximal run enclosed by `tag`."""
    result, current = [], None
    for value, style in stream:
        if tag in style and not value.startswith('<'):
            current = (current or '') + value
        elif current is not None:
            result.append(current)
            current = None
    return result + ([current] if current is not None else [])


def compact(markup):
    text = ID.sub('', re.sub(r'</?(?:%s)>' % '|'.join(STYLES), '', markup))
    lines = [line.strip() for line in BLOCK.sub(r'\n\1', text).split('\n')]
    return [re.sub(r'\s+', ' ', line) for line in lines if line]


def main():
    base, cand = Path(sys.argv[1]), Path(sys.argv[2])
    show = int(sys.argv[sys.argv.index('--show') + 1]) if '--show' in sys.argv else 40
    left, right = Evaluation(base, {}), Evaluation(cand, {})
    bracket, maths, structural = [], [], []
    for number in sorted(left.pages.keys() | right.pages.keys()):
        a, b = left.pages.get(number, {}), right.pages.get(number, {})
        if a == b:
            continue
        other = sorted(k for k in a.keys() | b.keys() if k != 'markup' and a.get(k) != b.get(k))
        before, after = normalized(styled(a.get('markup', ''))), normalized(styled(b.get('markup', '')))
        if not other and before == after:
            bracket.append(number)
        elif not other and before == without(after, 'i') and spans(after, 'i'):
            maths.append(number)
        else:
            structural.append((number, other))
    print(f'bracket-only pages ({len(bracket)}): {" ".join(map(str, bracket))}')
    print(f'math-italic pages ({len(maths)}): {" ".join(map(str, maths))}')
    print(f'structural pages ({len(structural)}): {" ".join(str(n) for n, _ in structural)}')
    if '--spans' in sys.argv:
        for number in maths + bracket:
            after = styled(right.pages[number]['markup'])
            added = spans(after, 'i')
            if added:
                print(f'  p{number} i: {added[:14]}')
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
