#!/usr/bin/env python3
"""Classify the `<pre>` blocks surveyed by `survey_pre_blocks.py` (issue #29).

Two passes. The first reads each block on its own: its marker shape, the run of sibling
markers it belongs to (the library's own rule — same kind, same punctuation, a value one or
two away, adjacent in the spine, same page or the next), and content shapes such as a
bibliographic year, a hearing citation, a coded weather report or an elision.

The second pass reads the page. A reference list or an endnote apparatus wraps its entries,
and a wrapped line becomes a `<pre>` block of its own, sometimes with a false marker (an
author initial reads as `J.`). So a page whose marked blocks are mostly bibliography is a
bibliography page, and its unmarked and falsely marked blocks are continuations of it. The
same holds for Warren's endnotes and for Wallace's answer keys.

Classification is a measurement aid, not converter behaviour. A block no rule reaches is
reported as `unclassified` rather than forced into a class.
"""

import argparse
import collections
import json
import re

BULLET_CHARS = '•*−●▪–-'
MARKER = re.compile(r'^(?:[0-9]{1,9}|[A-Za-z])([.)])(?=\s)')
TIGHT_ANSWER = re.compile(r'^([0-9]{1,9})\)−')
REFERENCE = re.compile(r'\b(1[89]|20)\d\d[a-z]?[:,.]\s|https?://|doi\.org/|\bRFC\s\d|\bpp\.\s'
                       r'|\bEds\.|\bVol\.\s|\bJournal\b|\bUniversity Press\b|\baccessed\b')
AUTHORS = re.compile(r'^[0-9]{1,4}\.\s+[A-Z][A-Za-z’\'-]+,\s+[A-Z]\.')
INITIALS = re.compile(r'^[A-Z]\.[A-Z]?\.?\s')
ENDNOTE = re.compile(r'\b\d+\s+H\s?\d|\bCE\s|\bCE\.|\bIbid\b|\bId\.\s+at\b|\bsupra\b|\binfra\b'
                     r'|\bDE\s\d|\bapp\.\s|\bch\.\s|\bp{1,2}\.\s?\d', re.I)
CODED = re.compile(r'^(METAR|SPECI|TAF|UA/|UUA/|PIREP)\b')
CONTENTS = re.compile(r'\.\s?\.\s?\.\s?\.|\s\d{1,4}$')
TESTIMONY = re.compile(r'^[QA]\.\s')
ELISION = re.compile(r'^\*\s*\*\s*\*\s*$|^\*\s*\*\s*\*\s')
NOTE_STAR = re.compile(r'^\*\s')
WORD = re.compile(r'[A-Za-z]{3,}')

ORDERED = {'numbered-list-item', 'lettered-sub-item', 'exercise-item', 'bibliography-entry',
           'endnote-entry', 'answer-key-entry', 'questionnaire-item'}


def shape_of(block):
    if TIGHT_ANSWER.match(block['lines'][0] if block['lines'] else ''):
        return 'digit)'
    if block['bullet']:
        return 'bullet'
    if block['marker']:
        return block['marker'][0] + block['marker'][1]
    return 'unmarked'


def value_of(block):
    text = block['lines'][0] if block['lines'] else ''
    tight = TIGHT_ANSWER.match(text)
    if tight:
        return ('digit', ')', int(tight.group(1)))
    return tuple(block['marker']) if block['marker'] else None


def sibling(a, b):
    return bool(a) and bool(b) and a[0] == b[0] and a[1] == b[1] and 1 <= abs(a[2] - b[2]) <= 2


def mark_runs(blocks):
    identifier, previous = 0, None
    for block in blocks:
        block['shape'] = shape_of(block)
        block['value'] = value_of(block)
        joins = (previous is not None and block['page'] is not None
                 and previous['page'] is not None
                 and 0 <= block['page'] - previous['page'] <= 1
                 and block['ordinal'] == previous['ordinal'] + 1
                 and (block['bullet'] and previous['bullet'] == block['bullet']
                      or sibling(previous['value'], block['value'])))
        if not joins:
            identifier += 1
        block['run'] = identifier
        previous = block
    sizes = collections.Counter(b['run'] for b in blocks)
    for block in blocks:
        block['runSize'] = sizes[block['run']]


def prose(text):
    return sum(len(w) for w in WORD.findall(text)) / max(len(text), 1)


def first_pass(case, block):
    text = ' '.join(' '.join(block['lines']).split())
    shape = block['shape']
    if CODED.match(text) or (block['lineCount'] > 3 and shape == 'unmarked'):
        return 'coded-report'
    if ELISION.match(text):
        return 'elision'
    if case == 'gpo-warren-1964' and TESTIMONY.match(text):
        return 'testimony-turn'
    if shape == 'bullet' and NOTE_STAR.match(text) and prose(text) > 0.4 and block['runSize'] == 1:
        return 'note-asterisk'
    if case == 'wallace-algebra-2010':
        if shape in ('digit)', 'digit.', 'lower.', 'lower)'):
            # The book's answers section runs from page 438 (physical) to the end; before it
            # the same marker shapes are the exercises themselves.
            return 'answer-key-entry' if block['page'] >= 438 else 'exercise-item'
        if block['bullet'] == '•':
            return 'bulleted-list-item'
        # A row opening with a minus is a wrapped line of a displayed derivation, not a bullet.
        return 'display-math-row'
    if AUTHORS.match(text) and (REFERENCE.search(text) or case == 'noaa-nca5-2023'):
        return 'bibliography-entry'
    if case in ('noaa-nca5-2023', 'arxiv-replay-clocks-2023') and shape.startswith('digit') \
            and REFERENCE.search(text):
        return 'bibliography-entry'
    # A wrapped reference line often opens with an author initial, which reads as a marker.
    if case == 'noaa-nca5-2023' and shape in ('upper.', 'lower.') and INITIALS.match(text):
        return 'entry-continuation'
    if case == 'gpo-warren-1964' and shape == 'digit.' and ENDNOTE.search(text):
        return 'endnote-entry'
    if case == 'cia-blue-book-14-1955' and prose(text) < 0.35:
        return 'ocr-debris'
    if prose(text) < 0.3 and shape != 'unmarked':
        return 'ocr-debris'
    if shape == 'unmarked':
        return 'unmarked-preformatted'
    if case in ('nbs-jres-geltman-1977', 'ntrs-20200002975-gwl-2020') and shape == 'digit.':
        return 'contents-or-section-title'
    if case == 'gpo-911-2004' and CONTENTS.search(text) and shape == 'digit.' and block['page'] <= 12:
        return 'contents-or-section-title'
    if case == 'uscourts-pro-se-1-2016':
        return 'form-section-title'
    if block['runSize'] == 1:
        return 'singleton-marked-line'
    if shape == 'bullet':
        return 'bulleted-list-item'
    if shape in ('lower.', 'lower)', 'upper.', 'upper)'):
        return 'lettered-sub-item'
    return 'numbered-list-item'


def second_pass(case, blocks):
    """Attribute a page's stragglers to the apparatus that dominates it."""
    by_page = collections.defaultdict(list)
    for block in blocks:
        by_page[block['page']].append(block)
    strays = {'singleton-marked-line', 'unmarked-preformatted', 'ocr-debris',
              'numbered-list-item', 'lettered-sub-item', 'note-asterisk'}
    for page, items in by_page.items():
        counts = collections.Counter(b['class'] for b in items)
        for apparatus in ('bibliography-entry', 'endnote-entry'):
            if counts[apparatus] >= max(3, len(items) * 0.4):
                for block in items:
                    if block['class'] in strays:
                        text = ' '.join(' '.join(block['lines']).split())
                        opens = bool(re.match(r'^[0-9]{1,4}[.)]\s', text))
                        block['class'] = apparatus if opens else 'entry-continuation'
    # CIA: a questionnaire page carries numbered questions and lettered options together.
    if case == 'cia-blue-book-14-1955':
        for page, items in by_page.items():
            marked = [b for b in items if b['class'] in
                      ('numbered-list-item', 'lettered-sub-item', 'singleton-marked-line')]
            prosy = [b for b in marked if prose(' '.join(b['lines'])) >= 0.45]
            if len(prosy) >= 2 and len(prosy) >= len(marked) * 0.5:
                for block in prosy:
                    block['class'] = 'questionnaire-item'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('surveys', nargs='+')
    parser.add_argument('--samples', type=int, default=0)
    parser.add_argument('--json', help='write the per-class totals here')
    arguments = parser.parse_args()
    totals = collections.Counter()
    by_case = collections.defaultdict(collections.Counter)
    pages = collections.defaultdict(lambda: collections.defaultdict(set))
    samples = collections.defaultdict(list)
    for path in arguments.surveys:
        data = json.load(open(path))
        case, blocks = data['case'], data['blocks']
        mark_runs(blocks)
        for block in blocks:
            block['class'] = first_pass(case, block)
        second_pass(case, blocks)
        for block in blocks:
            name = block['class']
            totals[name] += 1
            by_case[case][name] += 1
            pages[name][case].add(block['page'])
            if len(samples[(case, name)]) < arguments.samples:
                samples[(case, name)].append(block)
        json.dump({'case': case, 'blocks': blocks}, open(path, 'w'))
    print(f'{"class":28s} {"blocks":>7s}  books (pages)')
    for name, count in totals.most_common():
        spread = ', '.join(f'{c} {by_case[c][name]}/{len(p)}p'
                           for c, p in sorted(pages[name].items(), key=lambda i: -len(i[1])))
        print(f'{name:28s} {count:7d}  {spread}')
    print(f'{"TOTAL":28s} {sum(totals.values()):7d}')
    if arguments.json:
        json.dump({'totals': totals,
                   'byCase': {c: dict(v) for c, v in by_case.items()},
                   'pages': {n: {c: sorted(p) for c, p in v.items()} for n, v in pages.items()}},
                  open(arguments.json, 'w'), indent=1)
    for (case, name), items in sorted(samples.items()):
        print(f'\n--- {case} / {name}')
        for block in items:
            print(f"  p{block['page']} run={block['runSize']}  "
                  + ' \\n '.join(block['lines'])[:150])


if __name__ == '__main__':
    main()
