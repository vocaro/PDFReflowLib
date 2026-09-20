#!/usr/bin/env python3
"""Both loss rules on the same readings (#240).

Applies #116's rule (a line box believed for its whole width) and #240's (each box cut back to
the width its own transcription can fill) to one set of `probe-ocr-coverage-signals.swift`
records, and reports what each would flag, retry and reflow. Running both over identical readings
keeps Vision's run-to-run variation (#173) out of the comparison: the two columns differ only by
the rule. [rules-compared.json](rules-compared.json) is this output over the probed corpus.

    compare_rules.py <label>=<signals.jsonl> ...
"""
import json
import sys


def summary(label, records):
    def outcome(flagged):
        # The retry is kept when the bands cover more of the page's writing and cost it no words.
        kept = [r for r in flagged
                if (r.get('banded') or {}).get('coversMore') and r['banded']['words'] >= r['firstWords']]
        words = sum(r['firstWords'] for r in records) + sum(r['banded']['words'] - r['firstWords'] for r in kept)
        return {'flagged': len(flagged), 'retried': len(kept), 'words': words}

    old = [r for r in records if r['indicatesLoss']]
    new = [r for r in records
           if r['written06UncoveredRows'] >= 8 and r['written06UncoveredFraction'] >= 0.2]
    return {'book': label, 'pages': len(records),
            'firstReadingWords': sum(r['firstWords'] for r in records),
            'boxesBelievedWhole': outcome(old), 'writtenWidth': outcome(new)}


def main():
    results = []
    for argument in sys.argv[1:]:
        label, _, path = argument.partition('=')
        results.append(summary(label, [json.loads(line) for line in open(path) if line.strip()]))
    for r in results:
        old, new = r['boxesBelievedWhole'], r['writtenWidth']
        print(f"{r['book']}: {r['pages']} pages | boxes believed whole: {old['flagged']} flagged, "
              f"{old['retried']} retried, {old['words']} words | written width: {new['flagged']} flagged, "
              f"{new['retried']} retried, {new['words']} words")
    print(json.dumps(results, indent=1, sort_keys=True))


if __name__ == '__main__':
    main()
