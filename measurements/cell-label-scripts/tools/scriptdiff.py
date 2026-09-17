#!/usr/bin/env python3
"""usage: scriptdiff.py base.epub cand.epub [page...]  per page: sup/sub elements lost and gained, and
whether anything but script markup changed (page markup with sup/sub tags removed, compared exactly).

With no pages, every page is compared. Prints one line per lost or gained script (tag, text, the 24
characters of plain text before it) and a per-page and total count."""
import collections, html, re, sys, zipfile


def pages(path):
    z = zipfile.ZipFile(path)
    names = sorted([n for n in z.namelist() if re.search(r'chapter-\d+\.xhtml$', n)], key=lambda s: int(re.findall(r'\d+', s)[-1]))
    body = ''.join(re.sub(r'(?s).*<body>|</body>.*', '', z.read(n).decode()) for n in names)
    body = re.sub(r' id="(heading|note|noteref)-[^"]*"', '', body)
    body = re.sub(r'images/image-\d+', 'images/image-N', body)
    parts = re.split(r'<span epub:type="pagebreak"[^>]*id="page-(\d+)"[^>]*/>', body)
    return {int(parts[i]): parts[i + 1] for i in range(1, len(parts), 2)}


def scripts(markup):
    found = []
    for match in re.finditer(r'<(sup|sub)>(.*?)</\1>', markup):
        before = html.unescape(re.sub(r'<[^>]+>', '', markup[:match.start()]))[-24:]
        found.append((match.group(1), html.unescape(re.sub(r'<[^>]+>', '', match.group(2))), before))
    return found


def unscripted(markup):
    return re.sub(r'</?(sup|sub)>', '', markup)


base, cand = pages(sys.argv[1]), pages(sys.argv[2])
wanted = list(map(int, sys.argv[3:])) or sorted(set(base) | set(cand))
totals = collections.Counter()
for page in wanted:
    a, b = base.get(page, ''), cand.get(page, '')
    if a == b:
        continue
    lost = collections.Counter(scripts(a)) - collections.Counter(scripts(b))
    gained = collections.Counter(scripts(b)) - collections.Counter(scripts(a))
    other = unscripted(a) != unscripted(b)
    print(f'==== page {page}: lost {sum(lost.values())}, gained {sum(gained.values())}'
          + (', OTHER MARKUP CHANGED' if other else ''))
    for (tag, text, before), count in sorted(lost.items()):
        print(f'  - <{tag}>{text!r} after {before!r}' + (f' x{count}' if count > 1 else ''))
        totals[f'lost {tag}'] += count
    for (tag, text, before), count in sorted(gained.items()):
        print(f'  + <{tag}>{text!r} after {before!r}' + (f' x{count}' if count > 1 else ''))
        totals[f'gained {tag}'] += count
    totals['pages'] += 1
    totals['pages with other changes'] += other
print('TOTAL', dict(totals))
