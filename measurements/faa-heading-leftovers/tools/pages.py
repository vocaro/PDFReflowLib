import sys, re
# usage: pages.py dump.txt page... -> blocks of those pages (width-limited)
path = sys.argv[1]
want = set(int(p) for p in sys.argv[2:])
page = 0
for line in open(path):
    m = re.match(r'=== page (\d+)$', line.strip())
    if m:
        page = int(m.group(1))
    if page in want:
        print(str(page).rjust(4), line.rstrip()[:170])
