"""Offline issue #24 diagnostics; reports known semantic failures, never repairs reflow."""
import argparse
from collections import Counter
import json
import math
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def normalize(text):
    return " ".join(text.split())


def valid_rect(rect):
    return len(rect) == 4 and all(math.isfinite(x) for x in rect) and rect[2] > 0 and rect[3] > 0


def owned_line_indices(capture, title, tolerance=1e-6):
    """Conservative diagnostic fallback when title.lines is empty, not a semantic rule.

    Require equal transcript and all four normalized rectangle values within tolerance.
    Return candidates, including ambiguity; the caller accepts ownership only for one match.
    No containment-only or substring matching, which could select unrelated nearby text.
    """
    if not title or not normalize(title["text"]) or not valid_rect(title["rect"]):
        return []
    return [i for i, line in enumerate(capture["lines"])
            if normalize(line["text"]) == normalize(title["text"])
            and valid_rect(line["rect"])
            and all(abs(a - b) <= tolerance for a, b in zip(line["rect"], title["rect"]))]


def words(text):
    # Used only to report missing source heading groups, not to assign title ownership.
    return " ".join(re.findall(r"\w+", text.casefold()))


def assess(capture, review):
    if (capture["caseID"], capture["page"]) != (review["caseID"], review["page"]):
        raise ValueError("Capture/review page identity mismatch")
    title = capture["containers"][0]["title"]
    selected = title["text"] if title else None
    if selected != review["reviewedTitleTranscript"]:
        raise ValueError("Title selection changed; source review required before reusing semantic labels")
    indices = owned_line_indices(capture, title)
    unique = len(indices) == 1
    flagged = [i for i, line in enumerate(capture["lines"]) if line["isTitle"]]
    selected = selected or ""
    return {
        "capture": review["capture"], "caseID": capture["caseID"], "page": capture["page"],
        "sourceSHA256": capture["sourceSHA256"], "lineCount": len(capture["lines"]),
        "titleText": selected if title else None,
        "titleLineCount": len(title["lines"]) if title else 0,
        "ownedRootIndices": indices, "uniqueTextRegionOwnership": unique,
        "flaggedRootIndices": flagged, "titleAndFlagAgree": unique and flagged == indices,
        "nestedContainerCount": len(capture["containers"]) - 1,
        "nestedTitleCount": sum(c["title"] is not None for c in capture["containers"][1:]),
        "reviewedRole": review["selectedRole"],
        "knownFalsePromotion": unique and review["selectedRole"] in {
            "body", "dialogue", "sign", "running_header"},
        "captionCandidateRequiringTableOwnership": unique and review["selectedRole"] == "table_caption",
        "sourceHeadingGroupsMissingFromTitle": [group for group in review["headingGroups"]
                                                if words(group) not in words(selected)],
    }


def analyze(captures, review_path):
    reviews = json.loads(review_path.read_text())["pages"]
    manifest = {d["id"]: d["sha256"] for d in json.loads((ROOT / "corpus/manifest.json").read_text())["documents"]}
    results = []
    for review in reviews:
        capture = json.loads((captures / review["capture"]).read_text())
        if capture["sourceSHA256"] != manifest[review["caseID"]]:
            raise ValueError("Capture/corpus checksum mismatch")
        results.append(assess(capture, review))
    return {"schemaVersion": 1, "purpose": "Rejected metadata-only heading candidates; not passing fidelity claims",
            "pages": results, "summary": {
                "pageCount": len(results),
                "titles": sum(r["titleText"] is not None for r in results),
                "uniqueTextRegionOwnership": sum(r["uniqueTextRegionOwnership"] for r in results),
                "titleAndFlagAgree": sum(r["titleAndFlagAgree"] for r in results),
                "knownFalsePromotions": sum(r["knownFalsePromotion"] for r in results),
                "captionCandidatesRequiringTableOwnership": sum(r["captionCandidateRequiringTableOwnership"] for r in results),
                "reviewedRoles": dict(Counter(r["reviewedRole"] for r in results)),
                "nestedContainers": sum(r["nestedContainerCount"] for r in results),
                "nestedTitles": sum(r["nestedTitleCount"] for r in results),
                "missingSourceHeadingGroups": sum(len(r["sourceHeadingGroupsMissingFromTitle"]) for r in results),
            }}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--captures", type=Path, default=ROOT / "tools/vision_titles/captures")
    parser.add_argument("--review", type=Path, default=ROOT / "tools/vision_titles/review.json")
    args = parser.parse_args()
    print(json.dumps(analyze(args.captures, args.review), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
