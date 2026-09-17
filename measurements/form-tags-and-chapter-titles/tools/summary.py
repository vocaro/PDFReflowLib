import json, collections, sys, subprocess, re
S = '/private/tmp/claude-501/-Users-trevorharmon-Development-PDFReflowLib--claude-worktrees-fable-agents-coordination-d95da7/074c2806-5fb3-4f17-8def-46d26414399e/scratchpad/w/'
base, cand = sys.argv[1], sys.argv[2]

def fallback(label):
    d = json.load(open(S + label + '.json')); w = d['warnings']
    fb = [x for x in w if x['code'] == 'structureFallback']
    by = collections.defaultdict(set)
    for x in fb: by[x['message'][:30]].add(x['page'])
    return d, w, set(x['page'] for x in fb), by

for label in (base, cand):
    d, w, pages, by = fallback(label)
    print(label, 'warnings', len(w), 'fallback pages', len(pages), {k: len(v) for k, v in by.items()},
          {k: d[k] for k in ['imageCount', 'pageCount', 'reflowedPageCount', 'recognizedPageCount']})
_, a, pa, ba = fallback(base); _, b, pb, bb = fallback(cand)
ka = collections.Counter(x['code'] for x in a); kb = collections.Counter(x['code'] for x in b)
print('warning codes changed', {k: (ka[k], kb[k]) for k in set(ka) | set(kb) if ka[k] != kb[k]})
print('fallback pages only in base', sorted(pa - pb))
print('fallback pages only in cand', sorted(pb - pa))
for k in set(ba) | set(bb):
    print('  ', k, 'base-only', sorted(ba[k] - bb.get(k, set()))[:60], 'cand-only', sorted(bb.get(k, set()) - ba[k])[:400])
na = [l.split('\t') for l in open(S + base + '.nav').read().splitlines()]
nb = [l.split('\t') for l in open(S + cand + '.nav').read().splitlines()]
print('nav', len(na), len(nb))
ha = sorted(l for l in open(S + base + '.txt') if re.match(r'h[1-6]:', l))
hb = sorted(l for l in open(S + cand + '.txt') if re.match(r'h[1-6]:', l))
print('headings lost', [x.strip() for x in (collections.Counter(ha) - collections.Counter(hb)).elements()])
print('headings gained', [x.strip() for x in (collections.Counter(hb) - collections.Counter(ha)).elements()])
print('levels', collections.Counter(x[:2] for x in ha), collections.Counter(x[:2] for x in hb))
print('images identical', open(S + base + '.img').read() == open(S + cand + '.img').read())
