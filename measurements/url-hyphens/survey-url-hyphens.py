"""Rule-exact corpus survey for #88: line-end hyphens inside web addresses.

Usage: survey-url-hyphens.py <lines-directory> [case ...]

Reads the lines-<case>.jsonl dumps written by measurements/list-marker-pieces/dump-lines.swift
(native extraction, before furniture, image, table and note handling). Breaks are found as
measurements/note-pages-and-addresses/survey-url.py finds them (its `hyphen policy` category: an
address ending in `-` before a line starting lowercase, `carried` when the address began on an
earlier line). The book evidence mirrors `LayoutReconstructor.addVocabulary` and
`addAddressVocabulary`, and each break is decided as `addressHyphenOperation` decides it:

  address   the address through the broken segment (lowercased, no scheme or `www.`) is a seen
            prefix in one form only
  segment   the broken segment is a seen segment in one form only
  word      the letters beside the hyphen, with no digit next to them, join into a book word and
            are not both book words (hyphen removed)
  none      no evidence: hyphen kept, `uncertainHyphen`

`old` is the decision of the vocabulary policy the break used before #88 (remove when the book knows
the joined letters and not the compound; warn when it knows neither).
"""
import importlib.util
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('survey_url', HERE.parent / 'note-pages-and-addresses/survey-url.py')
source = spec.loader.get_source('survey_url').replace('\nmain()\n', '\n')
survey_url = type(sys)('survey_url')
exec(compile(source, 'survey-url.py', 'exec'), survey_url.__dict__)

URL = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&()*+,;=%")
DELIMITERS = set('/.?#&=:')
SCHEME_OR_WWW = re.compile(r'^(?:[A-Za-z][A-Za-z0-9+.-]*://|www\.)', re.I)


def normalized(address):
    text = re.sub(r'^[a-z][a-z0-9+.-]*://', '', address.lower())
    return text[4:] if text.startswith('www.') else text


def trailing_address(text):
    return survey_url.address(text)


def add_vocabulary(text, words, prefixes, segments):
    for word in re.split(r'[^\w-]|[\d_]', text.lower()):
        if word:
            words.add(word)
    if '/' not in text and 'www.' not in text.lower():
        return
    tokens = text.split()
    for index, token in enumerate(tokens):
        if '/' not in token and 'www.' not in token.lower():
            continue
        run = token
        while run and run[-1] not in URL:
            run = run[:-1]
        address = trailing_address(run)
        if address is None:
            continue
        fragment = index == 0 and not SCHEME_OR_WWW.match(address)
        text_ = normalized(address).rstrip('.,;:)]')
        if index == len(tokens) - 1:
            cut = max((i for i, c in enumerate(text_) if c in DELIMITERS), default=-1)
            if cut < 0:
                continue
            text_ = text_[:cut]
        if not text_:
            continue
        prefixes.add(text_)
        start = 0
        for position, character in enumerate(text_):
            if character in DELIMITERS:
                prefixes.add(text_[:position])
                if start < position and not fragment:
                    segments.add(text_[start:position])
                fragment = False
                start = position + 1
        if start < len(text_) and not fragment:
            segments.add(text_[start:])


def letters_before(text):
    run = ''
    for character in reversed(text):
        if not character.isalpha():
            break
        run = character + run
    return run


def decide(address, right, words, prefixes, segments):
    rest = ''
    for character in right:
        if character not in URL or character in DELIMITERS:
            break
        rest += character
    removed, kept = normalized(address[:-1] + rest), normalized(address + rest)
    segment = lambda text: re.split(r'[/.?#&=:]', text)[-1]
    for level, a, b in (('address', removed in prefixes, kept in prefixes),
                        ('segment', segment(removed) in segments, segment(kept) in segments)):
        if a != b:
            return level, 'removed' if a else 'kept'
    body = address[:-1]
    prefix = letters_before(body)
    suffix = re.match(r'[^\W\d_]*', right).group(0)
    whole = not body[:len(body) - len(prefix)][-1:].isdigit() and not right[len(suffix):len(suffix) + 1].isdigit()
    if whole and prefix and suffix and (prefix + suffix).lower() in words and \
            not (prefix.lower() in words and suffix.lower() in words):
        return 'word', 'removed'
    return 'none', 'kept+warn'


def old_policy(address, right, words):
    prefix = letters_before(address[:-1]).lower()
    suffix = re.match(r'[^\W\d_]*', right).group(0).lower()
    joined, compound = prefix + suffix, prefix + '-' + suffix
    if joined in words and compound not in words:
        return 'removed'
    return 'kept' if compound in words else 'kept+warn'


def main():
    directory = Path(sys.argv[1])
    cases = sys.argv[2:] or sorted(p.stem[len('lines-'):] for p in directory.glob('lines-*.jsonl'))
    for case in cases:
        pages = [json.loads(raw) for raw in open(directory / f'lines-{case}.jsonl')]
        words, prefixes, segments = set(), set(), set()
        for page in pages:
            for line in page['lines']:
                add_vocabulary(line['t'], words, prefixes, segments)
        hits = []
        for page in pages:
            lines = page['lines']
            size = survey_url.body(lines)
            following = {id(l): survey_url.next_line(l, lines, size) for l in lines}
            carried = {}
            for line in sorted(lines, key=lambda l: -l['y']):
                text, after = line['t'].rstrip(), following.get(id(line))
                if not text or after is None or not after['t'].strip():
                    continue
                parts = text.split()
                word, mark = parts[-1], ''
                if len(parts) == 1 and id(line) in carried:
                    word, mark = carried[id(line)] + word, ' carried'
                address = survey_url.address(word)
                if address is None:
                    continue
                right = after['t'].lstrip()
                category, joins = survey_url.classify(address, right)
                if joins:
                    carried[id(after)] = address
                if category == 'hyphen policy':
                    level, outcome = decide(address, right, words, prefixes, segments)
                    hits.append((page['page'], mark, level, outcome, old_policy(address, right, words),
                                 f'{address[-60:]} || {right[:45]}'))
        print(f'### {case}: {len(hits)} URL-internal hyphen breaks')
        for page, mark, level, outcome, old, detail in hits:
            print(f'  p{page}{mark} [{level}] {outcome} (old {old}): {detail}')


main()
