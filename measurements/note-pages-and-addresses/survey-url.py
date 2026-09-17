"""Rule-exact corpus survey for #79: lines broken inside a web address.

Usage: survey-url.py <lines-directory> [case ...]

Reads the lines-<case>.jsonl dumps written by measurements/list-marker-pieces/dump-lines.swift
(native extraction with style, as the pipeline extracts; the survey runs before furniture, image,
table and note handling, so its counts are upper bounds). The next line of a line is the nearest
line below it in the same column at ordinary spacing, as survey-markers.py's slash survey chooses
it. A line's address is the run of URL characters (letters, digits and `-._~:/?#[]@!$&()*+,;=%`)
that ends its last word, so an attached dash or quote is not part of it (`(NACO)—www.faa.`), without
leading `( [ < : ; ,`, extended back through the line above when that line joined this one with no
space and this line is a single word (marked `carried`; carried hits in NOAA's reference lists are
mostly entry numbers from the neighbouring column, a survey artifact). The run is an address when it
holds a dot and has a scheme (`https://`), starts with `www.`, or opens with a domain and a slash
(`ffiec.gov/`), as `LayoutReconstructor.trailingAddress` decides.

Each break inside an address is classified as `LayoutReconstructor.addressContinues` treats it:
  join %             no space: the address ends in a percent escape (`%`, `%2`, `%20`) and the next
                     line starts with a letter, digit or `%`
  join <c>           no space: the address ends in `_ = & ? # ~` after a letter or digit and the next
                     line starts with a letter or digit
  join .             no space: `.` after a letter or digit, and the next line starts lowercase, or
                     with a digit in a word that is not a bare number (`2022.2061405`, never `45.`)
  join -             no space, hyphen kept: `-` before a digit or capital letter
  join before <c>    no space: the address ends in a letter or digit and the next line starts with
                     `/ . _ ? # = & % ~` followed by a letter or digit
  hyphen policy      ends in `-` and the next line starts lowercase: unchanged vocabulary policy
  space              any other break inside an address (a `.` before a capital or a bare number, or
                     after a closing parenthesis)
  unmarked           ends in a letter or digit and the next word continues the address without a
                     URL character at the break (not joined; reported only)
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

OPEN = '(“"[<‘\''
ADDRESS = re.compile(r'^(?:[A-Za-z][A-Za-z0-9+.-]*://|www\.|[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/)', re.I)
URL_CHARS = re.compile(r"^[A-Za-z0-9\-._~:/?#\[\]@!$&()*+,;=%]+$")
INTERNAL = '_=&?#%~'
BEFORE = '/._?#=&%~'
CONTINUES = re.compile(r'[/=]|\.(?:s?html?|pdf|aspx?|cfm|php\d?|jsp|txt)\b', re.I)


def body(lines):
    weights = Counter()
    for line in lines:
        weights[round(line['s'])] += len(line['t'])
    return max(4, weights.most_common(1)[0][0]) if weights else 12


def next_line(line, lines, size):
    below = [o for o in lines if o['y'] < line['y'] and line['y'] - (o['y'] + o['h']) < size * 0.9
             and abs(o['x'] - line['x']) < size * 3]
    return max(below, key=lambda o: o['y']) if below else None


TRAILING = re.compile(r"[A-Za-z0-9\-._~:/?#\[\]@!$&()*+,;=%]*$")


def address(word):
    # The run of URL characters ending the word (after a dash or quote attached to it), without
    # leading opening punctuation.
    word = TRAILING.search(word).group(0).lstrip('([<:;,')
    return word if len(word) >= 2 and '.' in word and ADDRESS.match(word) else None


def classify(word, right):
    """(category, joins) for a break after address `word` before line text `right`."""
    last, before = word[-1], word[-2] if len(word) > 1 else ''
    first = right[0]
    second = right[1] if len(right) > 1 else ''
    if re.search(r'%[0-9A-Fa-f]{0,2}$', word):
        return ('join %', True) if (first.isascii() and first.isalnum()) or first == '%' else ('space', False)
    if last in INTERNAL and before.isalnum() and first.isalnum():
        return f'join {last}', True
    if last == '.' and before.isalnum() and first.isascii():
        head = right.split()[0].rstrip('.,;:)]')
        if first.islower() or (first.isdigit() and not head.isdigit()):
            return 'join .', True
        return 'space', False
    if last == '-':
        if first.isdigit() or first.isupper():
            return 'join -', True
        if first.islower():
            return 'hyphen policy', False
    if last == '/':
        return None, before.isalnum() or before == '/'  # #70's rule, not counted here
    if last.isalnum() and first in BEFORE and second.isalnum():
        return f'join before {first}', True
    if last in INTERNAL + '.-':
        return 'space', False
    if last.isalnum() and CONTINUES.search(right.split()[0]):
        return 'unmarked', False
    return None, False


def survey(lines):
    size = body(lines)
    following = {}
    for line in lines:
        n = next_line(line, lines, size)
        if n is not None:
            following[id(line)] = n
    carried = {}
    hits = []
    for line in sorted(lines, key=lambda l: -l['y']):
        text = line['t'].rstrip()
        n = following.get(id(line))
        if not text or n is None or not n['t'].strip():
            continue
        words = text.split()
        word, mark = words[-1], ''
        if len(words) == 1 and id(line) in carried:
            word, mark = carried[id(line)] + word, ' carried'
        word = address(word)
        if word is None:
            continue
        right = n['t'].lstrip()
        category, joins = classify(word, right)
        if joins:
            carried[id(n)] = word
        if category:
            hits.append((category + mark, f"{text[-50:]!r} || {right[:40]!r}"))
    return hits


def main():
    directory = Path(sys.argv[1])
    cases = sys.argv[2:] or sorted(p.stem[len('lines-'):] for p in directory.glob('lines-*.jsonl'))
    for case in cases:
        hits = []
        for raw in open(directory / f'lines-{case}.jsonl'):
            page = json.loads(raw)
            hits += [(page['page'], k, d) for k, d in survey(page['lines'])]
        kinds = Counter(k for _, k, _ in hits)
        print(f"### {case}: {len(hits)} on {len({p for p, _, _ in hits})} pages; {dict(sorted(kinds.items()))}")
        for page, k, detail in hits:
            print(f'  p{page} [{k}]: {detail}')


main()
