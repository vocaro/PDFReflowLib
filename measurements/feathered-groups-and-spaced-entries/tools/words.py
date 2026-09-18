import sys, re

# usage: words.py <blocks-dump>: per changed page, reflowed words and images, base -> cand.
text = open(sys.argv[1], encoding='utf-8').read()
base, cand = text.split('######## cand\n')
base = base.split('######## base\n', 1)[1]
def pages(s):
    out = {}
    for chunk in s.split('==== page ')[1:]:
        number, _, rest = chunk.partition('\n')
        lines = rest.splitlines()
        words = sum(len(l.split(':', 1)[1].split()) for l in lines if not l.strip().startswith('[img]') and ':' in l)
        images = sum(1 for l in lines if l.strip().startswith('[img]'))
        paras = sum(1 for l in lines if l.strip().startswith('p:'))
        out[int(number)] = (words, images, paras)
    return out
b, c = pages(base), pages(cand)
tb = tc = 0
for p in sorted(set(b) | set(c)):
    x, y = b.get(p, (0, 0, 0)), c.get(p, (0, 0, 0))
    if x != y:
        flag = '  <-- fewer words' if y[0] < x[0] else ''
        print(f'{p:5} words {x[0]:4} -> {y[0]:4}  images {x[1]} -> {y[1]}  paragraphs {x[2]:3} -> {y[2]:3}{flag}')
    tb += x[0]; tc += y[0]
print('total words', tb, '->', tc)
