# Dietary Guidelines layout baseline

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated macOS arm64 release CLI.
Corpus: owner-supplied Dietary Guidelines for Americans, 2025–2030, 10 physical pages,
3,422,452 bytes; SHA-256 `c34f1bec5c9416265670b7fcb24556bb8616ba95e8de2f2890460b6bbca1a472`.
Build: repository `178ccf0`, Xcode 27, macOS 27.0 (26A428),
`swift build -c release --scratch-path .build/corpus-cli`. Executable SHA-256:
`6ae1a17ef314531255ad1e768c4c75c6739483fe793de6627d8f9b5b2021602f`.

## Conversion and validation

The final fresh-process run completes in 1.35 seconds with 111,099,904 bytes peak RSS
(106.0 MiB), below the initial 192 MiB case ceiling. Sampled physical footprint peaks at
83,673,928 bytes. The EPUB is 3,967,138 bytes. All 40 progress events pass monotonicity,
bounds and completion checks; EPUBCheck 5.3.0 reports no errors or warnings. The report counts
2 pages with reflowed text, zero OCR pages and 11 images. These are one-run process metrics,
not mobile budgets or text-coverage scores; separate Apple services are excluded.

Generated receipts remain unchanged. The complete progress log is losslessly compressed and
its original identity retained. A separate full conversion prepares all ten pages for comparison.
The source and full EPUB remain local. The official CDN download matches the owner-supplied
file; `download-verification.json` records the identity and fetcher implementation.

## Source inspection and visual review

The source metadata identifies Adobe InDesign 21.1. `source-inspection.json` records pypdf
6.10.0 metadata, raw structure roles, RoleMap, page text and top-level stream operation counts.
The source has a structure tree, but its custom `/h2` and `/bullets` roles map to `/P`.
Names that resemble headings or lists therefore do not establish those standard semantics.
The converter does not currently consume the structure tree.

Visual spot checks cover physical pages 1 and 3; exact XHTML fragments cover all ten pages.
Other pages have prepared comparison views but are not visually adjudicated.

- Pages 3–10 contain only page-image figures in the EPUB, accompanied by unsupportedGraphics
  warnings. Native body text is consequently unavailable for reader text resizing. Page 3 has
  illustrated section headers, two-column bullets and a full-width callout. Its top-level
  stream contains `sh`; our GraphicsReader marks that shading operation unsupported. This is
  a concrete fallback trigger on page 3, not a complete diagnosis of the other seven pages.
  [Issue #13](https://github.com/vocaro/PDFReflowLib/issues/13) tracks more selective preservation.
- Page 3's whole-page image is much too small in the comparison pane, reproducing
  [issue #3](https://github.com/vocaro/PDFReflowLib/issues/3). Original layout and decoration are
  visible, but preserving their appearance does not establish usable reflow or readable sizing.
- Page 1 emits `GuidelinesFor Americans`, `Protein, Dair y` and `Ve getables`. Labels on opposite
  sides of the food pyramid become adjacent prose. The cover image is also present. This is
  native-text reconstruction, with no OCR used; [issue #14](https://github.com/vocaro/PDFReflowLib/issues/14)
  tracks word boundaries and label ownership.
- Poppler simple output also interleaves page 3's bullet columns and shows broken image links
  (existing harness issue #9). Positioned output preserves the page arrangement more closely
  but visibly overlaps cover title text. Neither comparator output is the reference truth;
  source rasters resolve the visual comparison.

The core bullet-group reading order remains unqualified because those pages currently bypass
reflow. Future regressions should preserve section-local left/right ordering and full-width
callouts, not merge the entire left page column before the entire right column. The supplied
PDF and retained excerpts keep HHS/USDA attribution, separate from the library MIT license.
