# Local paragraph typography after native box recovery

The final integration audit compared runtime `293aa28e036e59974862a0feb637e28d5509c3e5`
(contract revision `4f301ca`) with the landed next-wave baseline. The converter hashes were
`d7dc23e62c741e98c4529c1eeeaed2f31495175c18cc3013371bd33018c52eb2` and
`d0747e6d01997993290233a496dd3cb4682610eea8584fc0e3e9f6eaae5dc8eb`, respectively.
Conserved letters did not establish conserved paragraphs: NOAA page 1061's existing
summary became eleven navigation headings, and Fed page 47's two body paragraphs became
five individual rows. Newly recovered NOAA summaries on pages 69 and 74 also became headings.

The NOAA audit's pages with three or more added headings were 64, 69, 74, and 1061.
Page 64's added lines are genuine section headings already covered by the source column
controls; 69/74/1061 contain the complete summary paragraphs corrected here. The source
renders for all three summaries and Fed 47 were visually inspected. No raster is committed.

| Source page | Native paragraph evidence | Former incorrect interpretation |
| --- | --- | --- |
| NOAA 69 | Four 15 pt rows on 19 pt leading, two complete sentences | Four summary headings |
| NOAA 74 | Six 15 pt rows on 19 pt leading, four complete sentences | Six summary headings |
| NOAA 1061 | Eleven 12 pt rows on 16 pt leading, four complete sentences | Eleven summary headings after recovery of 9 pt box text |
| Fed 47 | Two and three 10 pt rows on 16 pt leading, separated by 32 pt | Five individual paragraphs borrowing the recovered box's 11 pt leading |

Sources are the checksum-pinned government publications:

- NOAA NCA5: `1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf`.
- The Fed Explained: `8db8fd9e1de63ac25a6f9585d78ded12f45ab56f0c14c52c199b36b368f84d60`.

The four text-only fixtures retain native layout-probe output and an additional `nativePage`
encoded from `PageReader.read` with `StructureTreeReader.Index`, using the pinned original
PDFs. This preserves the actual crop decisions, retained tags, line metadata, and links;
recreating fonts merely from PDF subset names would not replay those properties. The NOAA
pages have no retained structure assignments; Fed 47 has 23 unrelated tagged lines. Its
main paragraphs are untagged, and the opening paragraph links to source page 38. The
existing native capture does not recover NOAA 1061's visually italic confidence phrases;
this change does not claim to fix that pre-existing extraction limitation. An additional
styled-row control verifies that grouping preserves inline styles it receives.

`WrappedDisplayProse` reuses the existing geometric wrapped-prose evidence: at least four
rows and 200 characters, stable measure and leading, lowercase continuations, and ordinary
sentence text. It additionally requires two complete sentences, an uppercase opening,
no list or retained tag, unique line ownership, and no intervening text. Existing semantic
summaries, quotations, captions, and tables retain precedence. The existing native-panel
reconstruction applies typography locally to the complete summary. It does not raise the
page's global heading threshold, so the genuine nearby 14 pt headings remain headings.
The grouping operates on text already admitted to reflow; it does not change crop ownership.

Fed 47 uses a separate leading-only extension of the same geometric run builder. Two or
more aligned paragraphs, totaling at least five rows and 300 characters, must corroborate
one another at the document's native body size. At least three line pairs must state the
same leading. Bold, caption, list, heading-tag, short-measure, unrelated-column, and
inconsistent-leading controls cannot supply it. This evidence never raises the heading
threshold and does not relax the global four-pair spacing requirement or the smaller box's
own leading. The 32 pt paragraph break stays a break.

Validation on 2026-09-23:

- Fourteen focused Swift tests pass, including the four new source pages, existing Fed
  13/46/95 typography, NOAA 1691/1712/1730 genuine 14 pt heading controls, native/style
  restrictions, and unrelated-column and intervening-tag negatives.
- A counterfactual run disables only display-paragraph grouping and short-paragraph leading:
  both source tests fail, covering all three NOAA pages and both Fed 47 paragraphs (seven
  assertions). The candidate files were restored afterward.
- The corpus contract gains three complete NOAA summaries and two Fed 47 paragraph
  fragments. Fed's second fragment ends with the baseline's `vast major`, permitting the
  next page's continuation rather than requiring an erroneous dangling hard hyphen.
- No standalone probe source closure includes `LayoutReconstructor` or `PageTypography`;
  consequently the new layout helper adds no dependency to those 15 extraction/raster probes.
  The final root gate owns the complete documented-build check, full Swift suite, and
  integrated 21-document conversion. This focused record makes no full-corpus claim.

Refs #191, #214.
