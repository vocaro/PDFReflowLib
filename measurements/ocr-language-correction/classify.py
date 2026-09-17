#!/usr/bin/env python3
"""Classify every off -> on change span mechanically (#108 item 1).

usage: classify.py <changes.tsv from analyze.py> [--examples N]

Classes, first match wins:
  spacing-split / spacing-join  same characters, only whitespace differs (more / fewer tokens)
  punctuation                  same letters and digits (case-folded), only punctuation differs
  digits-lost / digits-gained  fewer / more digit characters (letters and digits traded)
  digits-changed               same count of digits, different digits
  dictionary-gain              alphabetic words: on has more dictionary words than off
  dictionary-loss              on has fewer dictionary words than off
  delete / insert              tokens removed / added (split by whether digits are involved)
  other                        a letter change that does not move the dictionary count
Dictionary: /usr/share/dict/words, case-folded, words of two or more letters.
"""
import re
import sys
from collections import Counter, defaultdict

WORDS = {w.strip().lower() for w in open('/usr/share/dict/words')}


def dict_count(text):
    return sum(w.lower() in WORDS for w in re.findall(r'[A-Za-z]{2,}', text))


def classify(op, off, on):
    digits_off, digits_on = re.findall(r'\d', off), re.findall(r'\d', on)
    if op == 'delete':
        return 'delete-numeric' if digits_off else 'delete-text'
    if op == 'insert':
        return 'insert-numeric' if digits_on else 'insert-text'
    if ''.join(off.split()) == ''.join(on.split()):
        return 'spacing-split' if len(on.split()) > len(off.split()) else 'spacing-join'
    if re.sub(r'\W', '', off).lower() == re.sub(r'\W', '', on).lower():
        return 'punctuation'
    if len(digits_on) < len(digits_off):
        return 'digits-lost'
    if len(digits_on) > len(digits_off):
        return 'digits-gained'
    if digits_on != digits_off:
        return 'digits-changed'
    gain = dict_count(on) - dict_count(off)
    if gain > 0:
        return 'dictionary-gain'
    if gain < 0:
        return 'dictionary-loss'
    return 'other'


def main():
    path = sys.argv[1]
    examples = int(sys.argv[sys.argv.index('--examples') + 1]) if '--examples' in sys.argv else 0
    counts = defaultdict(Counter)
    samples = defaultdict(list)
    for i, line in enumerate(open(path)):
        if i == 0:
            continue
        name, book, page, op, off, on, numeric, context = line.rstrip('\n').split('\t')
        c = classify(op, off, on)
        counts[(name, book)][c] += 1
        if len(samples[(book, c)]) < examples:
            samples[(book, c)].append(f'p{page}: {off!r} -> {on!r}')
    classes = sorted({c for v in counts.values() for c in v})
    print('set\tbook\ttotal\t' + '\t'.join(classes))
    for key in sorted(counts):
        v = counts[key]
        print(f'{key[0]}\t{key[1]}\t{sum(v.values())}\t' + '\t'.join(str(v[c]) for c in classes))
    for key in sorted(samples):
        print(key, samples[key])


if __name__ == '__main__':
    main()
