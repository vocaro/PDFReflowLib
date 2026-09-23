# Drawn writing beside a sparse layer

Measured 2026-09-23 on macOS 27.0, arm64, Xcode 27. Code: `37c2e8e`, based on
`a1bd1c8`. This is fresh evidence on main's pipeline, not the abandoned branch's
record. Refs #192.

The four items were checked separately:

1. On this baseline Earthdata slide 5's `NASA` was already a paragraph rather than
   a heading, but it was still incidental lettering transcribed out of the insignia.
   Its captured recognized rectangle lies wholly inside the source's placed raster.
   Recovery now excludes such lettering and retains the picture itself. The question
   remains one paragraph; no `NASA` occurs in this page's reflowed text. The new
   page-specific corpus assertion fails against the baseline and passes the candidate.
2. The drawn-writing geometry test no longer reads the declared language. The existing
   Arabic and Chinese corpus lanes actually run with `--language ar` and
   `--language zh-Hans`; both still recognize zero pages. Their EPUB entries and reports
   match the exact baseline with only the per-run package identifier and timestamp
   normalized by `tools/epub_identity.py`.
3. A folio plus a lone word no longer prevents the ink test. The generated version of
   Earthdata's two-line outline question with the native word `Goals` recovers the
   sentence under `en`, `ar`, and `zh-Hans`, and keeps the native word. A replay test
   substitutes an OCR typo `Goa1s` and verifies that the native spelling wins. This
   remains a deliberately sparse-layer rule: at most one letter run of at most 32
   letters, with at least two uncovered ink rows. Multiword layers, URLs and long
   unsegmented runs are excluded; expanding to all short layers falsely admitted
   Arabic cover/seal and map lettering during development. General missing paragraphs
   in an otherwise populated layer remain the separate text-layer judgment's work.
4. Recovery preserves the original pictures and non-page-sized graphic regions. An
   original region intersecting recovered writing becomes a supplemental artwork crop,
   so it does not swallow the transcription. Other figures remain normal figure crops.
   The writing's crop includes every recognized row, expands over any intersecting
   original region, and adds six points of padding. Slide 5 now has the insignia crop,
   a close crop of the complete two-line question, and the source-page reference. The
   close crop was opened and visually checked: the complete second line and question
   mark are present. No source raster or derivative is committed. Full-page background
   decomposition (#164/#182) is not introduced by this change.

The local crops follow the existing supplementary-reference policy. `.never` omits
these with the full-page reference; `.automatic` keeps them on recovered pages. A
failed recognition still keeps the original extracted crops. The page-store round
trip includes the new crop rectangles.

## Validation

`swift test`: **722 tests passed**, including the live en/ar/zh-Hans recovery cases,
source-derived Earthdata replay, native-spelling control, full artwork bounds,
empty/picture-only reading control, and page-store round trip.

Release converter SHA-256:
`9f98d78b3dcd50568e04788923d275a2f1d32aab5a80e698b1fc2be0f73cdf9b`.
The exact `a1bd1c8` baseline was built separately, SHA-256
`9c67cdec91f1098b0fe15d8a7a70736906601df3cb7f15ec3d7e2b06366c2f34`.
An earlier comparison using the preexisting main executable was discarded after
its stale provenance was identified; it supplies none of the results here.

All three complete books passed EPUBCheck, structure/navigation, progress, configured
memory ceilings and their reviewed content contracts. No memory ceiling changed.
The retained small summary is `results.json`; full receipts and archives were under
`/tmp/issue192-{earthdata,arabic,chinese}-{final,base-a1bd}`.

| Case | Pages | Recognized | Candidate peak RSS bytes | Content assertions |
| --- | ---: | ---: | ---: | ---: |
| Earthdata | 21 | 1 | 108,593,152 | 22 |
| Arabic newcomer guide (`ar`) | 116 | 0 | 175,341,568 | 26 |
| Chinese tax guide (`zh-Hans`) | 36 | 0 | 182,288,384 | 17 |

Earthdata's baseline fails the added absence assertion on `NASA`; every existing
positive assertion continues to pass. Arabic and Chinese are byte-identical at the
archive-entry/report level after the identity tool's two documented metadata
normalizations. These are single host runs, not a performance improvement claim.

Reproduce from the repository root (substitute the built converter path):

```sh
swift build -c release
python3 tools/evaluate_real_document.py \
  --case ntrs-20180003024-earthdata-slides-2018 \
  --pdf corpus/cache/20180003024.pdf --converter PATH/TO/pdf-reflow \
  --output /tmp/drawn-earthdata --epubcheck /opt/homebrew/bin/epubcheck
python3 tools/check_corpus_content.py \
  --case ntrs-20180003024-earthdata-slides-2018 --evaluation /tmp/drawn-earthdata
```

Repeat for `uscis-m618-arabic-2015` / `M-618_a.pdf` and
`irs-p596-zhs-2025` / `p596zhs--2025.pdf`. The evaluator reads their declared
languages from the manifest. Compare baseline and candidate archives and reports
with `tools/epub_identity.py` for the two non-English controls. The source identities
are checked by the evaluator before every conversion and copied into the summary.
