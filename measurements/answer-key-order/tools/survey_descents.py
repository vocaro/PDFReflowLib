#!/usr/bin/env python3
"""Pages whose key numbers, counting those under crops, step back other than to restart at 1.

Runs `survey-order` (built from `tools/survey-order.swift`) over a page range and reads the
numbers in its reading order: a text entry's own `N)`, and for a crop the numbers printed on the
lines it covers. A key read down its columns only ever rises, or restarts a new key at 1 (#185).

    python3 measurements/answer-key-order/tools/survey_descents.py <survey-order> <pdf> 438 489
"""
import re
import subprocess
import sys


def main():
    tool, pdf, first, last = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    out = subprocess.run([tool, pdf] + [str(page) for page in range(first, last + 1)],
                         capture_output=True, text=True).stdout
    bad = 0
    for block in out.split('== ')[1:]:
        lines = block.strip().split('\n')
        page = lines[0].split()[1]
        numbers = []
        for line in lines[1:]:
            match = re.match(r'\s*\d+\s+x .*?y\s+[\d.]+…\s*[\d.]+\s+(.*)', line)
            if not match:
                continue
            what = match.group(1)
            if what.startswith('"'):
                marker = re.match(r'"([0-9]{1,3})\)', what)
                if marker:
                    numbers.append(int(marker.group(1)))
            else:
                held = re.search(r'holding \[(.*)\]', what)
                if held:
                    numbers += [int(x) for x in held.group(1).split(', ')]
        descents = [(a, b) for a, b in zip(numbers, numbers[1:]) if b <= a and b != 1]
        if descents:
            bad += 1
            print(page, descents, numbers)
    print('pages with a descent not at a restart:', bad)


if __name__ == '__main__':
    main()
