#!/usr/bin/env python3
"""Per-page word recall of an EPUB against pdftotext -raw, the way issue #54 measures it.

Word multiset per page (spine split at doc-pagebreak, figcaption dropped) versus the
pdftotext -raw words of the same physical page. Also reports an order score (longest
common subsequence of the EPUB word sequence against the source sequence, over source
words) and per-page image counts.
"""
import re
import subprocess
import sys
import json
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
import check_corpus_content as ccc

WORD = re.compile(r"[0-9A-Za-zÀ-ɏ][0-9A-Za-zÀ-ɏ'’\-]*")


def words(text):
    return [w.lower() for w in WORD.findall(text.replace('­', ''))]


def source_pages(pdf, count):
    out = []
    for page in range(1, count + 1):
        text = subprocess.run(['/opt/homebrew/bin/pdftotext', '-raw', '-f', str(page), '-l', str(page), pdf, '-'],
                              capture_output=True, text=True, check=True).stdout
        out.append(words(text))
    return out


def lcs(a, b):
    if not a or not b:
        return 0
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b):
            cur.append(prev[j] + 1 if x == y else max(prev[j + 1], cur[j]))
        prev = cur
    return prev[-1]


def main():
    pdf, epub = sys.argv[1], sys.argv[2]
    pages, markers = ccc.read_pages(epub, max_entries=20000, max_uncompressed_bytes=4 * 1024 ** 3)
    count = max(pages)
    source = source_pages(pdf, count)
    total_source = total_hit = 0
    low = []
    rows = []
    for n in range(1, count + 1):
        src = source[n - 1]
        got = words(pages.get(n, {}).get('text', ''))
        sc, gc = Counter(src), Counter(got)
        hit = sum(min(c, gc[w]) for w, c in sc.items())
        total_source += len(src)
        total_hit += hit
        recall = hit / len(src) if src else 1.0
        order = lcs(got, src) / len(src) if src else 1.0
        images = len(pages.get(n, {}).get('images', []))
        rows.append({'page': n, 'source': len(src), 'epub': len(got), 'hit': hit, 'recall': round(recall, 3),
                     'order': round(order, 3), 'images': images})
        if src and (recall < 0.95 or order < 0.85):
            low.append(n)
    print(json.dumps({'sourceWords': total_source, 'epubMatchedWords': total_hit,
                      'bookRecall': round(total_hit / total_source, 4), 'lowPages': low,
                      'lowPageCount': len(low), 'pageCount': count,
                      'images': sum(r['images'] for r in rows)}))
    if len(sys.argv) > 3:
        Path(sys.argv[3]).write_text(json.dumps(rows, indent=1))


if __name__ == '__main__':
    main()
