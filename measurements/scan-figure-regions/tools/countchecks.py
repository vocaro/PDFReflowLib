import json, subprocess, sys
W = '/Users/trevorharmon/Development/PDFReflowLib/.claude/worktrees/agent-a11a7ffaa3ea102c4'
sys.path.insert(0, W + '/tools')
from check_corpus_content import assess

def totals(doc):
    checks = pages = 0
    for contract in doc['cases']:
        numbers = [p['page'] for p in contract['pages']]
        case = {'id': contract['id'], 'sha256': contract['sourceSHA256'], 'bytes': 1, 'pages': max(numbers)}
        result = {'case': case, 'runPassed': True, 'conversionExitCode': 0}
        empty = {n: {'text': '', 'images': []} for n in numbers}
        try:
            out = assess(case, contract, result, {'pageCount': max(numbers)}, empty, numbers,
                         image_data=lambda _: b'', reference_root=W)
            checks += out['contentChecks']
        except Exception as error:
            print('could not count', contract['id'], error)
            continue
        pages += len(set(numbers))
    return checks, pages

old = json.loads(subprocess.run(['git', '-C', W, 'show', 'bfe0476:corpus/regressions.json'], capture_output=True, text=True).stdout)
new = json.load(open(W + '/corpus/regressions.json'))
print('bfe0476', totals(old))
print('working tree', totals(new))
