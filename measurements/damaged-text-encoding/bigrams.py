"""Derive the embedded common-bigram list: the 300 most frequent within-word letter pairs by
type frequency over the ASCII alphabetic entries of /usr/share/dict/words (macOS web2)."""
import collections
counts = collections.Counter()
n = 0
with open('/usr/share/dict/words') as f:
    for w in f:
        w = w.strip().lower()
        if not w.isalpha() or not w.isascii(): continue
        n += 1
        for a, b in zip(w, w[1:]): counts[a + b] += 1
ranked = counts.most_common(300)
total = sum(counts.values())
print('words', n, 'coverage', round(sum(c for _, c in ranked) / total, 4))
s = ''.join(b for b, _ in ranked)
print(len(s))
for i in range(0, 600, 100): print('"' + s[i:i+100] + '"')
