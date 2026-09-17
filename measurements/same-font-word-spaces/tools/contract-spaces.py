#!/usr/bin/env python3
"""usage: contract-spaces.py <case-id> <base.epub> <cand.epub> [--write]

For every phrase in corpus/regressions.json's contract for <case-id> (page `text`, `orderedText`,
`paragraphs`, `notes`, `headings`, `listItems`, and the phrases of `noteLinks`, `continuedParagraphs`,
`separateParagraphs` and `distinctParagraphs`), reports a phrase the candidate EPUB no longer carries on
its page (or the next page, or in any note) but carries with spaces inserted, and only inserted spaces.
A rewrite is proposed only when the baseline EPUB carries the old phrase and not the new one, so the
updated check fails on the baseline (negative control). With --write the contract is rewritten in place
(indent 2, UTF-8), which leaves every other byte unchanged.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from check_corpus_content import normalized, read_pages  # noqa: E402

case_id, base_path, cand_path = sys.argv[1], sys.argv[2], sys.argv[3]
write = "--write" in sys.argv[4:]
contract_path = ROOT / "corpus" / "regressions.json"
contract = json.loads(contract_path.read_text(encoding="utf-8"))
case = next(c for c in contract["cases"] if c["id"] == case_id)


def haystacks(pages, number, notes_only=False):
    if notes_only:
        # A note link's phrase is matched against note anchor text alone, on the note's page when
        # the link names one (`number` is then that page).
        return [anchor["text"] for n, page in pages.items() for anchor in page.get("anchors", {}).values()
                if isinstance(anchor, dict) and "text" in anchor and (number is None or n == number)]
    texts = []
    for n in (number, number + 1):
        page = pages.get(n, {})
        texts.append(page.get("text", ""))
        texts += page.get("paragraphs", []) + page.get("notes", []) + page.get("headings", []) + page.get("listItems", [])
    for page in pages.values():
        texts += page.get("notes", [])
        texts += [anchor["text"] for anchor in page.get("anchors", {}).values() if isinstance(anchor, dict) and "text" in anchor]
    return texts


base_pages, _ = read_pages(base_path)
cand_pages, _ = read_pages(cand_path)
changes, unresolved = [], []


def check(number, phrase, notes_only=False):
    wanted = normalized(phrase)
    cand = haystacks(cand_pages, number, notes_only)
    if any(wanted in text for text in cand):
        return phrase
    # The phrase with an optional space wherever it has none between two characters.
    pattern = re.compile("".join(re.escape(c) + ("" if c == " " or i + 1 == len(wanted) or wanted[i + 1] == " " else " ?")
                                 for i, c in enumerate(wanted)))
    found = {m.group(0) for text in cand for m in pattern.finditer(text)}
    base = haystacks(base_pages, number, notes_only)
    if len(found) == 1:
        new = found.pop()
        if any(wanted in text for text in base) and not any(new in text for text in base):
            changes.append((number, phrase, new))
            return new
    unresolved.append((number, phrase, sorted(found)))
    return phrase


for item in case["pages"]:
    number = item["page"]
    for key in ("text", "orderedText", "paragraphs", "notes", "headings", "listItems"):
        if key in item:
            item[key] = [check(number, p) for p in item[key]]
    for key, fields in (("noteLinks", ("before", "note")), ("continuedParagraphs", ("end", "next")),
                        ("separateParagraphs", ("end", "next")), ("distinctParagraphs", ("first", "second"))):
        for entry in item.get(key, []):
            for field in fields:
                if (key, field) == ("noteLinks", "note"):
                    entry[field] = check(entry.get("notePage"), entry[field], notes_only=True)
                else:
                    entry[field] = check(number, entry[field])
for number, old, new in changes:
    print(f"page {number}\n  - {old}\n  + {new}")
for number, old, found in unresolved:
    print(f"UNRESOLVED page {number}: {old!r} candidates={found}")
print(len(changes), "changes", len(unresolved), "unresolved")
if write and not unresolved:
    contract_path.write_text(json.dumps(contract, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("written")
