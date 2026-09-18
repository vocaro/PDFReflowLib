#!/usr/bin/env python3
"""usage: respace-contract.py <case-id> <candidate-epub> [--write]

For a case's reviewed contract, finds every phrase the candidate EPUB no longer holds as written but
holds with only its whitespace changed, and prints the candidate's spelling beside the old one:
`text`, `orderedText` (page text), `paragraphs`, `listItems`, `distinctParagraphs` (paragraphs) and the
`before`/`after` context of `scripts`. A phrase whose non-whitespace characters the candidate does
not hold, or holds with more than one spelling, is reported and left alone. Every `absentText` phrase
is rewritten with the same substitutions its page's positive phrases received and kept beside the
old spelling, so an order guard such as `7) (b +8)(b + 4) 17)` still guards in the new spacing.
With --write, corpus/regressions.json is rewritten in place (json.dumps, indent 2, as stored).
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from check_corpus_content import normalized, read_pages  # noqa: E402


def spellings(phrase, haystack, anchor=None):
    """The spellings in `haystack` of `phrase` with its whitespace ignored (anchor: 'start'/'end')."""
    target = re.sub(r"\s+", "", phrase)
    if not target:
        return set()
    stripped, index = [], []
    for k, ch in enumerate(haystack):
        if not ch.isspace():
            stripped.append(ch); index.append(k)
    stripped = "".join(stripped)
    found, start = set(), 0
    while True:
        at = stripped.find(target, start)
        if at < 0:
            break
        if anchor == "start" and at != 0 or anchor == "end" and at + len(target) != len(stripped):
            start = at + 1; continue
        found.add(normalized(haystack[index[at]:index[at + len(target) - 1] + 1]))
        start = at + 1
    return found


def respell(phrase, haystacks, anchor=None):
    if any(normalized(phrase) in h for h in haystacks) and anchor is None:
        return phrase, None
    options = set()
    for h in haystacks:
        options |= spellings(phrase, h, anchor)
    if len(options) == 1:
        return options.pop(), None
    return phrase, ("absent" if not options else f"ambiguous {sorted(options)}")


def main():
    case_id, epub = sys.argv[1], sys.argv[2]
    path = os.path.join(ROOT, "corpus/regressions.json")
    data = json.load(open(path, encoding="utf-8"))
    contract = next(c for c in data["cases"] if c["id"] == case_id)
    pages, _ = read_pages(epub)
    changes, problems = 0, []
    for item in contract["pages"]:
        page = pages.get(item["page"], {"text": ""})
        substitutions = {}

        def update(value, haystacks, where, anchor=None):
            nonlocal changes
            new, problem = respell(value, haystacks, anchor)
            if problem:
                if not any(normalized(value) in h for h in haystacks):
                    problems.append(f"page {item['page']} {where}: {value!r}: {problem}")
                return value
            if new != value:
                changes += 1
                substitutions[value] = new
                print(f"page {item['page']} {where}: {value!r} -> {new!r}")
            return new

        for key in ("text", "orderedText"):
            if key in item:
                item[key] = [update(v, [page["text"]], key) for v in item[key]]
        if "paragraphs" in item:
            item["paragraphs"] = [update(v, page.get("paragraphs", []), "paragraphs") for v in item["paragraphs"]]
        if "listItems" in item:
            item["listItems"] = [update(v, page.get("listItems", []), "listItems") for v in item["listItems"]]
        for pair in item.get("distinctParagraphs", []):
            for k in ("first", "second"):
                pair[k] = update(pair[k], list(page.get("paragraphIDs", {}).values()), f"distinct.{k}")
        for script in item.get("scripts", []):
            spans = [s for s in page.get("scripts", []) if s["tag"] == script["tag"] and s["text"] == normalized(script["text"])]
            script["before"] = update(script["before"], [s["before"] for s in spans], "script.before", "end")
            script["after"] = update(script["after"], [s["after"] for s in spans], "script.after", "start")
        if "absentText" in item and substitutions:
            extended = []
            for phrase in item["absentText"]:
                extended.append(phrase)
                new = phrase
                for old, replacement in sorted(substitutions.items(), key=lambda kv: -len(kv[0])):
                    new = new.replace(old, replacement)
                if new != phrase and new not in item["absentText"] and new not in extended:
                    extended.append(new)
                    print(f"page {item['page']} absentText: + {new!r} (beside {phrase!r})")
                    if normalized(new) in page["text"]:
                        problems.append(f"page {item['page']} absentText {new!r} is present in the candidate")
            item["absentText"] = extended
    print(f"{changes} phrases respelled")
    for p in problems:
        print("PROBLEM", p)
    if "--write" in sys.argv:
        with open(path, "w", encoding="utf-8") as out:
            json.dump(data, out, ensure_ascii=False, indent=2)
            out.write("\n")


if __name__ == "__main__":
    main()
