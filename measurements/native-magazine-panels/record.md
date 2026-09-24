# Native magazine panels, captions and ruled tables (#191)

Fresh source runs on 2026-09-23, macOS 27 arm64, library defaults. The before executable was
built from exact main `a1bd1c8`; the candidate contains #295, #160 and the reviewed #182
backdrop work before this change. No previous branch measurement is reused. Checksummed
source identities and text-only extraction evidence are in the corpus manifest and the
`usda-magazine-*` / `techport-magazine-*` fixtures. All PDFs, renders, EPUBs and raw logs remain
outside the repository. TechPort has owner clearance for text derivatives only: no raster or
crop from any of its five pages is committed here.

## Source findings and behavior

- USDA pages 5, 8, 9 and 19: captions beside or over photographs now remain complete native
  paragraph units. The short stable-fly caption is two rows; the mosquito caption has a
  two-row opening followed by a separate lower paragraph. Source rows cannot be claimed
  partly by a crop and partly by neighboring body text.
- Page 16: the outlined initial is recognized as one letter from a bounded opening-paragraph
  crop. Only `A ` is prepended; all native words, styles, links and line metadata survive.
  The source paragraph begins `A team of Agricultural Research Service scientists in Parlier`.
  Recognition is subject to Vision variability; failure keeps the source initial. Page 21's
  different initial remains in its source crop in this run; it is not silently invented.
- Page 23: the two footer impressions become aliases only in the furniture ledger. Proved
  repetition removes both. The general native overprint rule is unchanged; a single-page
  negative control retains both impressions.
- TechPort pages 2–3: native sidebar fields reflow. The three TRL values (`Start: 4`,
  `Current: 6`, `Estimated End: 7`) remain native while the chart and its axis labels preserve
  source appearance. On page 4 all three ruled tables reflow, including a two-column merged
  header and the merged `Texas` row. Cell readings conserve every native non-whitespace
  character. Complete native cell lines preserve their styles and links.
- USDA 11–12: each displayed quotation and its attribution becomes one `blockquote`, excluded
  from navigation. These are quoted statements; the separately implemented Fed opener policy
  is not part of this issue's change.
- USDA 20–21 and 22–23: sustained native margins supply column order when decorative material
  crosses the gutters. Page-wide axial backdrops no longer force pages 20–21 into whole-page
  fallback. TechPort page 5 emits the three picture/caption cards from left to right, each
  with its complete caption. Raw picture geometry proves the gallery, and the exported crops
  retain their padded frames.
- TechPort's five repeated native header bands are proved together, then removed with their
  header graphics. Every row in a band participates in the repetition requirement.

## Safety and validation

755 Swift tests passed after the NOAA source controls and upright quotation guard. The focused source checks include all numbered issue cases, complete
caption and quotation assertions, native styles/metadata, merged cells, graphical chart lines,
shared backgrounds spanning separate grids, and single-page furniture negatives. Independent
review found and fixed three unsafe paint assumptions: pattern fills are not frames, a thin
raster strip is not a vector divider, and a clip-sized radial figure is not a page backdrop.
The full pipeline radial control retains its required image with `referenceImages: .never`.

58 corpus Python tests passed for the initial implementation; the final targeted corpus-content, runner and manifest checks passed all 46 tests. Both full affected sources pass their updated content contracts,
resource gates, structural checks and EPUBCheck with the same final release executable. The
machine-readable summary records one run, not a timing distribution: USDA 24 pages all reflow,
with one recognized initial; TechPort five pages reflow with zero OCR. Native-text comparison
found no lost prose: removed token fragments become joined words/compounds, and the doubled
running footer disappears. The magazine gains the formerly cropped body on pages 20–21 and
additional prose previously owned by frames and overlapping crop hulls. TechPort gains sidebar,
table and gallery text. The first 21-case broader run completed every conversion and resource/EPUBCheck gate, but content checks found NOAA leader/panel ownership and Fed body-sizing interactions. These require follow-up source controls and integrated validation before this issue can close. Earthdata page 5 also needs the separately landed #192/#296 native-label guard absent from this branch. TechPort was rerun successfully after correcting an invalid single-cell regression assertion. The latest NOAA composition correction is present in this checkpoint; final follow-up proof is pending.

Remaining #214 work is separate: paragraph continuations across display/figure interruptions,
Fed display-summary asides, and three line-end spellings that the current lexical policy cannot
decide. Ordinary URL wrapping and unrelated list semantics are not changed here.


The broader branch run completed all 21 cases with 17 content passes. The four content
failures were: NOAA pages 8/48, Fed pages 13/46 and the newly recovered page-123 sidebar,
Earthdata page 5's NASA label (the separate #192/#296 guard is absent from this branch), and
TechPort's invalid single-cell contract (corrected and rerun successfully). NOAA's captured
source controls now pass: dotted leaders remain separate until decoration classification,
and a patterned panel retains its artwork while its independently proved paragraph reflows.
The Fed page-123 source was rendered again: Box 7.1 actually precedes Interagency Initiatives.
Its recovered text therefore belongs in the continuity assertion, which now pins the box's
opening, introduction and closing paragraph as well as the following section. Reassessment
leaves only Fed 13/46's body sizing failures; a separate follow-up owns that guard. Root's
integrated corpus run remains required before closing #191.


The independent integration audit covered every NOAA and Fed page and found native text
losses outside the initial contract. Named ICCBased numeric colors are now recognized as flat
paint, with bounded resource lookup and color state restored across `q`/`Q` and Forms. Their
component count and Alternate space do not prove actual white without evaluating the embedded
profile, so ICC paint remains visible even for nominally white tuples. Pattern and unknown
spaces remain conservative. The intermediate attempt to omit nominal ICC white was rejected:
it shrank the report's aggregate artwork bounds and newly assigned native text to local crops.

An aggregate page-sized graphic retains the established page-reference/native-text behavior
unless every independently page-sized paint is a proved flat ground or background shading.
Audited NOAA pages 5, 25, 26, 34, 40, 41, 49, 52, 57, 62 and 76 had aggregate coverage above
75% but no individually page-sized paint. USDA 20–21 have independently proved background
shading and remain eligible; the other magazine/TechPort source controls have smaller bounds.

Adjacent collinear underline fragments are joined before table-header analysis: NOAA 962's
two-part link underline had become fictitious table columns and cropped a complete paragraph.
The same correction preserves IRS Chinese pages 4 and 16. Source controls retain the prose
without inventing figures. Final integrated corpus results are recorded separately.
