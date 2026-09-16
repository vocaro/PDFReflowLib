"""Experiment: per-page text plausibility statistics over PDFKit dumps.

Signals measured per page:
  words      alphabetic tokens (>= 2 letters, lowercase)
  stop       fraction of words in a small English function-word list
  rare       fraction of within-word letter bigrams outside the top-K English bigrams
  fonts      count of simple fonts on the page with unmappable Differences names and no ToUnicode
"""
import json, re, sys, collections, glob, os

STOP = set("""the of and to in a is that for it as was with be by on not he this are or his from at which but
have an had they you were their one all we can her has there been if more when will would who so no
this than into them its two out then up also only new some could time these first any may its these
other such each about how because between under over after before both those most than while where
than through many during three now must does do did being made make used use using data page
table figure section number see chapter part per within without same different against however
should very much still even here just like than every another might well since both same great
little our own way too""".split())

# Bigram table derived from /usr/share/dict/words (type frequencies); top-K set below.
def build_bigrams():
    counts = collections.Counter()
    with open('/usr/share/dict/words') as f:
        for w in f:
            w = w.strip().lower()
            if not w.isalpha() or not w.isascii(): continue
            for a, b in zip(w, w[1:]): counts[a + b] += 1
    return counts

TOKEN = re.compile(r"[^\W\d_]+")

def page_stats(text, common):
    words = [w.lower() for w in TOKEN.findall(text) if len(w) >= 2]
    n = len(words)
    stop = sum(1 for w in words if w in STOP) / n if n else 0
    bigrams = [w[i:i+2] for w in words for i in range(len(w) - 1) if w.isascii()]
    rare = sum(1 for b in bigrams if b not in common) / len(bigrams) if bigrams else 0
    return n, stop, rare, len(bigrams)

UNMAPPABLE = re.compile(r"^(?:[A-Za-z]{1,2}\d+|glyph\d+|index\d+|cid\d+)$")

def font_evidence(fonts):
    bad = 0
    for f in fonts:
        if f['hasToUnicode'] or f['descendantHasToUnicode']: continue
        if f['subtype'] not in ('Type1', 'TrueType', 'Type3', 'MMType1'): continue
        if f['differencesCount'] == 0: continue
        names = f['differencesSample']
        if names and sum(1 for nme in names if UNMAPPABLE.match(nme) and not nme.startswith('uni')) >= max(1, len(names) // 2):
            bad += 1
    return bad

def main():
    counts = build_bigrams()
    total = sum(counts.values())
    ranked = counts.most_common()
    K = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    common = set(b for b, _ in ranked[:K])
    covered = sum(c for _, c in ranked[:K]) / total
    print(f"top-{K} bigrams cover {covered:.4f} of dictionary bigram occurrences")
    rows = []
    D = os.path.dirname(os.path.abspath(__file__))
    for path in sorted(glob.glob(os.path.join(D, '*.json'))):
        d = json.load(open(path))
        for p in d['pages']:
            n, stop, rare, nb = page_stats(p['text'], common)
            rows.append((d['file'], p['number'], n, stop, rare, font_evidence(p['fonts']), p['largestGraphicFraction']))
    json.dump(rows, open(os.path.join(D, 'scores.json'), 'w'))
    # Report distribution per document for pages with >= 30 words
    by_doc = collections.defaultdict(list)
    for r in rows: by_doc[r[0]].append(r)
    for doc, rs in by_doc.items():
        big = [r for r in rs if r[2] >= 30]
        if not big: print(doc, 'no pages with >=30 words'); continue
        stops = sorted(r[3] for r in big); rares = sorted(r[4] for r in big)
        fonts = sum(1 for r in rs if r[5])
        print(f"{doc:55s} pages={len(rs):4d} >=30w={len(big):4d} stop min={stops[0]:.3f} p5={stops[len(stops)//20]:.3f} med={stops[len(stops)//2]:.3f}"
              f" | rare max={rares[-1]:.3f} p95={rares[len(rares)*95//100]:.3f} med={rares[len(rares)//2]:.3f} | fontEvidencePages={fonts}")
    print("\nLowest-stop pages (>=30 words):")
    for r in sorted((r for r in rows if r[2] >= 30), key=lambda r: r[3])[:40]:
        print(f"  {r[0][:40]:40s} p{r[1]:4d} words={r[2]:4d} stop={r[3]:.3f} rare={r[4]:.3f} fonts={r[5]} graphic={r[6]:.2f}")
    print("\nHighest-rare pages (>=30 words):")
    for r in sorted((r for r in rows if r[2] >= 30), key=lambda r: -r[4])[:40]:
        print(f"  {r[0][:40]:40s} p{r[1]:4d} words={r[2]:4d} stop={r[3]:.3f} rare={r[4]:.3f} fonts={r[5]} graphic={r[6]:.2f}")

main()
