# Keep opposite-side cover labels intact

Issue #172, measured on 2026-09-23 against main `a1bd1c8`; implementation `d22b485`
and styled-text normalization follow-up `b70a608`. Source: the corpus-pinned DGA,
SHA-256 `c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472`.

Source page 1 was rendered and inspected. PDFKit returns the left label's second line
and the right label's second line as one wide selection (`& Healthy Fats & Fruits`).
Content-stream show origins propose a split only across a large page-relative and
font-relative gap. Rectangular PDFKit selections measure each piece inside the existing
gate; the pieces must account for every non-whitespace character exactly once and
leave a substantial ink gap. The original attributed substring supplies the styles.
The U+FFFC-to-space normalization preserves UTF-16 offsets and is applied consistently
before matching the original styled string.

The resulting `Vegetables` and `& Fruits` lines share their right edge. An ampersand-led
alphabetic label continuation may use that edge within ordinary paragraph leading.
This limited rule does not accept the arithmetic derivations that invalidated the
broader right-alignment proposal in the issue's previous investigation. No source-name
or source-word matching appears in the implementation.

All three food labels now form intact paragraphs, and both footer labels remain complete.
Column-major cover order is accepted by the issue's item 2. Item 3's exercise-marker fix
already exists on main, and item 4 was explicitly assigned to table readers; neither is
claimed as a new fix here. The preserved cover image and existing review warning remain.

Four focused tests cover detached selection ownership and style, declining ordinary
cell gaps, right-aligned lexical controls, and the actual cover geometry. The strengthened
source contract checks paragraphs, not whole-page substrings: this caught an interaction
with #296 that otherwise kept all words while splitting labels into headings. The #296
follow-up limits its sparse-title fallback; integration verification must retain these
paragraph checks.

The exact `d22b485` DGA conversion passes EPUBCheck, structure, progress and its 192 MiB
Mac RSS gate. Against freshly built main, only page 1's semantic output changes; all 28
image entries and page markers are identical. `comparison.json` records binary/archive
identities and measurements. The new source assertions fail against main. Raw captures,
books and logs remain under `/tmp/pdfreflow-172-*` rather than in the repository.

Before integration, 722 Swift tests, 250 Python tests (one documented skip), all documented
probe builds, the PDFKit gate check and eight fresh-process concurrency checks passed.
A preliminary full-corpus lane passed all 20 cases, including each content and memory gate.
That lane spans two equivalent candidate builds because the helper's gated measurement
callback was refactored while it ran; it is not evidence for one final integrated binary.
The final integrated tree must run its own stable-binary corpus lane.

Reproduce with Python 3.10 or later:

```sh
swift test
swift build -c release
python3 tools/evaluate_real_document.py --case dga-2025-2030 \
  --pdf corpus/cache/DGA.pdf --converter .build/release/pdf-reflow \
  --output /tmp/detached-cover-evaluation --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/check_corpus_content.py --case dga-2025-2030 \
  --evaluation /tmp/detached-cover-evaluation
```

These are targeted source fidelity checks and Mac process measurements, not whole-book
fidelity qualification or physical-device measurements.
