# Issue #30 corpus candidates

Seven public-domain or CC BY sources broaden the development corpus beyond the ten existing
cases. They were chosen for the gaps named in [#30](https://github.com/vocaro/PDFReflowLib/issues/30),
plus academic papers in the two-column journal format of an owner-supplied example (Lamport,
"Time, Clocks, and the Ordering of Events in a Distributed System", CACM 1978). That example is
ACM-copyrighted and is not registered; the NBS paper is its public-domain stand-in.

| Case | Gap | Evidence on review pages |
| --- | --- | --- |
| `nbs-jres-geltman-1977` | Scanned two-column academic paper | Page 1 footnotes under a rule and equations 1–4; page 2 spanning figure and OCR-garbled equation 5 |
| `arxiv-replay-clocks-2023` | Born-digital two-column academic paper | ACM layout, rotated arXiv stamp, pseudocode and figures on pages 1, 3, 4; no footnotes seen on pages 1–4 |
| `usgs-mcs2025-copper` | Borderless tables | Page 1 statistics table with no rules and indentation-only row groups; page 2 spanning headers, in-cell superscripts, table notes |
| `scotus-loper-bright-2024` | Footnotes | Footnote 2 continues from page 97 to page 98; separator is dash characters |
| `census-rrs2002-01` | Damaged encoding | Page 1 extracts cleanly; page 3 "Two data files were used." extracts as `Wzr gdwd ohv zhuh xvhg1` |
| `uscis-m618-arabic-2015` | Right-to-left script | Page 21 extracts form I-551 as `551-I`, mirrors `(USCIS)` and reorders the phone number |
| `irs-p596-zhs-2025` | CJK script | Page 3 mixes Chinese with IRS.gov/EITC, form numbers and amounts; page 16 not rendered for review |

`verification.json` records the fetcher digest and exact identities. Each case downloaded into an
empty cache and matched its pinned byte count and SHA-256. Source PDFs remain ignored.

Rights evidence is recorded per case in the manifest. Loper Bright, the Census report and the USCIS
guide are marked tentative: the first two rest on federal authorship without a publisher statement,
and USCIS states some site images are licensed rather than public domain.

None of the seven has been converted. Each is excluded from the corpus gate in
`corpus/regressions.json` until a review-point file, content contract and baseline exist. Still
missing from #30: vertical CJK, Hebrew and Devanagari sources with clear rights.
