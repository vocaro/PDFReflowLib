#!/usr/bin/env python3
"""Labels each probed page with what its own text layer says the readings left out (#240).

`probe-ocr-coverage-signals.swift` writes one JSON object per page and, with PROBE_TEXT, each
reading's transcription beside it. This reads both, extracts the page's own text layer with
`pdftotext`, and compares the layer with each reading as a multiset of alphanumeric tokens.

Recall against the layer is the ground truth the coverage rule is judged against: a rule is not
justified by how many pages it flags but by whether the pages it flags are the ones whose reading
is missing the page's words. Precision shows whether a banded reading gained its words by
repeating itself rather than by reading more.

A layer is evidence, not truth: a page of mathematics or a damaged encoding depresses both
readings' recall alike, which is why the claims rest on the *difference* between the two readings
of the same page rather than on either number alone.

    label_pages.py <signals.jsonl> <text-directory> <source.pdf> <out.json>
"""
import collections
import json
import re
import subprocess
import sys
from pathlib import Path


def tokens(text):
    return collections.Counter(re.findall(r'[a-z0-9]+', text.lower()))


def main():
    signals, texts, source, out = (Path(a) for a in sys.argv[1:5])
    labelled = []
    for line in signals.open():
        record = json.loads(line)
        page = record['page']
        layer = tokens(subprocess.run(['pdftotext', '-f', str(page), '-l', str(page), str(source), '-'],
                                      capture_output=True, text=True).stdout)
        record['layerTokens'] = sum(layer.values())
        for reading in ('first', 'banded'):
            path = texts / f'p{page}-{reading}.txt'
            if not path.exists():
                continue
            read = tokens(path.read_text(errors='ignore'))
            shared = sum((read & layer).values())
            record[f'{reading}Recall'] = shared / max(1, sum(layer.values()))
            record[f'{reading}Precision'] = shared / max(1, sum(read.values()))
        labelled.append(record)
    out.write_text(json.dumps(labelled))
    print(f'{len(labelled)} pages labelled from {signals.name}')


if __name__ == '__main__':
    main()
