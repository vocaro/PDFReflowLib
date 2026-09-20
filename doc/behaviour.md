# Behaviour specification

This document states every rule the conversion applies, with its thresholds and the warning it
raises, organized by module in pipeline order. [architecture.md](architecture.md) describes the
modules and seams without these numbers; [decisions/](decisions/README.md) records why the
larger choices were made. Issue numbers in parentheses are provenance: the GitHub issue a rule
came from. Each rule is stated once here; the client-facing option guide
([conversion-options.md](conversion-options.md)) and README summarize and link back.

Sections end with an **Evidence** line naming the measurement record that established or
qualified the rule, where one exists. Records are frozen: they describe the build they measured.

## PDFConverter: entry, limits, progress, cancellation

- Input and output must be local file URLs. An existing destination is never overwritten
  (`ConversionError.outputExists`). Staging is a `.pdfreflow-<UUID>` directory beside the
  destination; it is removed on every failure and cancellation path, and the finished archive is
  moved into place atomically. The caller keeps any security-scoped access alive until the call
  returns and owns the destination's lifetime.
- Default ceilings: 256 MiB input bytes, 2,000 pages, 20 million extracted characters,
  12 million pixels per raster (1–48 million accepted), 180 DPI (72–600 accepted, subject to the
  pixel ceiling) and 512 MiB of image and entry bytes before ZIP compression
  (`maximumOutputBytes`; `Int64.max` effectively disables it). `maximumEPUBBytes` (default nil)
  separately caps the finished ZIP including archive overhead; it is checked before publication
  and cannot bound intermediate disk use. JPEG quality must be finite and in 0…1.
  `packageIdentifier` must be non-blank; `modificationDate` must fall in 1980–2099 (ZIP stores
  it in UTC at two-second resolution). These are input and work bounds, not process-memory or
  wall-clock guarantees; MiB means 1,048,576 bytes.
- Failures use `ConversionError` (`invalidOptions`, `unreadablePDF`, `encryptedPDF`,
  `outputExists`, `resourceLimit`, `renderingFailed(page:)`), `CancellationError`, or the
  underlying filesystem error. A failed final-size check throws `resourceLimit`, removes staging,
  leaves no destination and emits no completion event.
- `ConversionReport` carries `outputURL`, `pageCount`, `reflowedPageCount`,
  `recognizedPageCount`, `imageCount` and `warnings`. Source page numbers are one-based. A
  successful archive is not a claim that every page reflows.
- Progress events (`opening`, `extracting`, `recognizing`, `reconstructing`, `writing`,
  `completed`) are delivered through one async callback, awaited in order, never overlapping for
  one conversion; other conversions progress independently. The fraction is a monotonic work
  estimate, not a time estimate, and reaches 1 only after the EPUB exists at the destination.
  `ProgressBudget` fixes the shares: opening ends at 0.02; the pipeline takes 0.80 (ending at
  0.82; extraction 0.6875 of it, reconstruction 0.3125; recognition of a page is reported at that
  page's start); writing takes 0.17, reported over the archive entries; publication completes the
  remainder. The pipeline's end is clamped to 0.82 so binary rounding cannot make the first
  writing event step backward. Reconstruction hands each page's blocks to the writer as it makes
  them, so serializing them is counted as reconstruction; the writing stage is navigation,
  package metadata and the archive alone, and no event is reported between the last block and
  the first archive entry.
- Cancellation is Swift `Task` cancellation, checked at page, line and archive-chunk
  boundaries and between timed waits for the extraction gate. A platform rendering or
  recognition call already executing returns in its own time.
- With `packageIdentifier` and `modificationDate` both set, converting the same PDF twice with
  the same binary and environment yields the same SHA-256: entry order and names come from the
  writer, not directory enumeration. Rendering, OCR and image encoding can still differ across OS
  builds or device capabilities (#26); a client pinning bytes records the converter revision and
  OS build beside the digest.

Evidence: [progress-composition](../measurements/progress-composition/record.md),
[client-options](../measurements/client-options/record.md),
[raster-environment](../measurements/raster-environment/record.md).

## PDFPageSource: page windows

The PDF is opened in eight-page windows: PDFKit retains parsed page state for a document's
lifetime, so the source is reopened every eight pages and again between extraction and
reconstruction. Synchronous page work drains autoreleased objects, and pages that fall back to
images skip attributed-text extraction. ParentTree ownership for tagged pages is checked against
exact owner paths only when the relevant page is extracted, inside the same window, because
loading a sparse ParentTree's many null slots into one Core Graphics document causes avoidable
peak memory. These limits reduce retained work without capping Apple framework allocations or
fixing PDFKit's attributed-text leak.

Evidence: [pdfkit-structure-tree](../measurements/pdfkit-structure-tree/record.md),
[pdfkit-attributed-text](../measurements/pdfkit-attributed-text/record.md).

## NativeTextReader: PDFKit text, styles, scripts

- **Extraction gate (#21).** A process-wide lock serializes the synchronous PDFKit text step
  across converter instances. Acquisition tries the lock at once; a contended waiter checks task
  cancellation between 50 ms timed waits, and again after acquiring. What the step autoreleases
  (selections, attributed strings, their fonts) is drained inside the lock before it is released,
  because objects released later on another thread aborted the next extraction with the same
  `NSFont` exception although the two never overlapped under the lock (2 of 80 eight-worker
  processes aborted without the drain, 0 of 70 with it). The lock is released before progress
  callbacks, OCR, graphics work and writing. A cancelled waiter can return while another
  extraction still holds the lock; a PDFKit call already executing cannot be interrupted; each
  timed wait blocks its worker thread; concurrent imports trade throughput for serialization.
  Host PDFKit, CoreText or font work outside the library is not covered (Apple FB24796210).
- **One request per page (#4).** Styled lines are read as one union selection per page and sliced
  per line, which leaves about a twelfth of the attributed strings PDFKit leaks per request
  (135-page Fed: about 22,900 leaked objects per conversion with one request per line, about
  1,760 with one per page; the repeated-conversions gate allows 30 per page). What remains is
  the page's text itself, which only Apple can release (FB24783799).
- Image-attachment placeholders become word boundaries; empty selections are discarded before
  layout, vocabulary, OCR selection and coverage counting; object-only selections are discarded
  before attributed-string access so no image attachment is decoded. Placeholder-only pages
  follow the OCR policy.
- Explicit Core Text/Foundation baseline offsets preserve inline superscripts and subscripts;
  tiny positioning noise and full-line OCR offsets do not become scripts, and font size alone
  never establishes a superscript.
- **Drop caps.** A lowered, oversized single initial followed by substantial, consistently sized,
  normal-baseline prose is a drop cap, not a subscript: the following runs' size is its body
  size and its `readingRect` is a top-aligned body-height rectangle used for ordering, while its
  `rect` remains the full ink bounds for graphic intersections and crop preservation.
  Ambiguous styles, monospaced initials and missing native attributes supply no such evidence.
  Initial-word spacing and structure-tag consumption are separate concerns.
- **Missing word boundaries.** When adjacent, similarly sized attributed runs jump by more than
  the inline-script range and one carries a full-line offset, a space is inserted (PDFKit
  selections that concatenate visual lines). Existing whitespace and line-ending hyphens are
  unchanged; drop caps of a different size and opposite inline scripts are not evidence. This is
  not arbitrary within-line spacing repair or OCR spelling repair.

Evidence: [pdfkit-concurrency](../measurements/pdfkit-concurrency/record.md),
[pdfkit-gate-drain](../measurements/pdfkit-gate-drain/record.md),
[extraction-cancellation](../measurements/extraction-cancellation/record.md),
[pdfkit-repeated-conversions](../measurements/pdfkit-repeated-conversions/record.md),
[native-line-boundaries](../measurements/native-line-boundaries/record.md),
[drop-cap-order](../measurements/drop-cap-order/record.md).

## Content-stream readers

`ContentStreamWalk` gives every reader a budget of 100,000 operations and 128 saved graphics
states; a reader chooses through `Options` whether `q`/`Q`/`cm` inside a text object, a nested
`BT`, a stray `ET` or a positioning operator outside a text object disqualifies the page, whether
`Tf` is reported, a cap on `TJ` array elements, and how `'` and `"` are treated. `AnchorMatcher`
matches a show origin to a native line with a 0.75 pt tolerance and caps anchors and lines at
10,000 each and rectangle comparisons at two million per page; exhausting a cap falls back to
spatial reconstruction rather than partial results.

- **`NativeSpacingReader`.** Removes a PDFKit-inserted space only when a supported Type3
  text-show operation contradicts it: a tiny negative `TJ` adjustment at the removed space, with
  the font's one-byte `ToUnicode` map, text and placement matching. Explicit spaces, genuine
  word-size gaps, style attributes and ambiguous geometry are kept; unsupported fonts,
  transforms, Forms, character maps, text state and excessive work reject the page's evidence.
- **`GlyphIdentityReader` (#217, two of #186's five fixes).** PDFKit reads every glyph through
  its font's `ToUnicode` map; two kinds of font disagree with what they draw. A dingbat font
  (Zapf Dingbats and its clones ITC Zapf Dingbats, `Dingbats`, Monotype Sorts, subset tags
  aside) is read through the Zapf Dingbats encoding, so a bullet reported as the letter `l` becomes
  U+25CF. A non-symbolic Type 1 font whose map disagrees with its own `/Encoding` only in letter
  case (a small-caps credit reusing a capital's code point) is read as drawn (`BRAD FRITz` becomes
  `BRAD FRITZ`). The reader scans only simple (Type1/MMType1) and Type0/Identity-H fonts, only
  `Tj`/`TJ` shows drawn directly on the page (no Form XObjects), behind a resource-dictionary
  pre-check so pages without a candidate font pay nothing. A line is rewritten only where exactly
  one show's origin lies uniquely in its bounds and the reported text has one unambiguous
  occurrence there (its only occurrence, or the one standing alone between word spaces). Redrawn
  glyphs found isolated are flagged so a dingbat font's metrics never read as a superscript. It
  never invents a character.
- **`MarkedTextReader`.** Matches explicitly positioned text-show origins to unique native line
  rectangles for tagged-PDF association. Unknown glyph-cursor advancement, Form XObjects,
  missing or duplicate MCIDs, ambiguous geometry and incomplete groups keep spatial
  reconstruction. Origin matching is association evidence, not font decoding or proof of the
  author's semantics.

Evidence: [native-label-spacing](../measurements/native-label-spacing/record.md),
[structure-tags](../measurements/structure-tags/record.md).

## StructureTreeReader: tagged PDF

- The structure tree is parsed from a separate Core Graphics document into value-only page/MCID
  associations and exact owner paths, checking structural parent links, page identity, RoleMap
  resolution and duplicate references. Traversal is bounded to 200,000 visits and depth 64;
  exhaustion rejects the tree (fallback, never partial ordering). A false `MarkInfo/Marked` flag
  alone is not grounds to discard a populated tree. Cancellation is checked during traversal.
- Supported roles are `P` and `H1`–`H6`, reached through grouping containers and transparent
  inline spans. Heading levels enter the model and serialize as `h1`–`h6`; navigation stays flat.
  Table, figure and alternate-text semantics, Form content, generic `H`, general link ownership
  and arbitrary reading order are unsupported.
- Complete tagged groups may reorder only within an uninterrupted run of tagged text; unmatched
  lines and preserved images are barriers. Captions, list-like text and headings of 200 or more
  characters fall back to spatial order. Furniture removal or an image crop that takes a line
  invalidates an incomplete group. Validated paragraph identities prevent heuristic cross-page
  joins into a different paragraph. OCR text and unverified image-backed text never inherit tags.
- A page whose tagged text cannot be matched unambiguously reports `structureFallback`; a
  rejected tree adds one document-wide `structureFallback` warning attached to page 1.

Evidence: [structure-tags](../measurements/structure-tags/record.md),
[pdfkit-structure-tree](../measurements/pdfkit-structure-tree/record.md).

## GraphicsReader: painted regions

- Bounded Core Graphics paint operations and nested Form XObjects are scanned for placed images,
  vector paths and shading. Shading resources are bounded with conservative clipping, Form bounds
  and optional shading bounds, and rasterized by Core Graphics; the model stores an image asset,
  not a gradient. Unsafe or page-spanning bounds keep the page fallback. Cropping the original
  rendering preserves masks, clipping, paths and labels instead of exposing raw image resources.
- A footprint covers only the part the clip in force lets show, and a path or image wholly outside
  its clip is not recorded at all (#52, #98). An extent is not ink: FAA page 19 places a 338 by
  400 pt map under a 207 by 129 pt frame, and the rest of it reached 43 pt into the left column.
  The tracked clip is the bounding box of every clip path in force, intersected with the crop box
  and with each enclosing Form XObject's own box under that form's matrix, saved and restored by
  `q`/`Q` and around every form; it over-approximates the true clipping region, so no visible mark
  is ever dropped. Two rules keep the approximation safe: a clip path that reached no coordinate
  (`W n` with nothing constructed) and a form box that transforms to no area leave the clip
  unchanged rather than emptying it, and a painted footprint is padded by its two points before it
  is clipped, against a clip widened by the same two points — so a rule of no height survives, and
  a frame drawn exactly on the clip that bounds it keeps its tolerance and does not move.
- Placed raster XObjects are also reported separately from the undifferentiated region list, so
  the drawn-text test below can ignore a photograph's texture (#176).
- Text rendering mode is tracked across saved graphics state and nested forms. When every
  observed text uses invisible mode 3 and a graphic covers most of the page, attributed text is
  skipped and the page's typography is marked synthetic: layout treats it as ordinary prose, with
  no code or font-size heading inference (numbered lists keep their representation). Mixed
  visible/invisible text, text clipping and unsupported streams do not enter this path. This does
  not recover headings from a scan or correct inherited transcription.
- The reader's own budget is 250,000 charged operations per page, counted across nested Form
  XObjects, alongside 10,000 painted regions, 128 saved graphics states and 12 nested forms
  (#13). It is not `ContentStreamWalk`'s budget above. Over about 5,300 cached corpus pages only
  five sit between 100,000 and 250,000 operations and none between 200,000 and 1.9 million, so
  the number is set just above the heaviest real page rather than at the edge of a cliff: it
  admits FAA pages 226, 286, 288 and 302, whose prose the old 100,000 budget cost, and still
  refuses FAA page 448 at 1.95 million. It bounds what the reader accumulates and claims to have
  understood, not what the page costs: Core Graphics parses the content stream to its end whether
  or not the budget is exhausted, so FAA page 448 takes about a quarter of a second under either
  number. A charged operation costs about 0.25 µs and the reader's own state stays well under a
  megabyte.
- Unsupported or excessive drawing operations report `unsupportedGraphics` and require the
  original page image. Graphic-region merging and whole-line expansion repeat until the bounds
  stabilize, so a merged crop cannot cut through a newly intersecting text line; only text outside
  preserved regions reflows.
- A page that paints no region, shows no visible text and carries no annotation, and from which
  no text extracts, draws nothing at all; `PageReader` reports it as `emptyPage` (#224). A white
  ground is not a painted region, and a visible text-showing operator counts even when nothing
  extracts from it, so glyphs PDFKit cannot map are not mistaken for an empty page. The judgment
  is made on the extracted page, before recognition, which cannot read writing the page never
  drew; it is therefore the same under every OCR policy. Such a page is still preserved as an
  image, so `pageImageFallback` accompanies the warning.

Evidence: [shading-support](../measurements/shading-support/record.md),
[fractions-and-invisible-text](../measurements/fractions-and-invisible-text/record.md).

## PageDiagnosis: page evidence

`PageDiagnosis.assess` computes one `PageEvidence` per page, calling the ink measurement at most
twice and only when a judgment needs it:

- **Image-backed text.** Existing text lies over a graphic whose area exceeds 75% of the page
  (`pageSizedGraphicFraction`). This one conservative signal drives the `unverifiedTextLayer`
  review warning, the default source-page reference, and recognition candidacy under the
  retrying policy. It can flag illustrated pages with valid text and can miss cropped scans or
  pages assembled from smaller images.
- **Lacks readable text.** No text at all; replacement characters (U+FFFD/U+FFFC) exceeding
  `max(2, characters / 50)`; drawn text; or a damaged encoding. Automatic policies recognize such
  pages.
- **Exclusions.** A damaged encoding is diagnosed first, and such a page is judged neither for
  layer plausibility nor for drawn text. Plausibility is judged only on image-backed pages that
  do not already require a page image. Drawn-text candidacy requires some text, no damaged
  encoding, no required page image and an automatic OCR policy; it deliberately does not require
  `!imageBackedText`, because a born-digital slide with a full-bleed background fill reads as
  image-backed on that signal exactly as a scan does (the abandoned branch's `layoutComesApart`,
  #117, is not ported; `reflowsNoWords` is what keeps the two checks apart).

## TextEncodingCheck: damaged born-digital encodings (#38)

Two signals must agree before a page reports `damagedTextEncoding`:

- **Structural.** A simple font reachable from the page resources, a nested Form (to depth 4, at
  most 256 fonts) or the page tree's inherited resources (#223) has no `ToUnicode` map and a
  `Differences` encoding whose glyph names are index-style (`G108`, `g3`, `c63`, `glyph12`)
  for at least half its entries. Standard glyph names, `uniXXXX` names, named base encodings, a
  present `ToUnicode` map (even a wrong one) and composite (CID) fonts are not evidence. No glyph
  program is decoded.
- **Statistical.** With at least 20 words, the extracted words show a function-word rate under
  5% against an embedded English function-word list and a rare-bigram rate of at least 30%
  against an embedded 300-pair common-bigram table. Only documents declared English (`en`,
  `en-*`) are judged. No dictionary download, network or model is involved.

Example: the Census report's LaTeX pages render correctly but extract with every letter shifted
by three ("Two data files were used." extracts as "Wzr gdwd ohv zhuh xvhg1", its dropped
fi ligature included; the synthetic Type3 fixture that reproduces the mechanism extracts
"Wzr gdwd ilohv zhuh xvhg1"), because their Type 1C fonts use names such as `G108` without a
`ToUnicode` map.

Effect: the page is an OCR candidate under every automatic policy and `.always`, recommends a
source-page reference, and contributes no words to the hyphen-repair vocabulary. `.never` keeps
the unreadable text.

Evidence: [census-rrs2002-01](../measurements/census-rrs2002-01/record.md).

## EnglishText and TextLayerPlausibility: inherited layers, recognition, drawn text

Every English-language judgment reads `EnglishText`: which declared languages are judged
(`isDeclared`: `en`, `en-*`), the system lexicon (`NLEmbedding.wordEmbedding(for: .english)`, a vocabulary
lookup serialized behind a mutex; no network or download), the word classification over it, and
the line rule `readsAsWords`. Without a system lexicon only the ink test below runs.

**Word classes.** Whitespace-separated words are English (in the lexicon, or `a`/`I`), damaged
(a lower-case word the lexicon does not know, irregular capitals such as `sreANee`, a stray
lower-case letter from letter-spaced text such as `n e x t`, or letters of another script) or
neutral (unknown capitalized or upper-case words, which are names and abbreviations, compound
names such as `McDonald`, and words broken by symbols). Text split inside words (`fi e ld`)
joins up and is not counted.

### Inherited text over a page-sized image (#93, #7)

A layer fails, and reports `implausibleTextLayer` under every policy, when any test holds:

- **Too few English words.** With at least 20 judged (English plus damaged) words, and unless a
  fifth or more of the tokens hold digits (statistical tables and forms are not judged), fewer
  than half English fails.
- **Words misread in place (#7).** Under the same conditions, a tenth or more of all words are
  damaged words of three or more letters, or irregular capitals, that no neighbouring word
  completes (`tcld t» ftboot` for "told me about" on a carbon typescript).
- **Too little text for the ink.** Only when the layer holds fewer than 32 English words (no
  surveyed image-backed page leaves 75% of its text ink uncovered in more than 27 rows, and a
  layer can fail only with fewer English words than uncovered rows, so a larger layer is never
  rendered): the page is rendered at 180 DPI regardless of `rasterDPI` (the pixel ceiling still
  applies) and rows of glyph-sized ink outside the layer's lines are measured by
  `OCRTextCoverage`; the layer fails when at least 75% of that ink, in at least seven rows, lies
  outside its lines and it holds fewer English words than those rows.

The warning is written after recognition, so its message states what failed and what was done.
The problem clause is one of "Existing text over a page-sized image does not read as English:
only *e* of *j* words are English words (misspelled, wrongly capitalized or letter-spaced
text).", "… is missing most of the page's text: about *p*% of the page's text-shaped ink
(*r* rows) lies outside its lines, which hold *e* English words." or "… is a damaged
transcription: *m* of its *w* words are misread, not English words or names (such as “…”)."
The outcome clause is one of:

| Outcome | Message tail | Companion warning |
| --- | --- | --- |
| Replaced by recognition | "The existing text was discarded and replaced by OCR of the page image; review this page against the original page image." (or "the source PDF" when references are disabled) | `ocrUsed` |
| Recognition failed or found nothing | "The existing text was discarded, but OCR of the page image failed or found no text, so the page is preserved as an image." | `ocrFailed` or `pageImageFallback` |
| Recognition read no better as English | "The existing text was discarded, but OCR of the page image does not read as English either, so the page is preserved as an image and does not reflow." | `implausibleRecognition` |
| Kept over a comparison | "The page image was recognized again, but OCR failed or read it no better, so the existing text is retained; read the accompanying original page image instead." | `unverifiedTextLayer`, `ocrFailed` on failure |
| Kept by policy | "The existing text is retained because the OCR policy keeps it; read the accompanying original page image instead." | `unverifiedTextLayer` |
| Kept as extracted (#220) | "The page was recognized because its artwork holds writing, but OCR failed or found no text, so the page keeps the text and image crops it was extracted with; the writing in its artwork does not reflow." | `ocrFailed` |

`.automatic` replaces a failing layer; a layer that fails only by misreading words in place is
recognized and *compared* (`RecognitionPlan.Mode.compare`), and the recognition wins only when it
reads as English and misreads a smaller share of its own words (`readsBetter`).
`.automaticIncludingImageBackedText` and `.always` replace outright;
`.automaticKeepingImageBackedText` and `.never` keep the layer with `unverifiedTextLayer` and its
reference. A client wanting the pre-#93 automatic behaviour, recognition only of absent or
damaged text, selects `.automaticKeepingImageBackedText`. Recognition replaces the whole layer,
so a replaced page's reading order, styles and headings come from the recognized text.

### Every recognition is judged (#7)

`judgeRecognized` applies the English-share test alone to every recognition in an English book,
under every policy: a reading under half English that the language recognizer does not name as
another language with at least 0.95 confidence is noise (handwriting, or print recognition cannot
read). The recognized text is discarded, the page reports `implausibleRecognition` ("OCR of this
page image does not read as English: only *e* of *j* words are English words (handwriting, or
print recognition cannot read). The recognized text was discarded; the page is preserved as an
image and does not reflow.") and becomes a page image. A recognition can misread a tenth of its
words and still be the best text the page has, so the misread test is not applied to it.

**Headings from recognized text.** `readsAsWords` admits a recognized line in an English book as
a heading only when it holds no letter of another script, at least one known word, English in at
least half of all words (neutral words count against it), and digits in no more than half of its
tokens; a capitalized lexicon entry counts as English here. Table cells, digit strings and
handwriting read at heading size stay out of the navigation.

### Pages whose writing is drawn (#176)

A page whose text layer holds no letter at all (nothing, or only a folio: `reflowsNoWords`)
reflows nothing of its own. In an English book, under an automatic policy, it is rendered at
180 DPI and its text-shaped ink measured, ignoring everything inside placed raster images; when
at least two rows (`minimumImageOnlyRows`) stand outside the layer's lines the page carries
drawn text and is recognized like a page with no text layer at all. A page whose art forms no such
row (a chart, an answer key of bare surds) keeps its crops, and so does a page whose only rows
lie inside a photograph: writing the page draws is content its producer typeset; writing a
photograph shows belongs to the picture, which the crop preserves. Recognition attaches the
source-page reference in place of the crops. When recognition reads nothing, the page is left
exactly as extracted, with its crops, and reports `ocrFailed` ("This page reflows no text of its
own and its artwork holds writing, but recognition of the page failed or found no text; the
artwork is preserved as images and its writing does not reflow."). A layer finding the page also
carries is reported beside it, with the kept-as-extracted outcome, so the page can still be
reviewed (#220). This check coexists with the
inherited-layer check: a letterless page never has enough judged words to fail the word test,
and its two or three rows do not reach the ink test's seven.

### OCRTextCoverage: ink measurement

Rows of glyph-sized connected components (2.5–40 pt tall, aspect at most 12, fill density
0.08–0.9, side by side at similar height) are text-shaped ink; artwork, rules, fills and speckle
rarely form such rows. Ink is thresholded between 96 and 170 and read against the page's own
background: when a measurement finds no text row and the darker side of the threshold covers more
than half the page (`maximumBackgroundInk`), that side is the background and the page is measured
again inverted, so a slide printed white on dark blue is not one page-sized blob. A page whose
dark ink already forms rows is never inverted.

Evidence: the [Warren suspect-text excerpt](corpus.md#suspect-text-layer-excerpt) and its
contract `basis` in [corpus/regressions.json](../corpus/regressions.json),
[selective-ocr](../measurements/selective-ocr/record.md),
[ocr-headings](../measurements/ocr-headings/record.md).

## RecognitionPolicy: the decision table

`RecognitionPolicy.plan` is a pure function from `PageEvidence` and the OCR policy to a plan; a
page that requires a page image is never recognized. The whole table, and every resolution
below, is tested without a PDF in `RecognitionPolicyTests`.

| Policy | Recognizes when | Image-backed layer rule |
| --- | --- | --- |
| `.automatic` | the page lacks readable text, or its layer is implausible | judge: replace a failing layer, compare a misreading one |
| `.automaticIncludingImageBackedText` | lacks readable text, or the text is image-backed (graphic over 75% of the page) | always retry, replacing the whole page's native text |
| `.automaticKeepingImageBackedText` | lacks readable text | keep, reporting only |
| `.always` | every eligible page | always retry |
| `.never` | never | keep, reporting only |

`resolve` reconciles the plan with the recognition outcome into a `PageDisposition` (kept layer,
kept as extracted, replaced, or page image) and the page's warnings in report order: the
encoding diagnosis first, then `unverifiedTextLayer` for a layer that stands (or wins a
comparison) on an image-backed page, then what became of the layer and the recognition. Recognition
that succeeds and reads nothing is not a transcription (#222): the page is preserved as an image
(`pageImageFallback`), is not counted in `recognizedPageCount`, and reports `ocrFailed` ("OCR of the
page image found no text; the source page is preserved as an image and does not reflow.") rather
than `ocrUsed`. A compared layer still wins over such a recognition. Failed recognition reports
`ocrFailed` ("OCR failed; the source page is preserved as an image." or, after a comparison, "OCR
failed; the existing text layer is retained."). Recognized tables
become preserved regions; recognition marks the page for a source-page reference. Fresh OCR may
improve some errors and introduce others, lose native formatting or change reading order.

## OCRReader

Vision recognizes the page image, with the declared language when the recognizer supports it.
Uncertain words are preserved rather than dropped silently. OCR text is always reported as
transcription (`ocrUsed`: "Text is OCR transcription. The original page image preserves
unrecognized visual content."; with references disabled, "Supplementary references are disabled;
compare unrecognized visual content with the source PDF."). A recognition with no lines never
reports `ocrUsed`; see `RecognitionPolicy` above.

## DocumentEvidence and PageStore: what survives extraction

Extraction keeps only document-wide evidence: the hyphen-repair vocabulary (pages with a damaged
encoding contribute none), margin-furniture candidates, numbered-note heading pages, chapter
matches, the running character budget, the document's body size (the character-weighted
commonest size over every native page, #186) and the bold label styles that recur on at least
three pages (#218). Each extracted page is encoded as a binary property list in the workspace
(finite, infinite and NaN doubles round-trip; equal values share a slot, so a negative zero can
reload as positive zero, and no reconstruction step reads the sign of zero), reloaded once in
order, and deleted on reload; the page directory goes when reconstruction finishes, leaving only
assets. Reconstruction emits each page's assets and blocks to the writer as it finishes them,
holding back only the trailing block, which a continued paragraph on the next page can still
join; the whole block list is never resident. Model validation follows: each block is checked as
it arrives, and the checks that need the whole document — that it has blocks at all, and that
every chapter boundary reached a standalone page marker — run when the stream ends.

Evidence: [page-retention](../measurements/page-retention/record.md);
[decision 0001](decisions/0001-two-pass-page-retention.md),
[decision 0008](decisions/0008-streamed-blocks-to-the-writer.md).

## FurnitureDetector: running headers, footers and folios

- Short outermost margin rows are removed when at least three neighbouring or alternating
  physical pages support the decision with stable vertical position and typography (a run of at
  least three, in a ledger of at least three pages). Evidence is local to a chapter; document
  length does not set the frequency threshold.
- The header candidate band is the top 10% of the page (extended for the 9/11 report's
  headers); the footer band is the bottom 7%, kept narrower to retain whitespace-cut behaviour
  around illustrated rows: wider footer removal would disturb the alphabetical row order of the
  illustrated entries on Our Flag pages 34/42/43 without independent layout work. Synthetic invisible-text
  layers use the outer 7% on both edges, because their typography supplies no native font
  evidence. Font-size drift tolerance is the larger of 0.5 pt and 10% of the size (25% for folios,
  whose size comes from glyph height so fallback font estimates do not break matching).
- Where the outermost row is no candidate on its own — its lines run into the row inward of them
  rather than standing clear — the rows stacked on it form one block. Each further row joins while
  it stands nearer the block than its own separation, so the block ends at the first row that is
  set apart and is separated from the body as one outermost row is. A block may hold at most eight
  lines, and its inward boundary must stay within the outer eighth of the page, at either edge.
  Every line of a block is weighed for repetition on its own, and goes only when every other line
  of its block goes, so a block one page words differently stays whole on that page. The ceiling
  and the outer eighth are what keep genuine content out: the IRS EIC table's repeated head is
  nine rows deep, and the Earthdata deck's title, repeated unchanged on three consecutive slides,
  reaches to 0.82 of the page.
- Textual headers must be separated from inward content. Boundary page numbers share repetition
  evidence only with the same physical-page offset; numeric chapter-page folios keep their chapter
  prefix; internal chapter and date digits stay significant. Matching body titles, nearby captions
  and a page's only text are retained.
- Each affected page reports `furnitureRemoved` ("Repeated header or footer omitted from the
  reflowed text."); `removeRepeatedHeadersAndFooters = false` keeps everything. This is spatial
  evidence, not tag consumption or a universal header classifier.

Evidence: [local-header-regressions](../measurements/local-header-regressions/record.md),
[report-header-qualification](../measurements/report-header-qualification/record.md),
[stacked-margin-blocks](../measurements/stacked-margin-blocks/record.md).

## LayoutReconstructor, PageTypography, LineRole, BlockAssembler

### Columns and paragraphs

Whitespace cuts recover ordinary columns and spanning headings; a narrow cut requires substantial
text on both sides so short name/description cells do not become independent columns. Paragraph
reconstruction joins hard wraps and narrowly supported cross-page continuations; a validated
chapter start or a differing tagged paragraph identity blocks a cross-page join. The separate
page-size estimate governs whitespace cuts and paragraph geometry. Known cross-page splits and
folio joins are tracked in #45.

The cuts recurse 32 levels. A page whose separating gaps never narrow is cut one block at a
time, so its depth is its block count: uniform leading wider than 110% of the page body, as a
double-spaced typescript sets, reaches the limit at 33 blocks. Ordinary pages do not come near
it: the deepest of the captured source layouts cuts eleven levels. A group the limit leaves
uncut keeps the order it was extracted in, and the page reports `complexLayout` rather than
leaving that silent, as the tag phase reports its own give-up (#224).

- Two lines are one paragraph when they **share a column** (left edges within 1.5 bodies, the gap
  between them from −0.4 to 0.9 of a body) or are **two pieces of one printed row**: they overlap
  vertically by at least half the shorter one's height, the second stands to the right of the
  first, and less than 0.75 of a body separates them — the width a whitespace cut needs for a
  column, so a table's cells and the two ends of a running header remain separate blocks (#57).
  A short previous line ending a sentence closes its paragraph either way.

### Type sizes and headings

- The page **body** is the character-weighted commonest size over every line, at least 4 pt. The
  **established body** is the commonest size among reflowable lines (text preserved inside
  images excluded, so a figure's small labels cannot promote surrounding prose) when at least
  three lines and 200 characters support it; a sparser page establishes none. The **heading body**
  is the larger of the two.
- On a page that establishes no body of its own (a back cover, a cover with one short
  cross-reference line), the **document floor** is 110% of the document's body size (#186);
  otherwise zero.
- The **heading threshold** is the largest of 125% of the page body, 110% of the heading body and
  the document floor. A line is heading-sized when it reaches the threshold, is under 200
  characters, opens with a capital, a digit or a mark unless it **stacks** with another
  display-size line (same size, directly beneath or above at ordinary leading, sharing the left
  edge, centre or right edge), and, on a recognized page in an English book, `readsAsWords`
  holds. A lone heading-size line opening in lowercase is display text that heads nothing
  ("pages 2, 4-14" beneath a cover title), while the second line of a two-line title keeps its
  reading because it stacks. Candidates within 10% of a supported body size are suppressed while
  the 25% page-size rule still applies, which keeps modestly larger section headings; short
  titles beside images keep the page evidence.
- **Section labels (#218).** A bold sub-heading set at or near body size carries no size
  evidence, so it is recognized separately: the line must read wholly bold, open with a capital,
  digit or mark, end no sentence, and its style must recur on at least three pages of the
  document (gathered in the extraction pass), so a single bold run near body size cannot promote
  itself. It must open a paragraph: directly beneath it on the page's own paragraph geometry, or
  past an intervening picture (never a painted 1-pt thin rule) with everything between the
  picture and the opening smaller than the body (a caption, a credit), the opening within four
  body heights of the last such line. Below 95% of the body only a paragraph opening on the page's
  established first-line indent (at least two instances) counts as its text. Only this bold,
  body-adjacent path exists: italic labels, two-line stacked titles, hanging-entry titles, outline
  labels and tinted-box titles are not implemented.
- Heading levels from tags serialize as `h1`–`h6`; visible typography otherwise supplies flat
  heading navigation. Synthetic invisible-text pages supply no code or heading typography.

### Code and lists

Monospaced text is code and keeps line breaks and indentation; a line opening with a list marker
keeps its break. Both are preformatted blocks that retain native emphasis and scripts; inserted
newlines and indentation are unstyled.

Evidence: [heading-body-regressions](../measurements/heading-body-regressions/record.md),
[three-fidelity-fixes](../measurements/three-fidelity-fixes/record.md),
[preformatted-styles](../measurements/preformatted-styles/record.md),
[dga-layout-qualification](../measurements/dga-layout-qualification/record.md).

## HyphenRepair

- A soft hyphen (U+00AD) at a wrap is removed. A hard line-end hyphen is considered only when
  the next line opens in lowercase; the join is decided on the letters either side.
- The hyphen is removed silently when the book's own vocabulary holds the joined word and not the
  hyphenated compound. When the vocabulary holds the compound, the hyphen stays silently.
- When the vocabulary is silent on both, an English document's system lexicon may decide (#186):
  the join goes ahead, still silently, only when each half has at least two letters and the two
  together at least six, the lexicon holds the joined word, and *not* both halves are lexicon
  words on their own, so `com-panies` and `infec-tions` join while a genuine compound like
  `camera-man` keeps its hyphen and still warns. Only the lexicon judges a half's standing, never
  the page-local vocabulary: extraction has no notion of a line that opens with the second half of
  a broken word, so "panies interested in…" adds the bare fragment "panies" to the vocabulary as
  if whole, which would otherwise make `com-panies` look like two real words and block the join.
- Otherwise the hyphen is retained and the page reports `uncertainHyphen` once ("An ambiguous
  line-ending hyphen is retained. Review source word joins.").

Evidence: [spine-continuity](../measurements/spine-continuity/record.md).

## Region detectors

- **`TableRegionDetector`.** Aligned numeric dot-leader rows with a nearby, similarly aligned
  textual header are preserved as one region image with an `imageRegion` warning; a contents
  entry or a prose ellipsis is not a table, and an intervening paragraph breaks a row sequence.
  No table semantics are inferred.
- **Displayed formulas.** A non-monospaced line under 160 characters seeds a preserved region when
  it carries one of `∫∑∏√∂∇≈≠≤≥∞`, or when it states a relation: an `=` with a term after it, over
  at most twelve whitespace-separated words. The term after the sign is required because a font
  that prints its line-end hyphen as `=` (gpo-911-2004) ends every broken word's line in one, and
  because PDFKit reports no space after a full stop in that book a full measure of prose counts
  twelve words (#57). An equation prefix that genuinely ends in `=` is preserved by
  `FractionRegionDetector`, which has its painted bar as evidence. The line's web addresses are
  removed before it is measured, because a query string is not a relation: a word holding `://`,
  opening `www.`, or joining a `name=value` pair after a `?` or `&` is an address, and a note that
  cites one no longer seeds a crop (#227).
- **Thin rules.** A painted rule at most 6 pt high and at least 12 pt (and three times its height)
  wide, measured after `GraphicsReader`'s two-point padding, is a typographic separator rather than
  a figure. Such a rule seeds no region when it underlines one text line — it lies within that
  line's horizontal extent and between its foot and half its height — and the underlined line keeps
  reflowing; an underlined word inside a paragraph is decoration (#229). A rule that carries a
  fraction (compact, word-free terms directly above and below) keeps the terms it touches; a rule
  inside a short word-free line, such as a vinculum or an exercise bar, keeps that line; a rule
  clear of every line, such as a running-head rule or a box, stays an isolated graphic; and a row of
  at least three header underlines, or one short piece underlined whole away from the left margin,
  over at least three tightly leaded rows carrying numbers, is a borderless table
  (`TableRegionDetector.underlinedColumnRegions`) preserved as one region (#36).
- **Region expansion.** A seed's crop admits only the text lines it captures and the other pieces
  of those lines' rows, never a chain from line to line: PDFKit's line rectangles include leading
  and so overlap on tight leading, and chaining absorbed whole columns. A thin rule captures only
  text it strikes through — its midline inside the middle half of the line's rectangle — not the
  rectangles above and below it. The crop is then trimmed away from any line it merely touches,
  keeping the seed's ink (for a thin rule, its one-point stroke), because layout removes every
  intersecting line from the reflowed prose; a line the crop cannot be trimmed away from is
  admitted instead, and a thin rule left with nothing admitted yields no crop at all (#36, #229).
- **`FractionRegionDetector`.** Short horizontal painted bars with compact mathematical terms
  above and below, optionally with a nearby equation prefix, are preserved together in one image.
  Long rules, prose, code and connected table grids are left to existing handling; whole-line
  expansion supplies the crop margin once, and detection does not enlarge complete regions again.
  Arbitrary mathematical structure is outside this detector.
- **`NumberedNoteDetector`.** A top-margin chapter-note heading, consecutive indented note starts
  and consistent dedented continuations must agree before a bounded native endnote paragraph
  repair applies; ambiguous layouts keep spatial reconstruction. This is layout, not
  reference-to-note ownership.
- Preserved regions, page fallbacks and cropped figures are images: cropped text is neither
  reflowable nor accessible as text, and the generic image description names the source page
  rather than inventing a description of the picture.

Evidence: [rule-and-url-seeds](../measurements/rule-and-url-seeds/record.md),
[preserved-region-regressions](../measurements/preserved-region-regressions/record.md),
[fractions-and-invisible-text](../measurements/fractions-and-invisible-text/record.md),
[numbered-notes](../measurements/numbered-notes/record.md) and its
[recheck](../measurements/numbered-notes/recheck/record.md),
[image-regions](../measurements/image-regions/record.md).

## ChapterBoundaryReader

A conservative bookmark scheme is admitted: at least two root-level English `Chapter 1 …`
through `Chapter N …` entries with consecutive Arabic numbers and strictly increasing local
destination pages (direct or named destinations and GoTo actions; missing, remote, duplicate or
backward destinations reject the sequence). Nested, Roman-numbered, unnumbered and other-language
schemes keep ordinary packing. Each candidate must also show its chapter number and full title
on adjacent native lines among the first six lines in the upper half of its page, matching after
whitespace and case normalization and permitting a publication-name prefix; freshly recognized
pages and exclusively invisible image-backed text are rejected. Matching candidates become
chapter boundaries: their source markers stay standalone, cross-boundary paragraph joins are
prevented, and the writer flushes the preceding spine document before each. Bookmarks do not
manufacture headings or links.

Evidence: [chapter-boundaries](../measurements/chapter-boundaries/record.md).

## PageRasterizer and PageAssetWriter: images

- Rasters are rendered from the original page at the requested DPI (default 180), each full page
  or crop independently bounded by the pixel ceiling (12 million by default; a 1-million control
  reduces an FAA page to about 106 DPI while a small crop still reaches about 239 DPI).
  Whole-page crop and rotation are computed in page units and scaled to pixels explicitly;
  annotation drawing compensates for PDFKit's own crop/rotation transform.
- Only annotations a reader of the source page would see are drawn: an annotation whose `/F`
  flags set Hidden (bit 2) or NoView (bit 6) is skipped (#170). PDFKit's `shouldDisplay` is its
  own display switch; on macOS 27 it reports false for NoView but true for Hidden, so a hidden
  field or review layer would otherwise be painted into an image that stands in for the page.
- `fullPageImageEncoding` (references and required fallbacks) and `regionImageEncoding` (crops)
  each choose PNG, JPEG at a quality, or `.smallest`, which encodes both and keeps the smaller
  file (PNG on ties) at the cost of a second encoding pass; selection retains at most one raster
  and two candidate files, and the rejected candidate is deleted. The asset registry records the
  actual format; the writer uses matching extensions and media types. Quality is an ImageIO
  setting, lossy even at 1; encoding never resizes or validates OCR.
- `maximumOutputBytes` is checked against cumulative image bytes during reconstruction and all
  entry bytes during packaging; the library never drops images or lowers quality to fit.
- Reference policy: `.automatic` adds a source-page reference for fresh OCR, inherited text over a
  page-sized graphic and visible annotations; `.always` on every reconstructed page; `.never`
  omits supplementary references (`referenceImageOmitted`: "Client policy omits a supplementary
  source-page image recommended for this page. Compare the source PDF for visual content and
  transcription accuracy.") without suppressing the OCR, unverified-layer or annotation warnings.
  Rotated, unsupported or unrecoverable pages keep one required full-page fallback under every
  policy (`pageImageFallback`; `.always` does not duplicate it). Visible annotations report
  `annotationsNotConverted`; link and form interactions are not reconstructed.

Evidence: [raster-dpi](../measurements/raster-dpi/record.md),
[warren-image-encoding](../measurements/warren-image-encoding/record.md),
[client-options](../measurements/client-options/record.md),
[noaa-output-policies](../measurements/noaa-output-policies/record.md).

## EPUBWriter, SpinePacker, EPUBTextEncoder

- Output is EPUB 3: XHTML spine documents, a stylesheet, metadata, flat heading navigation, a
  source page-list, an OPF 3.0 package and the required first, uncompressed `mimetype` entry.
  `EPUBTextEncoder` escapes source markup (raw text is escaped before inline elements are added
  inside `<pre>`), excludes the control characters XML 1.0 forbids, and emits page markers and
  figure markup; source scripts, attachments, actions and remote resources are never copied.
- `SpinePacker` checks the complete UTF-8 body against a 60,000-byte target before admitting a
  block. A standalone source-page marker travels with the following content; inline markers keep
  their exact location. A short trailing run of headings, at most 6,000 bytes (a tenth of the
  target), moves with its navigation entries into the next document instead of ending the
  previous one, and stays with an oversized block that follows it; no spine document but the last
  may end with such a run. Other oversized paragraphs, headings, code blocks or figures occupy
  their own document unsplit. A validated chapter start always begins a new document, and the
  same subdivision applies within the chapter. This is a soft body target excluding metadata, an
  EPUB packing policy, not a memory ceiling or a promise that spine files are book chapters.
- Each block is serialized once, as it arrives from the pass that made it; a document is written
  as it closes; only the current body, the navigation lists and the asset registry stay in
  memory. Navigation, package metadata and the archive are built when the stream ends, and
  progress reports the archive entries.

Evidence: [spine-packing](../measurements/spine-packing/record.md),
[spine-continuity](../measurements/spine-continuity/record.md),
[large-epub-inspection](../measurements/large-epub-inspection/record.md).

## Warning codes

`ConversionWarning.Code` values, when each is emitted, and where its prose is composed
(`ConversionWarnings.warning` unless noted):

| Code | Emitted when |
| --- | --- |
| `structureFallback` | Tagged text on the page could not be matched unambiguously to native lines; or, attached to page 1, the document's structure tree was rejected (invalid, over budget or outside supported roles). |
| `ocrUsed` | Recognition replaced the page's text with at least one recognized line. |
| `ocrFailed` | Recognition threw, or succeeded and read nothing: the page became an image, the compared layer was retained, or a drawn-text page kept its crops. |
| `uncertainHyphen` | A line-end hyphen neither the vocabulary nor the lexicon could decide is retained; once per page (`HyphenRepair`). |
| `furnitureRemoved` | A repeated header, footer or folio was omitted from this page (`FurnitureDetector`). |
| `imageRegion` | Figures, tables or equations on the page are carried as crops ("Graphical regions retain source appearance as images; their internal text does not reflow."), or a source-page reference accompanies reflowed text ("A source-page reference image accompanies reflowed text to preserve all visual content."). |
| `pageImageFallback` | The page is preserved as one image and does not reflow (rotated, unsupported, unrecoverable or empty-recognition pages). |
| `unsupportedGraphics` | Unsupported or excessive drawing operations require the original page image. |
| `emptyPage` | The page's content stream draws nothing at all: no extracted text, no visible text-showing operator, no painted region (a white ground is not one) and no annotation. A blank page is still carried as an image, so `pageImageFallback` accompanies it. |
| `complexLayout` | The recursive whitespace cuts reached their depth limit before they had separated the page's content; what remained keeps the order it was extracted in (`LayoutReconstructor.ordered`). |
| `annotationsNotConverted` | Visible annotations exist: a page image preserves them (or references are disabled); link and form interactions are not reconstructed. |
| `referenceImageOmitted` | Analysis recommended a supplementary source-page image and client policy omitted it. |
| `unverifiedTextLayer` | Existing text over a page-sized graphic stands unverified ("Transcription, tables, numbers and reading order may be inaccurate."); a review signal, not an OCR confidence score. |
| `implausibleTextLayer` | An inherited image-backed layer failed the word, misread or ink test, under every policy (`TextLayerPlausibility.message`). |
| `implausibleRecognition` | Recognition of a page did not read as English and was discarded (`TextLayerPlausibility.recognitionMessage`). |
| `damagedTextEncoding` | A font without a usable Unicode mapping is present and the words fail the English statistics; the message is emitted after the recognition outcome is known and says whether recognition replaced the text, the text is retained, or it was discarded and the page became an image (#221). |

Messages whose tail depends on `referenceImages == .never` say "read the source PDF instead" in
place of the accompanying page image.

## Limits

PDF structure is ambiguous. The synthetic suite and the corpus do not establish general
textbook fidelity: untagged borderless tables, arbitrary equations, complex magazine layouts,
footnote relationships, vertical and right-to-left reading order and damaged font encodings
still need broader qualification. The detectors cannot identify every difficult region. Fonts,
original colours, full tagged-PDF semantics, links and interactive elements are not reproduced.
Smaller graphics and undetected scans can still carry transcription errors. Review warnings and
compare the source before distributing a derived book.
