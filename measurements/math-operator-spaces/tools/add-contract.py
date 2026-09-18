#!/usr/bin/env python3
"""usage: add-contract.py

Adds #188's reviewed page entries to corpus/regressions.json in page order, refusing a page the case
already has (one entry per page). Phrases were read from the candidate EPUB and each fused form from
the baseline EPUB; see the record's contract section.
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
ENTRIES = {
    "wallace-algebra-2010": [
        {"page": 7,
         "text": ["− 5 + ( − 3) Same sign, add 5 + 3, keep the negative",
                  "Diﬀerent signs, subtract 7 − 2, use sign from bigger number, negative"],
         "absentText": ["5+ (− 3)", "add 5+ 3", "subtract 7− 2", "Diﬀ erent"]},
        {"page": 8,
         "text": ["4 + ( − 3) Diﬀerent signs, subtract 4 − 3, use sign from bigger number, positive",
                  "9 − ( − 4) Add the opposite of − 4 9 + 4 Same sign, add 9 + 4, keep the positive"],
         "absentText": ["4+(− 3)", "subtract 4− 3", "opposite of− 4", "9 +4", "Diﬀ erent"]},
    ],
    "arxiv-replay-clocks-2023": [
        # The page's subfigure captions (`𝑛 = 32`, and caption (e)'s closed `𝑛= 64`) are inside the
        # preserved figure region, so only the prose reaches the EPUB text; the Swift fixture test
        # `replayCaptionsSpaceTheirRelationsAndKeepTheOneTheAuthorsSetClosed` covers the captions.
        {"page": 7,
         "paragraphs": ["in the simulation to ensure that if E = 1𝑚𝑠 then the worst-case clock skew is indeed 1𝑚𝑠."],
         "absentText": ["if E= 1𝑚𝑠"]},
    ],
}

path = os.path.join(ROOT, "corpus/regressions.json")
data = json.load(open(path, encoding="utf-8"))
for case in data["cases"]:
    for entry in ENTRIES.get(case["id"], []):
        if any(p["page"] == entry["page"] for p in case["pages"]):
            raise SystemExit(f"{case['id']} already has page {entry['page']}")
        index = next((k for k, p in enumerate(case["pages"]) if p["page"] > entry["page"]), len(case["pages"]))
        case["pages"].insert(index, entry)
        print(f"{case['id']}: page {entry['page']} added at position {index}")
with open(path, "w", encoding="utf-8") as out:
    json.dump(data, out, ensure_ascii=False, indent=2)
    out.write("\n")
