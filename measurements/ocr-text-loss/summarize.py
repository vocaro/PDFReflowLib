#!/usr/bin/env python3
"""Summarizes one or more `probe-ocr-text-loss.swift` JSONL files (#116).

For each file: how many pages the first recognition left text-shaped ink uncovered, what the
band retry recovered, and what the check and the retry cost in time.

Usage: summarize.py [--json] <label>=<file.jsonl> ...
"""
import json
import sys


def load(path):
    with open(path) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def summary(label, rows):
    flagged = [r for r in rows if r['indicatesLoss']]
    retried = [r for r in flagged if r['retried']]
    still = [r for r in rows if r.get('finalUncoveredFraction') is not None]
    recognize = sum(r['firstSeconds'] for r in rows)
    measure = sum(r['measureSeconds'] for r in rows)
    # `completeSeconds` repeats the first measurement, so the retry's own cost is what it adds.
    retry = sum(r['completeSeconds'] for r in rows) - measure
    return {
        'label': label,
        'pages': len(rows),
        'flaggedPages': len(flagged),
        'flaggedPageNumbers': [r['page'] for r in flagged],
        'retryKeptPages': len(retried),
        'retryKeptPageNumbers': [r['page'] for r in retried],
        'stillIncompletePages': len(still),
        'stillIncompletePageNumbers': [r['page'] for r in still],
        'wordsBefore': sum(r['firstWords'] for r in rows),
        'wordsAfter': sum(r['finalWords'] for r in rows),
        'wordsRecoveredOnRetriedPages': sum(r['finalWords'] - r['firstWords'] for r in retried),
        'linesRecoveredOnRetriedPages': sum(r['finalLines'] - r['firstLines'] for r in retried),
        'maxUncoveredRowsOnCleanPage': max((r['uncoveredRows'] for r in rows if not r['indicatesLoss']), default=0),
        'maxUncoveredFractionOnCleanPage': round(
            max((r['uncoveredFraction'] for r in rows if not r['indicatesLoss']), default=0.0), 3),
        'uncoveredFractionOnFlaggedPages': [round(r['uncoveredFraction'], 3) for r in flagged],
        'uncoveredFractionAfterRetry': [round(r['finalUncoveredShare'], 3) for r in flagged],
        'uncoveredRowsAfterRetry': [r['finalUncoveredRows'] for r in flagged],
        'recognitionSeconds': round(recognize, 1),
        'coverageCheckSeconds': round(measure, 1),
        'coverageCheckMillisecondsPerPage': round(1000 * measure / max(1, len(rows)), 1),
        'retrySeconds': round(retry, 1),
        'retryCostShareOfRecognition': round(retry / recognize, 3) if recognize else 0.0,
    }


def main():
    arguments = sys.argv[1:]
    as_json = '--json' in arguments
    results = []
    for argument in arguments:
        if argument == '--json':
            continue
        label, _, path = argument.partition('=')
        results.append(summary(label, load(path)))
    if as_json:
        print(json.dumps(results, indent=1))
        return
    for result in results:
        print(f"{result['label']}: {result['pages']} pages, {result['flaggedPages']} flagged, "
              f"{result['retryKeptPages']} retries kept, {result['stillIncompletePages']} still incomplete; "
              f"words {result['wordsBefore']} -> {result['wordsAfter']}; "
              f"check {result['coverageCheckMillisecondsPerPage']} ms/page, "
              f"retry +{result['retryCostShareOfRecognition']:.0%} of recognition time")
        if result['flaggedPageNumbers']:
            print('  flagged pages:', result['flaggedPageNumbers'])
        if result['retryKeptPageNumbers']:
            print('  retry kept on:', result['retryKeptPageNumbers'])
        if result['stillIncompletePageNumbers']:
            print('  still incomplete:', result['stillIncompletePageNumbers'])
        print(f"  cleanest-page ceiling: {result['maxUncoveredRowsOnCleanPage']} uncovered rows, "
              f"{result['maxUncoveredFractionOnCleanPage']} uncovered share")


if __name__ == '__main__':
    main()
