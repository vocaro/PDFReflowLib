#!/usr/bin/env python3
"""Per-chapter note counts, linked notes and unlinked notes (no body reference) in a 9/11 EPUB."""
import sys, re, glob, html, json
from collections import defaultdict

root = sys.argv[1]
files = sorted(glob.glob(root + '/EPUB/chapter-*.xhtml'), key=lambda p: int(re.search(r'chapter-(\d+)', p).group(1)))
src = '\n'.join(re.search(r'<body[^>]*>(.*)</body>', open(f, encoding='utf-8').read(), re.S).group(1) for f in files)

page = 0
notes = defaultdict(dict)        # chapter -> number -> (page, linked, text)
markers = defaultdict(list)      # chapter -> [(number, page)] linked noterefs
plain_sups = []                  # (page, digits) unlinked sup digit runs in body
chapter = 0
expected = None
ids = set(re.findall(r'id="note-c(\d+)-(\d+)"', src))
for line in src.split('\n'):
    breaks = [int(x) for x in re.findall(r'id="page-(\d+)"', line)]
    start_page = breaks[0] if breaks and line.lstrip().startswith('<span epub:type="pagebreak"') else page
    if breaks:
        page = breaks[-1]
    if start_page >= 469:
        body = re.sub(r'<span epub:type="pagebreak"[^>]*/>', '', line)
        m = re.match(r'\s*<p(?: id="note-c(\d+)-(\d+)")?[^>]*>(?:<a [^>]*>)?\s*([1-9][0-9]{0,2})\.', body)
        if m:
            n = int(m.group(3))
            if m.group(1):
                chapter = int(m.group(1))
            elif n == 1:
                chapter += 1
            if expected is None or n == expected or n == 1 or m.group(1):
                notes[chapter][n] = (start_page, bool(m.group(1)), html.unescape(re.sub(r'<[^>]+>', '', body))[:80])
                expected = n + 1
    else:
        for c, n in re.findall(r'href="[^"]*#note-c(\d+)-(\d+)"', line):
            markers[int(c)].append(int(n))
        for d in re.findall(r'<sup>\s*([0-9]{1,3})\s*</sup>', line):
            plain_sups.append((start_page, d))

rows = []
for c in sorted(notes):
    nums = notes[c]
    top = max(nums)
    missing_seq = [n for n in range(1, top + 1) if n not in nums]
    linked = sorted(set(markers[c]))
    unlinked = [n for n in range(1, top + 1) if n not in set(linked)]
    rows.append(dict(chapter=c, notes=top, parsed=len(nums), gaps=missing_seq, markers=len(markers[c]),
                     linkedNotes=len(linked), unlinkedNotes=unlinked))
    print('chapter %2d notes %3d parsed %3d markers %3d linkedNotes %3d unlinked %3d gaps %s' %
          (c, top, len(nums), len(markers[c]), len(linked), len(unlinked), missing_seq[:10]))
print('plain body sup digit runs:', len(plain_sups))
print('total markers', sum(r['markers'] for r in rows), 'notes', sum(r['notes'] for r in rows),
      'unlinked notes', sum(len(r['unlinkedNotes']) for r in rows))
json.dump(rows, open(sys.argv[2], 'w'), indent=1)
