"""summarize.py <before.tsv> <after.tsv> [image-backed pages]: census tables before/after."""
import collections, csv, sys

def load(p):
    return {int(r['page']): r for r in csv.DictReader(open(p), delimiter='\t')}

def table(rows):
    pages = collections.Counter(); groups = collections.Counter(); gpages = collections.Counter()
    for r in rows.values():
        if r['validates'] == 'false': pages['tree validation (ParentTree owner check)'] += 1; continue
        if r['applies'].startswith('notAttempted'): pages[r['applies']] += 1; continue
        if r['pageReason'] != '-': pages['page invalid: ' + r['pageReason']] += 1; continue
        pages['all groups apply' if r['applies'] == 'all' else 'some groups rejected'] += 1
        for kv in (r['groupReasons'].split(',') if r['groupReasons'] != '-' else []):
            k, v = kv.split('='); groups[k] += int(v); gpages[k] += 1
    total_groups = sum(int(r['groups']) for r in rows.values())
    tagged = sum(int(r['taggedLines']) for r in rows.values()); lines = sum(int(r['lines']) for r in rows.values())
    return pages, groups, gpages, total_groups, tagged, lines

b, a = load(sys.argv[1]), load(sys.argv[2])
for name, rows in (('before', b), ('after', a)):
    pages, groups, gpages, tg, tagged, lines = table(rows)
    print(f'== {name}: {len(rows)} tagged pages, {tg} groups, {tagged}/{lines} lines tagged')
    for k, v in pages.most_common(): print(f'   pages  {k}: {v}')
    for k, v in groups.most_common(): print(f'   groups {k}: {v} groups on {gpages[k]} pages')
changed = [n for n in a if a[n]['taggedLines'] != b[n]['taggedLines']]
print('pages whose tagged-line count changed:', len(changed))
zero_before = [n for n in b if b[n]['taggedLines'] == '0']
print('zero-tagged pages before', len(zero_before), 'after', len([n for n in a if a[n]['taggedLines'] == '0']))
if len(sys.argv) > 3:
    for n in map(int, sys.argv[3].split(',')):
        print(f'   page {n}: {b[n]["pageReason"]} {b[n]["taggedLines"]}/{b[n]["lines"]} -> {a[n]["pageReason"]} {a[n]["applies"]} {a[n]["taggedLines"]}/{a[n]["lines"]} {a[n]["groupReasons"]}')
