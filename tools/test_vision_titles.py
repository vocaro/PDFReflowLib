"""Protect diagnostic ownership and source counterexamples, not a rejected runtime fix."""
import copy
import json
import unittest

from analyze_vision_titles import ROOT, analyze, assess, owned_line_indices


class VisionTitleEvidenceTests(unittest.TestCase):
    def test_changed_title_selection_requires_new_source_review(self):
        base = ROOT / "tools/vision_titles"
        review = json.loads((base / "review.json").read_text())["pages"][0]
        capture = json.loads((base / "captures" / review["capture"]).read_text())
        capture["containers"][0]["title"]["text"] = "A different selection"
        with self.assertRaisesRegex(ValueError, "source review required"):
            assess(capture, review)

    def test_source_controls_reject_metadata_only_mapping(self):
        report = analyze(ROOT / "tools/vision_titles/captures",
                         ROOT / "tools/vision_titles/review.json")
        pages = {p["capture"]: p for p in report["pages"]}
        # A unique owner plus agreement with isTitle still promotes source prose/dialogue.
        for name in ["cdc-13.json", "cdc-16.json", "warren-30.json", "warren-50.json",
                     "warren-100.json", "blue-book-9.json", "fed-32.json"]:
            with self.subTest(name=name):
                self.assertTrue(pages[name]["uniqueTextRegionOwnership"])
                self.assertTrue(pages[name]["titleAndFlagAgree"])
                self.assertTrue(pages[name]["knownFalsePromotion"])
        self.assertTrue(pages["blue-book-74.json"]["captionCandidateRequiringTableOwnership"])
        self.assertEqual(pages["warren-21.json"]["reviewedRole"], "heading")
        self.assertFalse(pages["warren-21.json"]["sourceHeadingGroupsMissingFromTitle"])
        for name in ["cdc-15.json", "warren-7.json", "blue-book-4.json", "911-19.json"]:
            self.assertTrue(pages[name]["sourceHeadingGroupsMissingFromTitle"])
        self.assertIsNone(pages["warren-920.json"]["titleText"])
        self.assertEqual(pages["warren-920.json"]["lineCount"], 0)

    def test_empty_title_lines_do_not_mean_absent_title(self):
        report = analyze(ROOT / "tools/vision_titles/captures",
                         ROOT / "tools/vision_titles/review.json")
        for page in report["pages"]:
            if page["titleText"] is not None:
                self.assertEqual(page["titleLineCount"], 0)
                self.assertTrue(page["uniqueTextRegionOwnership"])

    def test_repeated_words_require_unique_region_and_text(self):
        title = {"text": "A title", "rect": [0.1, 0.8, 0.4, 0.03]}
        other = {"text": "A title", "rect": [0.1, 0.3, 0.4, 0.03]}
        capture = {"lines": [copy.deepcopy(title), other]}
        self.assertEqual(owned_line_indices(capture, title), [0])
        capture["lines"].append(copy.deepcopy(title))
        self.assertEqual(owned_line_indices(capture, title), [0, 2])  # Ambiguous, not first-match wins.
        capture["lines"][0]["text"] = "A title with other text"
        self.assertEqual(owned_line_indices(capture, title), [2])

    def test_overlapping_or_invalid_regions_are_not_owners(self):
        title = {"text": "Title", "rect": [0.1, 0.8, 0.4, 0.03]}
        for region in [[0.1, 0.8, 0.4, 0.04], [0.1, 0.8, 0, 0.03],
                       [float("nan"), 0.8, 0.4, 0.03]]:
            capture = {"lines": [{"text": "Title", "rect": region}]}
            self.assertEqual(owned_line_indices(capture, title), [])
        self.assertEqual(owned_line_indices({"lines": []}, None), [])


if __name__ == "__main__":
    unittest.main()
