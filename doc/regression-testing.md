# Regression testing

Regression coverage across PDF types is the first development priority. Fixes to extraction,
layout or rendering require both a reproducer and positive controls from other layouts.
A valid EPUB can still contain incorrect text, wrong reading order or unreadable images.

## Gates

- `scripts/check-all.sh --fast`: Swift extraction/model/raster/EPUB tests, Python tool tests,
  and six small fixture conversions. No external PDFs are required. The raster tests inspect
  pixels, including crop origins, rotations, annotations and resource ceilings.
- `scripts/check-all.sh --corpus`: the same checks plus eight complete PDF conversions,
  sequentially, with EPUBCheck, monotonic progress, pinned source identities, memory budgets
  and reviewed page-specific content contracts. All selected cached sources and EPUBCheck
  are required; missing data fails explicitly. The evaluator does not download anything.
- `tools/check_corpus_content.py --case <id> --evaluation <directory>`: run the content contract
  against an existing complete evaluation without reconverting. This is an additional content
  check, not a replacement for the evaluator's EPUB/resource checks.
- `tools/run_corpus_regressions.py --converter <CLI> --epubcheck <executable> --output <new-directory>`:
  run the corpus lane directly. Repeat `--case <id>` to narrow a debugging run; the summary
  lists omitted cases explicitly. A failing case does not hide subsequent results.

Fetch originals explicitly with `tools/fetch_corpus.py --case <id>`. Downloads are cached and
checksum-verified. Publisher-blocked downloads require an owner-supplied matching original;
see [corpus instructions](corpus.md). Large originals and output EPUBs remain gitignored.

## Current content coverage

[corpus/regressions.json](../corpus/regressions.json) has 55 targeted checks on 18 reviewed pages
across eight books: FAA, algebra, 9/11, The Fed Explained, Dietary Guidelines, Our Flag, the CDC
comic and Blue Book. All source-page anchors must also remain complete and ordered, and semantic
text must contain no image attachment placeholders.

The checks preserve selected correct words, paragraph/list order, license attribution, image
presence and explicit transcription/fallback warnings. They read the actual EPUB spine, track
page boundaries inside styled text, preserve ownership across chapter-file continuations, and
exclude navigation/captions from source-text matching. They do not freeze serialization details
or broken output such as interleaved columns and flattened exponents.

The checker has negative controls for deleted text, text moved to the wrong page, reversed order,
missing images, missing/wrong-page warnings, changed source identity, failed conversion, missing
or duplicate page markers, and captions masquerading as source text. A list of assertions without
such controls could silently pass despite a broken checker.

Image-presence checks are weaker than visual fidelity checks. They cannot prove a flag's colors,
a diagram's arrows or mathematical notation is correct. Unit pixel checks and source-image review
cover selected rendering behavior; robust visual/semantic contracts need expansion. The corpus
lane does not supply a whole-book quality score or physical-device performance qualification.

Full Warren and NOAA conversions remain explicitly excluded from this successful-conversion lane
because of the known image-output ceiling failure (#5). The pinned Warren excerpt separately
checks its two textless pages. These exclusions are listed in output, never counted as passes.
The manifest consistency test requires every corpus document to be covered or explicitly excluded.

## Adding or changing a regression

1. Reproduce the defect using a pinned source. Add a small original synthetic PDF/operator
   fixture when that isolates the mechanism, and retain a source-derived real-document target.
2. Read the source visually before writing expected text, order, cell values or image properties.
   Do not derive expected correctness from the converter being tested.
3. Prove the test fails on the old behavior. Keep known unresolved defects in the roadmap/issues,
   rather than blessing them as golden output or disguising them as passing tests.
4. Add positive controls for neighboring behaviors and another document type. For example,
   attachment filtering must retain mixed styled text, blank scans, recoverable OCR and images.
5. Run the synthetic and corpus lanes. Review changed content/image counts; increases and decreases
   can both be suspicious. Update expectations only after reviewing the source and explaining
   the intended behavior change. Preserve historical measurement receipts.

[Issue-fix measurements](../measurements/quality-and-raster-fixes/record.md) and the
[cross-corpus content run](../measurements/cross-corpus-regressions/record.md) document current evidence.
