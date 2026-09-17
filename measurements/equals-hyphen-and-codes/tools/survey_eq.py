import json, sys, glob, os, re, collections

here = os.path.dirname(os.path.abspath(__file__))
detail = sys.argv[1] if len(sys.argv) > 1 else None
for path in sorted(glob.glob(os.path.join(here, "lines", "*.jsonl"))):
    doc = os.path.basename(path)[:-6]
    c = collections.Counter()
    examples = collections.defaultdict(list)
    for raw in open(path):
        page = json.loads(raw)
        lines = page["lines"]
        for i, line in enumerate(lines):
            t = line["t"].rstrip()
            if "=" in t: c["lines with ="] += 1
            if t.endswith("-") and len(t) > 1 and t[-2].isalpha(): c["letter- end"] += 1
            if not t.endswith("="): continue
            c["= end"] += 1
            nxt = lines[i + 1]["t"].lstrip() if i + 1 < len(lines) else ""
            before = t[-2] if len(t) > 1 else ""
            kind = ("letter" if before.isalpha() else "space" if before == " " else "digit" if before.isdigit() else "other:" + before)
            opens = ("lower" if nxt[:1].islower() else "upper" if nxt[:1].isupper() else "digit" if nxt[:1].isdigit() else "other")
            inner = t[:-1].count("=")
            key = f"before={kind} next={opens} otherEq={inner>0}"
            c[key] += 1
            examples[key].append((page["page"], t[-40:], nxt[:30], round(line["s"], 2)))
    print(f"== {doc}: " + ", ".join(f"{k}: {v}" for k, v in sorted(c.items())))
    for k, v in examples.items():
        show = v if (detail == doc or len(v) <= 6) else v[:4]
        for e in show: print("   ", k, e)
