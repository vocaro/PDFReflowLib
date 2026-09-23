# A native word and drawn words sharing one recognized row

Measured 2026-09-23. Code `d5b2d30` follows `37c2e8e`; the earlier experiment remains
in `record.md` unchanged. The review found a real gap: Vision can put a native word
and adjacent outlined writing in one OCR line. The first merger then appended the
native word a second time. Refs #192.

The new integration test constructs the same kind of outlined writing as Earthdata
slide 5, but places a bold native `Goals` immediately before the first row. It verifies
that Vision itself returns `Goals support user analysis` as one line before handing
the reading to the merger. With the prior merger restored, the test fails on:

```
Goals Goals support user analysis of very large data volumes?
```

With the corrected merger restored, the test passes: `Goals` occurs once and retains
its native bold run. The replay test uses the misspelling `Goa1s` at the native word's
measured location; the result is `Goals support user analysis` with the original bold
`Goals` and no duplicate.

The correction uses `RecognizedText.boundingBox(for:)` for each word. Whole-line
geometry alone does not locate a word inside a joined row. Word boxes are requested
only on the drawn-text path and transformed with any banded recognition; ordinary OCR
retains its existing request costs. Their ranges are consumed during merging and do
not spill to the page store. A same-row reading with unavailable word geometry takes
the existing `keptAsExtracted` / `ocrFailed(unreadDrawnText)` branch, preserving the
native word and original artwork instead of guessing. A separate control explicitly
checks that a reading filtered down to only picture lettering takes that same branch,
leaves the extracted page unchanged, and creates no supplemental recognized-artwork
crop.

Validation: the full **724-test Swift suite passed**; the two strengthened live and
picture-only tests then passed again, as did the misspelled-word replay. The live
same-row test was also run with the prior merger and failed, then rerun after restoring
the correction and passed. Logs stayed in `/tmp/issue192-{merge-suite,row-failed-control,
row-restored}.log`.

Final release SHA-256:
`b15d67fa86f305da37672a98d31ad17bff920db5e7a07f152dbfffa9be331fa6`.
All three complete lanes were rerun from the pinned sources. EPUBCheck, structure,
progress, memory and the **22 / 26 / 17** content assertions passed again. Recognized
pages remain **1 / 0 / 0**. Candidate peak RSS bytes were **105,463,808 / 172,556,288 /
175,554,560** for Earthdata / Arabic / Chinese. Both non-English EPUBs and reports
again match the exact `a1bd1c8` baseline under `tools/epub_identity.py`'s identifier and
modification-time normalization. The final small receipt is `same-row-results.json`;
complete receipts and archives were `/tmp/issue192-{earthdata,arabic,chinese}-merged`.
