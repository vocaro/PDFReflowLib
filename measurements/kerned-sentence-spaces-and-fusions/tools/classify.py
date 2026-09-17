import sys, re
from collections import Counter, defaultdict
STOP = set("mr mrs ms dr gen col lt sgt adm capt cmdr maj rep reps sen gov pres rev st jr sr inc corp co ltd no nos vol vols vs cf ed eds fig jan feb mar apr jun jul aug sep sept oct nov dec dept univ ft mt pp pt ch sec art ibid etc al approx est govt amb gens cong".split())
rows = [l.rstrip('\n').split('\t') for l in open(sys.argv[1], encoding='utf-8')]
cats = defaultdict(list)
for r in rows:
    page, kind, left, right, prod, gap, lw, rw, ctx = r
    L, R = ctx.split('|', 1)
    nxt = R[1:2]
    word = re.sub(r'^[“‘(\[]+', '', lw)
    core = word.rstrip('.,;:?!”’)')
    if left == '’' and not re.search(r'[.,;:?!]’$', lw): c = 'x-apostrophe'
    elif nxt == '.' : c = 'x-initial-right'
    elif '/' in lw or 'www' in lw or '.php' in lw or '.asp' in lw: c = 'x-url'
    elif left in '.' and re.search(r'\.\.$', word): c = 'x-ellipsis'
    elif left == '.' and len(core) == 1: c = 'x-one-letter'
    elif left == '.' and '.' in core: c = 'x-internal-period'
    elif left == '.' and core.lower() in STOP: c = 'x-stoplist'
    elif left == '.' and core.isdigit(): c = 'x-digits'
    elif left == '.' and not re.search(r'[a-z]', core) : c = 'caps-period'
    else: c = 'insert-' + left
    cats[c].append(r)
for c in sorted(cats):
    words = Counter(r[6] for r in cats[c])
    print(f'{c}\t{len(cats[c])}\t' + ', '.join(f'{w} {n}' for w, n in words.most_common(40)))
