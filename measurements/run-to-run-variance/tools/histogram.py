import re, sys
rows = []
for line in open(sys.argv[1]):
    m = re.search(r'^(\d+)\t.*?rows=(\d+) unc=(\d+) ink=(\d+) uink=(\d+) f=([\d.]+) loss=(\w+)', line)
    if m:
        rows.append((int(m[1]), int(m[2]), int(m[3]), float(m[6]), m[7] == 'true'))
loss = [r for r in rows if r[4]]
print('pages', len(rows), 'loss', len(loss))
near_f = [r for r in rows if abs(r[3] - 0.2) <= 0.03 and r[2] >= 8]
near_rows = [r for r in rows if r[2] in (7, 8, 9) and r[3] >= 0.2]
print('within 0.03 of the fraction threshold (and enough rows):', [(r[0], round(r[3], 4), r[2]) for r in near_f])
print('within one row of the row threshold (and over the fraction):', [(r[0], r[2], round(r[3], 4)) for r in near_rows])
print('closest fractions to 0.2 among pages with >= 8 uncovered rows:',
      sorted(((round(abs(r[3] - 0.2), 4), r[0], round(r[3], 4)) for r in rows if r[2] >= 8))[:8])
print('uncovered rows of retried pages:', sorted(r[2] for r in loss)[:10], '...')
