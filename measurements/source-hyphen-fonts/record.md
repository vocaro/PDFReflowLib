# Source-font evidence for technical line-break hyphens

Refs #214. This is a bounded repair; the magazine's `as-` / `say` remains unresolved.

Source: *Agricultural Research*, November/December 2012, USDA Agricultural Research
Service, physical pages 8 and 11 of the checksum-pinned 24-page PDF. SHA-256:
`2673d1fded74ad89c8b5c59dc325c7884601e1aca5b5755b15a105c1f5b0d761`.
Owner-approved development corpus and committed text derivatives only. The two new
`usda-magazine-{8,11}-spacing.json` fixtures contain original page operators and font
maps captured with `tools/probes/capture-spacing-source.swift`; no font programs,
rasters, crops or converted text are included. Existing layout captures provide the
source-native text, styles and rectangles. Attribution: USDA Agricultural Research
Service. This material is not relicensed under the library's MIT license.

The body uses Type0/Identity-H `WVUHWN+TimesNewRomanPSMT` (`C2_1`). Inserted break
hyphens use a separate TrueType resource, `TimesNewRomanPSMT` (`TT1`), which shows
only isolated `-` on each of these pages: nine shows on page 8, ten on page 11.
The body font itself draws actual hard compounds, both internally and at native
wraps: `sugar-` / `feed` on page 8 and `fire-` / `resistant` on page 11. Each compound
also occurs whole in the body font on its page. The raw technical breaks occur
between body-font `pyre` and `throids`, and `neonic` and `otinoids`. This distinction
is lost by PDFKit's attributed extraction, which reports the same font name.

The font-role distinction is corroborating evidence, not an explicit discretionary
character: both resources map to U+002D, and `TT1` uses ordinary WinAnsiEncoding.
There is no `/ActualText` or source soft-hyphen code that can settle an ambiguous
compound. The reader therefore requires a full bounded resource census, including
nested Form uses; at least four sole-hyphen shows; unambiguous native line ownership,
same-family/body-font neighbors, exact source/native text agreement and normal
lowercase continuation geometry for every use; a separately drawn hard compound at
a native wrap also attested internally; and at least three distinct dictionary-
vouched joined words. Unknown uses, interior punctuation, minus/bullet uses,
unsupported maps/state or shared ownership reject the resource. Font names, resource
names, publication identity and target words are never hard-coded.

Literal source hyphens and attributed styles remain intact. An optional exact-word
field on inline text carries the evidence to the actual paragraph join. English
language context is required there; a different continuation, a source-attested
compound, or two independently valid word halves keeps the hyphen. The metadata is
cleared when text is appended or the trailing character changes, and older inline
serialization without the field remains readable. The reader shares the existing
bounded `bfchar` parser, opting into complete UTF-16 sequences for source ligatures;
the glyph-identity caller retains its original single-scalar restriction.

This deliberately does not repair `as-` / `say`. The system English embedding knows
`assay`, but also both `as` and `say`. A probe of hyphenated forms gives the same
result for genuine compounds: `assay`, `cameraman`, `bylaw`, `recover`, `coop`, `email`
are known, while `as-say`, `camera-man`, `by-law`, `re-cover`, `co-op`, `e-mail` are all
absent. Absence cannot safely decide whether to delete a source hyphen. The same-PDF
vocabulary contains no unbroken assay/pyrethroids/neonicotinoids. No special word
list, morphology exception or weaker both-valid-halves guard is introduced.

Validation on 2026-09-23:

- Six focused Swift tests pass, including the two real source pages, generated Form
  resource contradiction, unsupported state, excessive shows, cancellation,
  source/native ambiguity, insufficient calibration, ordinary fallback-font
  controls, exact continuation, compound/English vetoes, style retention, optional
  metadata serialization, and malformed UTF-16 controls.
- The full Swift suite run before the final decoder-only test addition ran 789
  tests: 788 passed; one old source-page-17 ordering expectation fails in the
  integrated base because #214 now places `range, consistently` together before the
  intervening display. That test reconstructs saved PageContent directly and never
  calls this reader. The coordinator was notified to update the stale expectation.
- The 33 Python corpus-content tests pass. The two integrated page-12 contract
  entries were consolidated so both the quotation and paragraph checks remain.
- Otherwise identical release builds, with only the new NativeTextReader census
  hook disabled for the parent, each converted all 24 pages with the normal
  `pdf-reflow` basename. Both pass EPUBCheck and the 512 MiB process RSS gate.
- All 24 source markers and all 85 image assets are identical. All three XHTML
  documents are byte-identical apart from the three hyphen removals. Every page's text is
  identical except exactly three hyphen removals: page 8 `pyre-throids` to
  `pyrethroids`, `neonic-otinoids` to `neonicotinoids`; page 11 `launder-ings` to
  `launderings`. `as-say` stays literal. All 65 magazine content assertions pass;
  the exact parent fails only the five newly added assertions for these three words.

`results.json` records exact binary/output hashes and validation results. Raw
outputs remain in `/tmp/pdfreflow-214-hyphen-{parent,candidate}`. This qualifies the
bounded magazine repair; the coordinator owns integrated full-corpus validation.
#214 stays open until its remaining ordinary defect is resolved.
