"""Negative control for inkcheck: shrink every candidate crop by N points on each side. usage: shrink.py in out N"""
import json
import sys

n = float(sys.argv[3])
with open(sys.argv[2], 'w') as out:
    for raw in open(sys.argv[1]):
        page = json.loads(raw)
        page['crops'] = [[x + n, y + n, max(0, w - 2 * n), max(0, h - 2 * n)] for x, y, w, h in page['crops']]
        out.write(json.dumps(page) + '\n')
