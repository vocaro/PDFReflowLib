#!/usr/bin/env python3
"""Apply this change's reviewed contract edits to corpus/regressions.json (idempotent)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PATH = ROOT / 'corpus/regressions.json'

TABLE_3_1 = {
    'title': 'Table 3.1 Traditional tools in an ample-reserves regime',
    'columns': ['Tool', 'Definition', 'In practice'],
    'rows': [
        {'label': 'Interest on reserve balances (IORB)', 'values': [
            'Interest on reserve balances (IORB)',
            'Interest paid on funds that banks hold in their reserve balance accounts at their Federal Reserve Bank.',
            'Because banks are unlikely to lend funds in the federal funds market for less than they get paid in their '
            'reserve balance account at the Federal Reserve, IORB is an effective tool for guiding the federal funds rate. '
            'In fact, interest on reserve balances is the primary tool for moving the federal funds rate within the target range.']},
        {'label': 'Overnight reverse repurchase agreement (ON RRP) facility', 'values': [
            'Overnight reverse repurchase agreement (ON RRP) facility',
            'The Federal Reserve’s standing offer to many large nonbank financial institutions to deposit funds at the Fed and earn interest.',
            'Because large, nonbank financial institutions who are counterparties to the ON RRP facility are unlikely to lend '
            'funds for lower than the ON RRP offering rate, the ON RRP facility acts as a supplementary tool for moving the '
            'federal funds rate within the target range.']},
        {'label': 'Open market operations', 'values': [
            'Open market operations',
            'The Federal Reserve’s buying and selling of securities issued or guaranteed by the U.S. Treasury or U.S. government agencies.',
            'Open market operations will be used to maintain an ample supply of reserves.']},
        {'label': 'Discount window', 'values': [
            'Discount window',
            'The Federal Reserve’s lending to banks (the “discount window”) at the discount rate.',
            'Because banks are unlikely to borrow at a rate that’s higher than the discount rate, the discount window helps '
            'put a ceiling on the federal funds rate.']},
    ],
}

# Table A's two header cells each span a label column and an amount column; the checker maps one
# grid column per distinct header path, so the transcription checks the label columns (the
# amounts sit in the unlabelled columns beside them and are checked as ordered text).
TABLE_A = {
    'title': 'Table A. Simplified view of the Federal Reserve balance sheet, as of June 24, 2020',
    'columns': ['Assets (billions of dollars)', 'Liabilities (billions of dollars)'],
    'rows': [
        {'label': 'Treasury securities held outright', 'values': ['Treasury securities held outright', 'Deposits of depository institutions']},
        {'label': 'Agency debt and mortgage-backed securities holdings', 'values': ['Agency debt and mortgage-backed securities holdings', 'Federal Reserve notes in circulation']},
        {'label': 'Other assets', 'values': ['Other assets', 'Capital and other liabilities']},
        {'label': 'Total', 'values': ['Total', 'Total']},
    ],
}

EDITS = {
    'fed-explained-2021': {
        46: {'drop': ['minimumImages'], 'set': {'tableCells': [TABLE_3_1], 'maximumImages': 1}},
        47: {'set': {'tableCells': [TABLE_A], 'maximumImages': 1,
                     'orderedText': ['Treasury securities held outright 4,197 Deposits of depository institutions 2,938',
                                     'Agency debt and mortgage-backed securities holdings 1,946 Federal Reserve notes in circulation 1,915',
                                     'U.S. Treasury, General Account 1,587',
                                     'Other assets 939 Capital and other liabilities 642']}},
        32: {'set': {'maximumImages': 1}},
        64: {'set': {'maximumImages': 1}},
        120: {'set': {'maximumImages': 0}},
    },
    # The pink rule across the top margin of a continuation page, with no text near it. Page 27's
    # rules beneath its section titles stay regions (its minimumImages 3 is unchanged).
    'gpo-our-flag-2003': {
        12: {'set': {'maximumImages': 0}},
        54: {'set': {'maximumImages': 0}},
    },
}


def main():
    raw = PATH.read_text()
    data = json.loads(raw)
    for case in data['cases']:
        for number, edit in EDITS.get(case['id'], {}).items():
            entries = [entry for entry in case['pages'] if entry['page'] == number]
            if not entries:
                # Insert after the nearest earlier page without reordering existing entries.
                entry = {'page': number}
                earlier = [i for i, e in enumerate(case['pages']) if e['page'] < number]
                case['pages'].insert(earlier[-1] + 1 if earlier else 0, entry)
            else:
                entry = entries[0]
            for key in edit.get('drop', []):
                entry.pop(key, None)
            for key, value in edit.get('set', {}).items():
                if key == 'orderedText' and key in entry and entry[key] != value:
                    raise SystemExit(f'page {number} already has orderedText')
                entry[key] = value
    PATH.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    main()
