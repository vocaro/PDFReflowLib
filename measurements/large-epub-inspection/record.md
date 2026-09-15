# Explicit limits for large EPUB content inspection

Issue [#25](https://github.com/vocaro/PDFReflowLib/issues/25), 2026-09-15, baseline
`7fb0e7b`. The shared `tools/check_corpus_content.py` reader now accepts keyword-only
`max_entries` and `max_uncompressed_bytes`; `check_evaluation` forwards them, and the CLI
exposes `--max-entries` and `--max-uncompressed-bytes`. Defaults remain 10,000 entries and
536,870,912 expanded bytes. Both limits are inclusive, independent integers from 1 through
`sys.maxsize`; bools, non-integers, zero, negatives and larger values are rejected.

Admission still occurs before any package/chapter read. Duplicate names, malformed XML,
invalid/duplicate page boundaries, missing assets and content-contract failures remain errors.
Member names are cached once for image-presence lookup, avoiding a full member-list allocation
and search for each of NOAA's 11,245 image references. The reader never extracts archives or
decodes their images. ZIP metadata is loaded on open; chapter XML and accumulated page content
still require memory. The explicit ceilings are not process-memory limits or EPUB conformance
qualification.

## Reproduction and controls

At baseline, loading `tools/check_corpus_content.py` from `git show 7fb0e7b:tools/check_corpus_content.py`
and calling `read_pages` on the retained PNG NOAA archive produced:

```text
ValueError: EPUB exceeds inspection bounds
TypeError: read_pages() got an unexpected keyword argument 'max_entries'
```

The first call used defaults; the second supplied 20,000 entries and 4 GiB. The updated reader
retains the first rejection and supports the second request.

Eight focused tests in `tools/test_inspection_limits.py` cover API and real subprocess CLI
behavior. The large synthetic fixture creates 1,834 page anchors, 81 spine documents and
11,245 image references, plus 513 MiB of actual expanded padding. It needs both overrides to
pass and verifies every page's text and ordered image references. Padding is generated in
1 MiB chunks in a compressed temporary ZIP; no large fixture is stored in Git. These are
content-inspector fixtures, not valid image or EPUB conformance fixtures.

Other controls independently exceed the default entry count, use exact inclusive ceilings and
one-below values, verify rejection before XML reads, reject malformed API/CLI values, retain
duplicate-entry/XML/page/asset failures, and prove that larger admission values do not turn
missing source text into a pass. Existing small API and CLI calls pass with omitted limits.

```sh
python3 -m unittest discover -s tools -p 'test_*.py' -v
python3 -m unittest discover -s measurements/noaa-output-policies -p 'test_*.py' -v
python3 measurements/large-epub-inspection/verify.py --outputs .build/noaa-policy-review/full
git diff --check
```

Results: all **77 Python tool tests** passed in 7.082 seconds, all **4 NOAA measurement tests**
passed, and the diff whitespace check passed. The tool suite includes eight new inspection-limit
tests and all prior caller regressions. No runtime Swift code changed; new Swift-suite results,
conversions, EPUBCheck runs or device-memory measurements are not claimed.

## Retained full NOAA outputs

`verify.py` checks the unchanged local EPUBs from the
[NOAA output-policy measurement](../noaa-output-policies/record.md). It verifies each archive's
SHA-256 against the committed receipt before inspection. Both archives reject defaults and
reject either override alone. Both succeed with `max_entries=20000` and
`max_uncompressed_bytes=4294967296`:

| Policy | ZIP entries | Expanded bytes | Source pages | Image references |
| --- | ---: | ---: | ---: | ---: |
| PNG | 11,331 | 1,516,406,112 | 1,834 | 11,245 |
| JPEG | 11,331 | 1,522,700,828 | 1,834 | 11,245 |

PNG SHA-256: `1d0dae81928a5a798e55779c3b083f8e392d966a90e7e67d9c7c6d5b2402ecf6`.
JPEG SHA-256: `1cf27a1f22c7110c7a210e19e5a094159ac38d805167cef8b53fc865013e1f11`.
Every ordered page anchor, each page's text after removing whitespace, and each page's ordered
image ownership matches the prior dedicated inspection. Whitespace is excluded from that
comparison because the two readers separate list/figure blocks differently. No source-fidelity
claim follows from matching two inspectors on the same output.

The original NOAA measurement and receipts remain historical records. Its default conversion
failure, #5, and the full NOAA/Warren routine-corpus exclusions are unaffected. In particular,
NOAA has no reviewed passing default-budget content contract, so the CLI still refuses that
case even when larger inspection limits are supplied; direct `read_pages` supports bounded
inspection independently of the routine contract lane.
