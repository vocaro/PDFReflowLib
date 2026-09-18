import re
p = 'corpus/regressions.json'
s = open(p, encoding='utf-8').read()
table = {'ﬀ': 'ff', 'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬃ': 'ffi', 'ﬄ': 'ffl', 'ﬅ': 'ſt', 'ﬆ': 'st'}
n = len(re.findall('[ﬀ-ﬆ]', s))
s = re.sub('[ﬀ-ﬆ]', lambda m: table[m.group(0)], s)
open(p, 'w', encoding='utf-8').write(s)
print('respelled', n)
