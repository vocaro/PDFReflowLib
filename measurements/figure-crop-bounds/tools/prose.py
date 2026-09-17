"""Split figure-crop misses into prose-like lines (body size, near a column measure) and labels."""
import collections
import json
import sys

recs = [r for r in json.load(open(sys.argv[1])) if r['cause'] == 'figure-crop']
full = len(sys.argv) > 2


def prose_like(r):
    return 9.5 <= r['size'] <= 11.5 and r['rect'][2] >= 120 and len(r['text'].split()) >= 5


prose = [r for r in recs if prose_like(r)]
bypage = collections.defaultdict(list)
for r in prose:
    bypage[r['page']].append(r)
print(len(prose), 'prose-like lines on', len(bypage), 'pages;', sum(len(r['text'].split()) for r in prose), 'words')
for p, rs in sorted(bypage.items()):
    print(f"p{p} n={len(rs)} words={sum(len(r['text'].split()) for r in rs)} crop={rs[0]['crop']}")
    for r in rs if full else rs[:3]:
        print('   ', r['rect'], r['size'], r['text'][:80])
other = [r for r in recs if not prose_like(r)]
print('non-prose', len(other), 'lines', sum(len(r['text'].split()) for r in other), 'words; pages', len({r['page'] for r in other}))
