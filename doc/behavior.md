# Behavior specification

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
- A locked document converts when `ConversionOptions.password` unlocks it, and throws
  `encryptedPDF` when it does not (#252). The password is applied wherever the conversion opens
  the file — the page window's reopen, the outline read and the structure tree each open it
  themselves — and reaches no report, warning, progress event or staged file;
  `ConversionOptions.Password` redacts itself in `description`, `debugDescription` and its mirror.
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
  callbacks, OCR, graphics work and writing. A canceled waiter can return while another
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
  never establishes a superscript. A run holding no non-whitespace character takes no script
  style however its metrics place it (#273): a raised space is a space, `<sup> </sup>` claims an
  inline script over nothing a reader can see raised, and the space itself is written where the
  page set it. Whitespace *inside* a run that also holds a glyph is that script's own. Evidence:
  [whitespace-only-inline-scripts](../measurements/whitespace-only-inline-scripts/record.md).
- Emphasis is read the same way. A run holding no non-whitespace character takes neither italic
  nor bold from its font, so `<em> </em>` and `<strong> </strong>` are never written over a space
  (#278). The run itself is kept — the page set that space and the words on either side need it —
  and where such a run stands beside prose of the same style it merges into it. An underline is
  judged the other way and survives: a rule the page paints under a space is ink the page really
  put there, not a font's claim (#235). Evidence:
  [whitespace-only-emphasis](../measurements/whitespace-only-emphasis/record.md).
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

- **A margin rule an inherited recognition read as letters (#264).** Project Blue Book paints a
  rule down the outer margin of its pages, and the layer it inherited read each segment of it as a
  capital `I` set in 30-point type. PDFKit puts that letter in the same line as the type beside it,
  so a 7.8-point line came back in a 31.5-point box at a 31.5-point size, overlapping the rows
  above and below: on page 7 the wrap `I South Farwest Region . 54` (`y[645.9..677.4]`) sorted
  *above* the entry it continues, `Figure 38 …of the` (`y[656.8..663.8]`), and no join or ordering
  rule could reach it, because the geometry was wrong before reconstruction began. This is not the
  thin-rule ownership of #207, which reads a rule the page *paints* against the row it strikes: a
  recognized rule is painted nowhere, so by the time any ownership rule runs there is no rule left
  to own.
  A **mark** is a character that is one of `I`, `l` or `|` — the glyphs a recognition offers for a
  vertical rule, and no others, however tall they stand — drawn at least two and a half times as
  tall as the page's own characters and at least twice as tall as it is wide, standing in the outer
  twentieth of the page on one side. **Four marks sharing one column are a rule**; three are not,
  because a display initial, a mathematical bar and a stray recognition are each one mark and none
  of them repeats down a margin. A line a rule reached is measured by the characters that remain
  after its marks are cut, together with the space a recognition sets between a mark and the type
  beside it, which carries the mark's size and would otherwise state it for the whole line; a line
  the rule drew and nothing else carries no text and is dropped. A line holding no mark can still
  be damaged, because PDFKit gives every piece of a printed row the height of the tallest piece in
  it — page 7's `56` stands in `y[632.6..637.9]` and was reported at `y[610.4..641.9]` — so a line
  sharing its row with one the rule reached, whose reported box is at least twice as tall as the
  characters it holds, is measured by those characters too. **A line genuinely that tall keeps its
  box**, because its own characters are that tall. A mark read *inside* a line is not a margin
  rule's, since nothing stands between a margin and the type beside it, and such a line is left
  exactly as it was read.
  The character rectangles come from PDFKit itself: `characterBounds(at:)` is indexed over the
  page's characters without the separators the reading synthesizes between rows, which is the
  offset the lines' own strings reach laid end to end. A page whose lines run past the characters
  it declares supplies none. Only a page whose lines already show a rule glyph at one end, in the
  outer twentieth, on four lines or more is measured character by character at all; of the
  twenty-four cached sources only Blue Book's pages are, and of those only the 241 that draw the
  rule are changed. Evidence:
  [margin-rule-read-as-letters](../measurements/margin-rule-read-as-letters/record.md).

- **A row of two columns PDFKit merged across the gutter (#270).** The 9/11 report sets two flight
  timelines side by side on physical pages 50 and 51, each under three heading rows. PDFKit reads
  the first and third of those rows as two lines, one per column, and hands the second back as a
  single line spanning both — `(AA 11)             (UA 175)` at `x=39.66` over `199.63` points,
  where the rows above and below are read apart at `x=39.66` and `x=195.67`. A line that bridges
  the gutter cannot be separated by any whitespace cut downstream, and it stands on the left
  column's own edge directly above the left column's route, which the column-and-leading test then
  joins to it: the book read `(AA 11) (UA 175) Boston to Los Angeles` and stranded the right
  column's route. The page's own shows do not divide such a row — `NativeSpacingReader` returns the
  whole heading row as one text-showing operation, with the gutter inside its own advance, so the
  ink `TableReader` reads (#210) is one unbroken range and its corridors find nothing. The division
  comes from the characters, where the box is formed, for the same reason #264's does.
  A line is cut where **three rows agree on two column edges**: the line stands alone in its
  printed row, the printed rows directly above and below it each hold exactly two pieces, those
  two rows state the same two left edges to within a point, and the line begins on the first edge
  and reaches past the second. Each step between the three rows is a leading, no more than twice
  the taller row's height, so three rows of a page at large are not a group.
  **The three rows are the whole of what the page states there.** Neither the row two above nor the
  row two below may stand on the same pair of edges: where a page states its columns over four rows
  or more, the reading already holds divided pieces for them and the ordering rules can see those
  columns, and dividing one more row changes how the whole page is read. The 9/11 report's own
  table of names on page 451 sets twenty-three rows on 44.70 and 152.70, of which PDFKit merges
  one, and dividing that one used to turn a list of names with their offices into a paragraph of
  names followed by a paragraph of offices: the undivided line bridging the gutter was the only
  thing keeping the page from being cut there. That cut is now refused on its own geometry — a
  stack of cells standing on the rows of the lines beside them is not a column of the page — so
  the page reads row by row whether or not its merged row is divided, and this condition no longer
  carries it (#283).
  **What refuses the cut is the white.** A line the page genuinely sets across both columns — a
  headline, a caption — has the same shape, and keeps its reading, because it runs its words
  *through* the gutter: the white at the column edge is the space it sets everywhere else. The cut
  is made only where the second edge falls in white at least twice the line's own characters are
  tall and at least three times the widest white elsewhere in the line — 118.37 points against
  4.50 on page 50. A line whose characters PDFKit reports out of the order they stand in states
  nothing about its columns and is left alone, and so is one with anything printed in the white,
  so nothing that prints is ever cut away. The white is read from the line's **ink**: its spaces,
  and any character the page gives no width, are not type.
  Each piece keeps PDFKit's own outer edge, its own inner edge, the row's baseline and height, and
  its half of the styled text; a line a repair rewrote between the reading and the cut is not cut.
  Across the twenty-four cached sources exactly two lines are cut, the two the issue names.
  Evidence:
  [flight-label-row-cut-at-the-gutter](../measurements/flight-label-row-cut-at-the-gutter/record.md).

Evidence: [pdfkit-concurrency](../measurements/pdfkit-concurrency/record.md),
[pdfkit-gate-drain](../measurements/pdfkit-gate-drain/record.md),
[extraction-cancellation](../measurements/extraction-cancellation/record.md),
[pdfkit-repeated-conversions](../measurements/pdfkit-repeated-conversions/record.md),
[native-line-boundaries](../measurements/native-line-boundaries/record.md),
[drop-cap-order](../measurements/drop-cap-order/record.md).

- **List markers and line size (#183).** A line's size is its first character's, and a list
  marker is drawn at whatever size the page likes, so a marker larger than its item states the
  marker's size for the whole line: the Fed's page 58 sets a 10-point bullet over 8-point text on
  14 lines, and IRS Publication 596 sets one large enough that five bulleted sentences were read
  as headings. Where a line opens with a marker glyph and a space, and that marker is drawn larger
  than the text after it, or smaller than it, the size comes from the text instead (#254).
  Nothing else at the start of a line is a marker: a drop cap, an opening quotation mark and a
  contents line's leaders keep the size they had.
  Reading the smaller marker as well is what promoted IRS Publication 596's four starred
  footnotes into headings while the rule read one direction only. What stops that is the reading
  of the line rather than a bound on its size: **a bulleted line is not a heading**, whatever
  size its text is set in, because a page that draws a bullet has said the line belongs to a
  list. Only the glyphs `• * − – — -` followed by a space count; a numbered or lettered marker is
  not evidence of the same kind, since `1. Introduction` is a heading in many books.
  The rest of such an item carries no marker at all, because the marker is on the line above it,
  so the page states the relationship in the indent instead: **a line hanging under a bulleted
  line is the rest of that item**, and is no more a heading than the item is (#256). The evidence
  is the page's own hanging indent — the line opens with no marker of its own, is set at the
  marked line's size, stands directly beneath it within the leading a broken item is joined on,
  and sits between 0.8 and 3 of its size in from that line's left edge, the window a numbered
  note's continuation is read on. The marked line must also fill a measure, at least twelve of
  its own sizes wide, because a line that wrapped is a line that ran out of room: a short
  bulleted item above an indented one is two items. IRS Publication 596 sets the starred
  footnotes under its EIC table at 8 points over a table whose body is 5.69, so on four of its
  pages the footnote that wrapped reached the page's heading threshold on size alone. The line
  keeps its own block and its own words; only the heading reading goes.
  A page also keys notes to marks of its own choosing, and enumerating the glyphs would say
  nothing about why one is a marker, so the page is asked instead: **a line is a note, not a
  heading, where it opens with a glyph the page keys its own material to** (#259). Three things
  the page states together — the line opens with one character that is no letter and no digit,
  then a space, then text, the shape the size correction above already reads; the same character
  is printed *by itself*, higher up the page, as the reference the note explains; and the line
  filled its measure, at least twelve of its own sizes wide. The search covers everything the
  page printed, not only the lines that still reflow, because the material a note is keyed to may
  be inside a crop. IRS Publication 596 prints `★` alone in two column headers of each EIC table
  page and explains it in the band beneath, `★ 如果您的报税身份是已婚分别申报…请使用此栏。`, at
  8 points; on ten pages that legend read as a heading. A heading opening `§` or `★` on a page
  that keys nothing to it, and a short decorated heading beneath a star the page does print, keep
  their readings. The rest of such a note, hanging under it, is read as the rest of a bulleted
  item is.
  Evidence: [list-marker-size](../measurements/list-marker-size/record.md),
  [smaller-marker](../measurements/list-marker-size/smaller-marker/record.md),
  [hanging-continuation](../measurements/list-marker-size/hanging-continuation/record.md),
  [keyed-mark](../measurements/list-marker-size/keyed-mark/record.md).
- **East Asian text (#42).** Chinese, Japanese and Korean set no space between the characters of
  a word, and a justified line stretches the gaps between characters rather than between words.
  Two spacing rules were measured on Latin text and do not hold here. A gap between two
  characters drawn one em wide is never read as a missing word space, however wide it is, so a
  justified line is not broken into words. A space the extracted text layer already carries
  between two Han ideographs (`CJKText.isIdeograph`: the Unified blocks, Extension A and the
  compatibility ideographs) is removed with the attributes either side of it kept, which restores
  a heading the page letter-spaces one character at a time. The narrower ideograph test, not the
  one-em test, decides the removal: a source may legitimately set a space after `。` or `，`
  where a run-in heading ends, and every boundary with Latin text keeps the source's own spacing.
- **Right-to-left text (#41).** A page written right to left is read as one: `ArabicText` counts
  the Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan and Mandaic letters of the page's own lines
  against their Latin letters, and a page carrying at least as many of the first is right to left.
  Nothing below runs on any other page, and nothing consults the declared language: the page's
  own script decides, whether the book converts at the default `en` or, as the corpus lane
  converts the Arabic guide since #293, declared `ar`. Such a page hands back its Arabic in the order it
  was written and its numbers in the order it was painted, because PDFKit inverts the page's
  layout without the two rules of the bidirectional algorithm that fold a separator into the
  number beside it. Two orders are put back:
  - **A number or an identifier whose separators were resolved right to left.** Two or more runs
    of Latin letters and digits joined by single ES or CS separators (`+ , - . / :`, the Arabic
    comma and the dashes) are one chain, and a chain with a digit directly beside one of its
    separators is restored to the order the page set it in, each run keeping its own order:
    `551-I` becomes the form `I-551`, and `3676-870-800-1` the telephone number `1-800-870-3676`.
    A chain of words alone is resolved the same way by the page and by the reading and is left
    exactly as it was read, so `www.uscis.gov/uscis-elis` is untouched.
  - **A line with no right-to-left letter of its own**, which the reading inverts with the wrong
    base direction and hands back in the order the page painted it. Such a line is restored only
    where its own brackets close before they open — a closing bracket standing where nothing has
    opened, which is what a mirrored right-to-left parenthetical looks like read left to right.
    The line is reversed and each left-to-right island in it is turned back, so `.)USCIS(` becomes
    `(USCIS).`.

  Both reorderings are permutations of the line's characters and carry every attribute with them.
  A run of right-to-left letters is never an inline superscript or subscript, however its metrics
  place it: shaping shifts single letters off the baseline inside a word the page never raised
  (page 21 raises the `ا` of `إذا` by 2.34 points on a twelve-point body, against the 1.44 an
  inline script needs). A digit or a Latin letter raised in the same text still is one. Evidence:
  [right-to-left-runs-and-rows](../measurements/right-to-left-runs-and-rows/record.md).

## Content-stream readers

`ContentStreamWalk` gives every reader a budget of 100,000 operations and 128 saved graphics
states; a reader chooses through `Options` whether `q`/`Q`/`cm` inside a text object, a nested
`BT`, a stray `ET` or a positioning operator outside a text object disqualifies the page, whether
`Tf` is reported, a cap on `TJ` array elements, and how `'` and `"` are treated. `AnchorMatcher`
matches a show origin to a native line with a 0.75 pt tolerance and caps anchors and lines at
10,000 each and rectangle comparisons at two million per page; exhausting a cap falls back to
spatial reconstruction rather than partial results.

- **`NativeSpacingReader`.** Repairs a PDFKit word boundary only where a supported text-show
  operation contradicts it. It *removes* a space when a Type3 `TJ` array places a tiny negative
  adjustment there, with the font's one-byte `ToUnicode` map, text and placement matching, and
  where two shows continue one number (#274, below). It
  *inserts* the space the source draws without a space glyph (#43/#110, #119, #128, #120), on
  pages it can model completely: `Tc`, `Tw` and the text matrix are tracked (a show that draws
  straight after another continues the cursor by the previous show's own advance, spacing and
  adjustments included); `Ts` and `Tr` must be 0 and `Tz` 100; a `gs` that selects a font, a
  missing resource, `'`, `"`, an inline image, rotated pages and work beyond the caps (10,000
  font selections, 256 distinct fonts parsed, 10,000 shows, 4,096 codes or `TJ` elements per
  show, 8,192 code units per line) reject the page's evidence. Rotated or mirrored text supplies
  no evidence but does not disqualify the page's upright text. Simple fonts are read through a
  one-byte `ToUnicode` map (bfchar and bfrange, any number of UTF-16 code units, a two-byte
  `<0000> <FFFF>` codespace read as one byte) or, without one and outside TrueType, through
  `WinAnsiEncoding` and its `Differences`; glyph advances come from `FirstChar`/`Widths`.
  A boundary is restored when:
  - **a font change** separates two shows on one baseline (within 0.1 em) by at least 0.15 em,
    with a letter or digit on either side, or a closing `) ] , ; :` that ends a word or formula
    before a letter; 0.10 em is enough where a number is set against a run that opens with an
    English word of three letters or more, which is how a page sets `8cent stamps` and
    `Subtract 5from both sides` and not how it sets the same book's `30qpr` (#120);
  - **a note reference**, a show of one to four digits at most 0.8 of the next show's size and
    raised 0.15 to 0.6 of it, precedes a capital or opening quote at a word gap;
  - **`sameFontWordSpace`** reads a `TJ` adjustment between two glyphs of one show, in a producer
    that justifies with character or word spacing, as min(adjustment, adjustment + `Tc`) in em:
    0.066 em before a letter, digit or `(`, and 0.005 em before an overhanging `A T V W Y` or an
    opening quote that follows a lowercase letter or punctuation; never above 1 em, never inside
    a number or time (`3.5`, `8:46`), never beside a mathematical letter (U+1D400–U+1D7FF,
    U+2100–U+214F), never where a chained initial (`C.|A.`) explains the gap, and never on a
    boundary beside a one-glyph string whose other side is also a word gap (letter-spaced type);
  - **a character-spaced column gap** of at least 0.5 em set by `Tc` splits a two-glyph show;
  - **`closesNumber`** takes a space back where the page draws one number in two shows (#274):
    two shows of one font at one size on one baseline (within 0.1 em), the first ending in a
    digit and the second opening with one, at a positive gap narrower than the space character
    that font itself draws (`Widths[32]`, less any `Tw` that narrows it). FAA page 416 sets the
    NDB table's `25` as `(       2)Tj … (5)Tj` at 1.34 pt over a 10-point size — 0.134 em against
    a 0.25 em space — and the row arrived as `MH Under 50 2 5`. This is the only boundary the
    corpus closes: the nearest digit-to-digit boundary it leaves alone is that book's page 458
    chart columns, at 3.6 times their own font's space. A font that states no width for the space
    character, or states zero, states nothing here — that is every TeX font of Wallace's algebra,
    which draws no space glyph at all — so #119's constraint holds by mechanism and not by
    threshold. Only two digits close: a number against a word is what the font-change rule
    weighs, and a period or comma against one is a contents leader or a sentence.
  - **`sentenceSpace`** finds sentence punctuation (`. , ; : ? !`, optionally behind closing
    quotes or brackets) after a letter, digit or closing bracket, before a capital not followed by
    a period or an opening quote before an alphanumeric, at a gap between -0.15 and 1 em: the
    kerned boundaries where no gap remains. An apostrophe, an ellipsis, an address (`/ @ = \`,
    `www`), a mathematical letter, a number that opens the show, and an initial before a
    capitalized abbreviation ending in a period are not sentence boundaries.

  The boundaries are applied only where the shows and PDFKit agree. `NativeSpacingOwnership`
  splits the line into its maximal agreeing segments — resynchronizing on twelve matching
  characters, skipping at most 64 either way and at most 64 times per line — and applies a
  boundary only where the characters on both sides of it matched inside one segment, so a
  boundary inside a disagreeing region or against its edge is dropped (#139 item 1). Twelve,
  because eight recurs inside one printed row: the 9/11 appendix's
  `Abu Bara al Yemeni (a.k.a.Abu al Bara al Ta’izi` has `Bara al ` in both halves, and the walk
  resumed in the wrong one (#120). A show whose text the reader cannot decode is a hole in the
  source's reading rather than a reason to discard the line, and nothing is read across the hole:
  one radical on Wallace page 120 used to discard every boundary of
  `5− 2x 11 Subtract 5from both sides`. A show whose origin lies in more than one line's rectangle
  is a hole of the same kind, in every line that holds it, rather than a reason to discard those
  lines (#258): a line carrying a superscript, an exponent or a stacked fraction gets a PDFKit
  rectangle as tall as what it carries, so it overlaps its neighbors' rectangles and holds their
  origins, and Wallace's `Convert 8cubic feet to yd3` — one rectangle 69 points tall over eight
  shows of the fraction rows inside it — refused the twelve shows that spell it exactly. A show
  whose origin another line's rectangle alone holds still reaches this line when its baseline lies
  inside the line and its glyph advances cross the line's span, which is how one printed row
  PDFKit split at a wide gap is repaired in the half that holds each boundary. Explicit spaces,
  genuine word-size gaps and style attributes are kept, a boundary PDFKit already spaces inserts
  nothing, and a line whose every show is held by another rectangle too rewrites nothing.

  A boundary the walk cannot reach is still applied where **the line can hold its show in only one
  place**: the show's own marks stand at exactly one position in PDFKit's reading of the line,
  stepping over PDFKit's own spaces, so there is nothing to align and no anchor is needed (#260).
  This is read per show, so a line the walk owns keeps everything the walk gave it. A show of one
  mark is never placed, because one character standing once in a line is a coincidence the line is
  too short to rule out, and neither is a show carrying whitespace of its own, which would not
  line up mark for mark. Two lines of *Beginning and Intermediate Algebra* need it and no other
  book in the corpus moves: page 224 reads seven source characters against an anchor of twelve, so
  `resynchronize` runs out of source at the first hole, and page 223's line holds the second digit
  of a `66` the page split across two rows, so the walk opens on that coincidence and
  resynchronizes onto the boundary itself.

  A *removal* is owned differently, because the defect it answers has the opposite shape: a page
  sets a table row by carrying the cursor from cell to cell with runs of space glyphs and PDFKit
  reports one space for a run, so on such a row the source draws the whitespace the extraction
  does not, and the segmented walk — which skips only the extraction's own spaces — resynchronizes
  on nothing (between `MH     Under 50         25` and `MH Under 50 2 5` the longest anchor is the
  nine characters of `Under 50 `). `closedSpaces` therefore owns a removal whole-line and blind to
  whitespace on both sides: every non-blank character the shows draw must be the next non-blank
  character PDFKit read, in order, with nothing left over either way, the closure must have no
  whitespace beside it in the source, and exactly one space at it in the extraction. That is
  stricter than the segmented walk, not looser, and it reaches no insertion (#274).
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
  rectangles for tagged-PDF association. Unknown glyph-cursor advancement, missing or duplicate
  MCIDs, ambiguous geometry and incomplete groups keep spatial reconstruction. Origin matching is
  association evidence, not font decoding or proof of the author's semantics.
- A `Do` is followed into a Form XObject, under the form's own `Matrix` and resources and inside
  the implicit `q`/`Q` the operator carries, and the page is charged what the form actually
  shows: a form that shows no text places no line and costs nothing (#241). The structure tree
  reaches a form's marked content only through an `/MCR` with a `/Stm`, and every group holding
  one is rejected before this reader runs, so a form's text describes no group that arrives here:
  inside the form an MCID names nothing, only `/Artifact` still says the content is furniture,
  and a show the form places costs the group of any line it lands in. The page is still refused
  outright when a form cannot be followed — a `Do` inside a text object, a `Matrix` that is not
  six finite numbers, an XObject that is neither `Image` nor `Form` or has no subtype at all,
  nesting past 12 forms, a stream the scanner cannot read or that spends the page's operation
  budget, a form whose own `q`/`Q` or `BT`/`ET` do not balance, and a form that would close
  marked content its caller opened or leave a section of its own open — and when a form shows
  text this reader cannot place outside an `/Artifact`, which could have drawn on any line.
- A show whose origin this reader cannot derive (no positioning operator, or a leading non-zero
  `TJ` adjustment) costs exactly what it could have described: nothing inside an `/Artifact`,
  which carries no structure; the enclosing MCID's group inside a marked section; and the whole
  page outside marked content, where the text could belong to any line (#67). `/Artifact` is
  inherited by nested spans; an explicit MCID always names its own content.
- A show drawing only spaces places no line and costs no group, while its MCID still counts as
  shown. A code is a space only where the font's `ToUnicode` map gives a one-byte `bfchar` entry
  for exactly U+0020, or, with no map, where a simple font names `WinAnsiEncoding`,
  `MacRomanEncoding` or `StandardEncoding` and the code is 32. Ranges, multi-character
  destinations, `usecmap`, maps over 65,536 bytes, Type3 and composite fonts give no space codes
  (#91). Space codes are read once per font dictionary, for at most 256 fonts per page.
- Invisible render mode (`3 Tr`) is judged where text is shown: inside an `/Artifact` it costs
  nothing; anywhere else it refuses the page, since invisible text over a scan is inherited
  transcription, not what the tags describe. Clipping modes (4–7) still refuse the page (#91).

Evidence: [native-label-spacing](../measurements/native-label-spacing/record.md),
[structure-tags](../measurements/structure-tags/record.md),
[tag-gate-scoping](../measurements/tag-gate-scoping/record.md),
[form-xobject-tag-gate](../measurements/form-xobject-tag-gate/record.md).

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
  invalidates an incomplete group. Two validated paragraph identities that differ prevent a
  heuristic cross-page join; one identity against a page that applied no tags does not, since that
  page states nothing about where its last paragraph ends, and the geometric rule decides (#67).
  OCR text and unverified image-backed text never inherit tags.
- A page whose tags never name a heading has not stated that its display lines are not headings:
  there, a line the page's own typography reads as a heading keeps that reading and its tag is
  not applied to it. Where the page's tags do name a heading, every role they give is believed
  over visible typography, as before (#67).
- One exception, where a page's tags contradict themselves: a paragraph-tagged group is read as a
  heading where the same page's tags call a line of that exact type size (to the half point) a
  heading, every line of the group also reads as a heading by the page's typography, and the
  group holds fewer than 200 characters. It takes the shallowest level the page gives that size,
  so it nests as the sibling of the headings it is set like. One line of the group set as prose
  refuses the whole group, and a display size no tag on the page calls a heading stays a
  paragraph: size alone is not the evidence (#67).
- Where the page's own tags state nothing about a size, the **book's tags rank it** (#294,
  `HeadingRank`). The extraction pass gathers, over every native page, each display size the
  tags call a heading — a tagged heading counts only where its own page's typography reads it
  as heading-sized, so a body-size `H` on a sparse page states no display size — and a size
  ranks once at least three pages tag it, at the level the tags give it most often (equally
  often, the shallower). A style is a size to the half point and, where PDFKit reports one, a
  weight; the rank speaks only to a line of the weight it ranked. On a page whose tags name a
  heading, a paragraph-tagged group whose every line reads as a heading by the page's typography
  and whose size the page's own tags never call a heading takes the level of the largest ranked
  size not above it; below the rank's smallest size the rank has no opinion and the tag is
  believed. IRS Publication 596's cover tags `目录` a paragraph in fifteen-point type beside a
  seventeen-point `H1`; the book tags seventeen and eighteen points `H1` on six pages each and
  fourteen `H2` on five, so `目录` is an `H2`. One refusal: a display line whose nearest line
  beneath, in its own column, is set larger is a label standing over a title and keeps its
  paragraph role — the same cover's `596 号刊物` over its thirty-one-point title, and the Fed
  cover's `PUBLIC EDUCATION & OUTREACH` over its forty-point one. The rank never demotes, and a
  page whose tags name no heading is never asked it: the FAA handbook, whose tags name none, is
  byte-identical (#67, #243).
- A page whose tagged text cannot be matched unambiguously reports `structureFallback`; a
  rejected tree adds one document-wide `structureFallback` warning attached to page 1.

Evidence: [structure-tags](../measurements/structure-tags/record.md),
[pdfkit-structure-tree](../measurements/pdfkit-structure-tree/record.md),
[contradicted-heading-tags](../measurements/contradicted-heading-tags/record.md),
[document-wide-heading-rank](../measurements/document-wide-heading-rank/record.md).

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
  the drawn-text test below can ignore a photograph's texture (#176) and reconstruction can tell
  the artwork a crop cannot be trimmed away from (#239). They are carried on the page, so both
  passes see them.
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
  `en-*`) are judged. No dictionary download, network or model is involved. This signal is also
  met, whatever the words say, when the page's replacement characters plus the glyphs
  `GlyphIndexDecoder` read but the page's lines did not take exceed `max(2, characters / 50)` —
  the same share `PageEvidence.lacksReadableText` already allows.

Example: the Census report's LaTeX pages render correctly but extract with every letter shifted
by three ("Two data files were used." extracts as "Wzr gdwd ohv zhuh xvhg1", its dropped
fi ligature included; the synthetic Type3 fixture that reproduces the mechanism extracts
"Wzr gdwd ilohv zhuh xvhg1"), because their Type 1C fonts use names such as `G108` without a
`ToUnicode` map.

Effect: the page is an OCR candidate under every automatic policy and `.always`, recommends a
source-page reference, and contributes no words to the hyphen-repair vocabulary. `.never` keeps
the unreadable text.

Evidence: [census-rrs2002-01](../measurements/census-rrs2002-01/record.md).

## GlyphIndexDecoder: reading an index-named font from the document's own words (#143, #226, #237)

Nothing in such a file states a character. The embedded CFF program names its own glyphs `G<n>`
exactly as the `Differences` array does, its built-in encoding places `G<n>` at code `n`, and the
descriptor's `CharSet` repeats the names, so the index is a slot in the font program Distiller
read, not a letter. The offset from slot to character is therefore read from the document's own
words, per font, and never assumed.

**Fonts.** A Type1, TrueType, MMType1 or Type3 font with no `ToUnicode` whose `Differences` names
at least half its codes by index (`TextEncodingCheck.isIndexStyleGlyphName`), with at most 1024
`Differences` entries and 64-character names. A font is keyed by its subtype, `BaseFont` and its
whole `Differences` array, so one font shared across pages or reopened in another document is one
font. At most 256 such fonts and 4096 pages per document; at most 500,000 glyphs and 50,000
distinct words per font.

**Words.** Every show of such a font across the document is split into words wherever a gap of at
least 0.15 em stands before a glyph. A gap is the character spacing (`Tc`, in ems of the selected
size) that the `TJ` adjustments do not cancel; a show begins a word. Census's body kerns measure
0.00 em and its word gaps 0.43 em, and its letter-spaced headings set 1.10 em of character
spacing between two glyphs of one string while canceling it with a +1120 adjustment between the
others, which is how `1Introduction` recovers its space. A page drawn with `'` or `"`, whose own
word spacing this does not model, supplies no evidence at all.

**Offset.** Every offset in −255…255 under which at least half the font's glyph occurrences read
as ASCII letters is judged with #38's embedded English tables, reading index `n` as code
`n − offset`: at least 20 words of two letters or more, 10 of them four letters or longer, a
function-word rate of at least 10%, a rare-bigram rate of at most 10%, at least 50% lower-case
letters, at least one capitalized word, and at most 2% of words with a capital after a lower-case
letter. A font is decoded only when exactly one offset passes. The lower-case and capital rules
are what separate an offset from its case-swapped twin 32 slots away; the long-word rule is what
keeps a math font's two-letter variable runs off function words.

**Characters.** A decoded font's codes read through TeX's Cork (T1) table when its `BaseFont`,
subset tag aside, matches `^(dc|ec)[a-z]+[0-9]+$` — the name that states the encoding — and
otherwise through the letters, digits and `!#$%&()*+,-./:;=?@[]` that TeX's OT1 and T1 and Adobe's
Standard and WinAnsi all place at the same code. Cork's accents (0–12) and its compound-word mark
and per-mille zero (23, 24) state no character and stay undecoded. A `Differences` entry with an
ordinary glyph name (`space`, `quoteright`, `fi`) states its own character whatever the offset is.

**Family corroboration.** A Cork-named font whose own words are too few for any statistics takes
the offset that at least two other independently decoded Cork-named fonts of the same document
agree on, provided that offset states a character for every one of its codes. That is the whole of
the relaxation: `dctt10075` draws one e-mail address in 24 glyphs while `dcr`, `dcti` and `dcbx`
establish +3 from thousands. Nothing else inherits an offset, and the `cm` math fonts in
particular do not — the document disagrees inside that family, `cmmib` sitting three slots on from
`cmmi`.

**Line repair.** A PDFKit line is rebuilt from the index-glyph shows whose origin lies in its
rectangle and in no other line's, in drawing order, and only when those glyphs spell what PDFKit
read: every non-blank character of the line must be the character PDFKit reports for the next
glyph in order (its index as a code point, for an index in 33–126 or 161–255 under a one-letter
glyph-name prefix), and every glyph must be placed. A glyph PDFKit reports as nothing — a ligature
— is inserted where it is drawn, after an adjoining space when its own gap opens the word. A word
gap the page's character spacing hid opens a word even where PDFKit set none. A glyph whose font
the document does not establish is written U+FFFD and may stand for one character of the line or
for none, whichever completes the alignment. Anything else — a character no glyph explains, a
glyph left over, a line no show can be attributed to — leaves the line exactly as PDFKit read it.
Lines at most 4096 characters and 4096 glyphs, with an alignment budget of 20,000 steps.

**Rows split across lines (#237).** TeX sets a whole printed row as one show, and PDFKit splits
several of the Census report's rows into a line per printed column: a reference's number is one
line and its body another, a table row is one line per cell. The show anchors to the leftmost of
them, which is then offered far more glyphs than it has characters. A line whose own glyphs spell
it is still rebuilt exactly as above, and only a line they cannot is allowed to stop at its last
character and hold the rest for the **next line of the same row** — one begun at or after the
row's right edge (the rows covered so far, unioned) whose middle lies inside the row's band of
baselines. The cut may fall only where the next glyph opens a word, which is what the gap between
two printed columns always is; a glyph that continues the word the line ends with was never the
next line's to take, so the repair declines instead of cutting a word in two. Carried glyphs are
offered to that line before its own, and the line must spell all of them and its own together or
it too is left as PDFKit read it. A line that does not continue the row drops what it was handed,
and `unreadGlyphs` then counts those glyphs against the page exactly as it counts a row no line
could be found for at all. So a wrong carry costs the two lines their repair; it cannot put one
row's words on another row's line.

**Reach.** Nothing happens at all unless the document established at least one font's characters,
so a book whose index-glyph fonts stay undecoded keeps #38's path untouched. Text the decoder read
that the page's lines did not take (`unreadGlyphs`) is counted against the page above, but only
for runs of at least four stated characters that hold one of #38's function words: a table row or
a column heading holds none, and rows a detector lifts into a preserved image never reach a reader
as text.

Evidence: [glyph-index-decoding](../measurements/glyph-index-decoding/record.md).

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

- **Too few English words.** A bare `a` or `I` standing on a line that holds no other English word
  is set aside first and counts neither way (#275): alone on its line it is a ruled column, a tick
  or a tally the reading shaped like a letter, not a word. With at least 20 judged (English plus
  damaged) words left, and unless a fifth or more of the tokens are numbers (statistical tables and
  forms are not judged), fewer than half English fails. The exemption counts the numbers a page
  states, not every token that holds a digit: a misreading of a hand-written figure (`l6`, `0,3`,
  `A.Di`) holds digits too, and counting those let a table of unread ink buy its own exemption
  (#275).
- **Words misread in place (#7).** Under the same conditions, a tenth or more of all words are
  damaged words of three or more letters, or irregular capitals, that no neighboring word
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
reference. A client wanting the pre-#93 automatic behavior, recognition only of absent or
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

The same measurement answers three different questions, with three different thresholds: whether
an inherited layer transcribes the page at all (at least 7 rows and 75% of the ink uncovered,
above), whether a page's art carries writing (at least 2 rows, #176), and whether a recognition
the conversion believes left part of the page unread (at least 8 rows and 20% of the ink, below).

Evidence: the [Warren suspect-text excerpt](corpus.md#suspect-text-layer-excerpt) and its
contract `basis` in [corpus/regressions.json](../corpus/regressions.json),
[selective-ocr](../measurements/selective-ocr/record.md),
[ocr-headings](../measurements/ocr-headings/record.md),
[ocr-text-loss](../measurements/ocr-text-loss/record.md).

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
become preserved regions, each carrying how much of its grid the reading transcribed
(`TableCellEvidence`, #31); recognition marks the page for a source-page reference. Fresh OCR may
improve some errors and introduce others, lose native formatting or change reading order.

## OCRReader

- **Cyrillic look-alikes (#168).** Vision returns Cyrillic from a page this library has told it is
  English, and neither restricting `recognitionLanguages` to `en-US` nor enabling language
  correction changes it (`measurements/apple-feedback-vision-script`). A recognized token whose
  every Cyrillic character is a Latin look-alike is rewritten to the Latin the page draws, and
  only when nothing of another script survives the rewrite: `МАУВЕ` becomes `MAYBE`, and the CDC
  graphic novel's `НИН?!` and `ОКДУ` keep every character they were read with, because their `И`
  and `Д` stand where the page draws `U` and `A` and no substitution can know that. A document not
  declared English is never touched by this rule, and Russian prose reaches it as words holding
  the letters that have no Latin look-alike and keeps them.
- **Latin look-alikes in a Cyrillic document (#108).** Given `ru-RU` as its recognition
  language, Vision returns an all-capital line whose every letter is drawn the same as a Latin
  one — `КОМАР ТАРА` — as Latin, `KOMAP TAPA`, and under every language it leaves single
  capitals and lower-case letters of such words Latin inside otherwise Cyrillic tokens
  (`MOСKВА`, `моpe`); words with a letter that has no look-alike, `ЖУРНАЛ`, and lower-case
  words are read correctly ([record](../measurements/ocr-language-options/record.md)). For a
  document whose declared language is written in Cyrillic (`ru`, `uk`, `bg`, `sr`, `mk`, `be`,
  `kk` and the rest, by the script the tag names or implies; `sr-Latn` is outside it), a token
  that mixes Cyrillic with Latin look-alikes is rewritten to Cyrillic whatever its case, and a
  token that is Latin throughout is rewritten only when it is all capitals and its letters do not
  spell a Roman numeral of `X`, `C` and `M` alone, which Vision returns as the Latin it is beside
  the Cyrillic it misread (`XX BEK` becomes `XX ВЕК`). A token holding a Latin letter with no
  Cyrillic look-alike is kept whole (`NASA`, `USA`), and so is one holding `I`, `J` or `S`, whose
  look-alikes belong to Ukrainian, Serbian and Macedonian and not to Russian (`XIX`, `ISO`); a
  lower-case Latin word (`tax`) is read as what it is and kept. The risk accepted: a genuine
  Latin word set in capitals from those twelve letters alone (`TAX`, `COMPACT`) in a Russian
  document is returned by Vision exactly as the misreading is, and is rewritten with it; either
  way it renders the same. Measured on synthetic type only; no corpus book is Russian.

Vision recognizes the page image, with the declared language when the recognizer supports it,
and with language correction only when `ocrLanguageCorrection` asks for it (#108); a conversion
that used it says so in every `ocrUsed` warning, because a corrected misreading is a real word a
reader cannot tell from the page's own, and the cost that keeps it off by default is in
[conversion options](conversion-options.md#language-correction).
Uncertain words are preserved rather than dropped silently. OCR text is always reported as
transcription (`ocrUsed`: "Text is OCR transcription. The original page image preserves
unrecognized visual content."; with references disabled, "Supplementary references are disabled;
compare unrecognized visual content with the source PDF."). A recognition with no lines never
reports `ocrUsed`; see `RecognitionPolicy` above.

A recognized line's **type size is its thickness, measured across its own baseline** (#130). The
box Vision reports is axis-aligned, so for a line the page sets sideways its height is the line's
length: the CDC graphic novel letters page 17's caption down the side of the panel, and a
224.8-point box around an 8.9-point line made the page's body 225 and put the heading threshold
beyond anything printed on it. The quadrilateral around the same line carries the direction the
writing runs in, and the distance across it is the height the box would have had upright. A line
standing upright — anything within half a right angle of vertical, which covers ordinary skew —
keeps its box height exactly, so no page of upright writing moves by a hair. A banded retry scales
a thickness that runs up the page with its band and leaves one that runs across it alone.

The same offset states the **quarter turn** the page set the line at, which the line carries into
reconstruction (#263): it points the way the tops of the letters face, so a line whose offset runs
right was turned clockwise and its writing runs down the page, and one whose offset runs left was
turned counterclockwise and its writing runs up. A line inside half a right angle of upright is
upright, and so is one read upside down, whose writing still runs across the page. The turn is the
only statement of where a sideways line starts and which line is the next one down, because the
rectangle around it is axis-aligned either way; `LayoutReconstructor` and `BlockAssembler` read it
under "Columns and paragraphs" above. A natively extracted line states no direction and is upright.

### Recognition that left the page's writing unread (#116)

Vision can return success with whole paragraphs or table columns missing, and nothing in the
result says so. Every recognition is therefore measured against the page it read: the raster
Vision was given is measured with `OCRTextCoverage` against the recognized line boxes, ignoring
Vision's own table regions (a recognized table becomes a cropped image whose cells never reflow).
The reading is **incomplete** when at least `minimumUncoveredRows` (8) rows of the page's
text-shaped ink lie outside every recognized line and those rows hold at least
`minimumUncoveredFraction` (20%) of that ink. Both conditions are required: a cover whose single
uncovered row is all its ink does not reach eight rows, and a dense page's eight stray rows are
not a fifth of its ink. The check costs about 10 ms a page, roughly 2% of the page's recognition.

An incomplete reading is recognized once more in two bands, the top and bottom 60% of the page
(`retryBands`), sharing the middle fifth so that a line one band's edge cuts is whole in the
other. Lines and tables are kept from the band holding their center (`retryBandSplit`), so the
shared strip is not transcribed twice, and a table crossing the split is joined from both parts.
The banded reading replaces the first only when it leaves less text ink uncovered, with both
readings' tables ignored in that comparison, so a retry cannot win by finding a larger table
region. There is exactly one retry per page and it never recurses; nothing caps how many pages of
a document may retry, because a cap would spend itself on whichever lossy pages came first.

Whatever the retry recovers, the reading the reader is given is reported: a page whose final
reading is still incomplete raises `incompleteRecognition`, stating the share of the page's
text-shaped ink still outside every recognized line and whether the band retry had already been
tried. Only a page whose recognition became its text reports it — a reading discarded as noise or
lost to a layer comparison is not what the reader gets, and those outcomes say so themselves.

Evidence: [ocr-text-loss](../measurements/ocr-text-loss/record.md). Which pages a given Vision
build drops is not stable across compiled model sets or even across runs (#173), so the library's
tests for this behavior use canned readings rather than Vision. Coverage is measured from what a
line wrote, not from the box Vision returned: over 18,442 lines of readings their pages' layers
confirm complete, a line is 0.555 row-heights wide per character, while the Warren endnote
readings run to 0.868, so a box-derived measure reported their untranscribed remainder as
accounted for and those pages went unretried (#240). A line therefore covers `advances` times 0.6
times the page's own median row height, with a fullwidth or ideographic character counting as two,
without which 24 of the 25 sound Chinese IRS pages false-fire.

## DocumentEvidence and PageStore: what survives extraction

Extraction keeps only document-wide evidence: the hyphen-repair vocabulary (pages with a damaged
encoding contribute none; a page's margin-furniture candidates contribute their words only once the
furniture plan says the reader keeps the line, so a running head set at the body size cannot enter
the reference vocabulary a broken word's carry is judged against, #184), margin-furniture candidates, numbered-note heading pages, chapter
matches, the running character budget, the document's body size (the character-weighted
commonest size over every native page, #186), the bold label styles that recur on at least
three pages (#218) and the display sizes the book's tags call headings on at least three pages,
ranked with their levels (`HeadingRank`, #294). Each extracted page is encoded as a binary property list in the workspace
(finite, infinite and NaN doubles round-trip; equal values share a slot, so a negative zero can
reload as positive zero, and no reconstruction step reads the sign of zero), reloaded once in
order, and deleted on reload; the page directory goes when reconstruction finishes, leaving only
assets. Reconstruction emits each page's assets and blocks to the writer as it finishes them,
holding back only what a later page can still amend (`amendableTail`): the trailing block, or,
where images stand at the tail, the paragraph beneath them that a continued paragraph can still
join together with the images that join would step over (#203). The whole block list is never
resident, and the held tail cannot grow past one page's pictures, because a page that opens no
paragraph puts its own marker at the tail and a marker is not a paragraph. Model validation follows: each block is checked as
it arrives, and the checks that need the whole document — that it has blocks at all, and that
every chapter boundary reached a standalone page marker — run when the stream ends.

Evidence: [page-retention](../measurements/page-retention/record.md);
[decision 0001](decisions/0001-two-pass-page-retention.md),
[decision 0008](decisions/0008-streamed-blocks-to-the-writer.md).

## FurnitureDetector: running headers, footers and folios

- Short outermost margin rows are removed when at least three neighboring or alternating
  physical pages support the decision with stable vertical position and typography (a run of at
  least three, in a ledger of at least three pages). Evidence is local to a chapter; document
  length does not set the frequency threshold.
- A **bare number in the outer tenth of the page** is that page's own folio, and a folio is never
  a title: at most four marks, holding a digit and no letter, at either edge. *Our Flag* prints
  its page number in 8.93-point type on picture pages whose body is 7.00, so it cleared the
  heading threshold, and because that book states no table of contents of its own its navigation
  is built from its headings — fifteen of its fifty-four entries were page numbers among the
  chapter titles (#290). Refusing the title reading moves nothing in the reading order, so the
  line still reflows as text. Inside the type area a bare number is a title of a kind: the 9/11
  report sets its chapter numbers above their titles on a chapter-opening page.
- The header candidate band is the top 10% of the page (extended for the 9/11 report's
  headers) — **of the page image where the sheet carries one** (#289). A book typeset on a page of
  its own and printed centred on a larger sheet states its margin there, not on the paper: a
  Supreme Court slip opinion sets six-by-nine on US Letter, so *Loper Bright*'s text runs from
  0.21 to 0.85 of the sheet and all 210 of its running heads survived, none of them ever a
  candidate. A page is read as an image on a sheet from the **symmetry and depth of its side
  insets** — both at least a seventh of the sheet, the two agreeing within a fiftieth of it —
  which that book meets at 156.24 and 156.13 on 612 and no other book in the corpus comes near.
  It is read per page, because the evidence arrives one page at a time, and one page's symmetry
  removes nothing on its own: what goes must still repeat in the same place at the same size on
  neighbouring pages. **The row behind a head** — where a book sets its head in two rows too far
  apart to be one stacked band — is admitted where everything further out than it is already a
  candidate, it stands in the same band, and it is set apart from the body by half the white an
  outermost row must keep: a row behind a head is bounded by the head above it as well as the body
  below. One row deep, and the head only, because at the foot it would reach a line standing over
  a folio whose words the folio-offset signature then groups across pages.
  The footer band is the bottom 7% of the sheet either way, kept narrower to retain whitespace-cut behavior
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
- A leading or trailing `chapter-page` number beside a row's words normalizes the same way a bare
  folio does: the page half becomes a consistent physical-page offset and the chapter half and the
  words stay literal, so NOAA's `23-2 | US Caribbean` running foot, set at the body size in
  ordinary capitalization and worded differently on every page, forms one run (#184).
- Beyond the runs, a document may establish a **margin slot**: an edge, a position within 0.004 of
  the page height, and a type size within the same drift tolerance, at which removals already
  stand on at least six pages and at least a quarter of the document's pages. A candidate row in
  an established slot is removed although its own words never repeat on three neighboring pages —
  a transition head naming two chapters, a chapter whose notes fill two pages, front matter naming
  its own part. Slot size is the line's own type size for folios as well as prose, so one unit
  compares them. Stacked bands are never admitted on slot evidence alone. A page's own type size
  cannot overrule the slot, which is the point: a notes page sets its body at 7 pt under a 9.5 pt
  running head, so that head clears the page's heading threshold and would otherwise reach the
  reader as an `h2` (#10).
- A **drop folio** — the page number a book prints at the foot of an opening page, where the
  running head that carries it elsewhere is suppressed — is reached by a third kind of evidence:
  the document's own numbering. Every margin line records the physical-page offsets its boundary
  numbers imply, and an offset that the lines the plan already removes state on at least six
  pages and at least a quarter of the document's — the floor a slot asks of a place — is the
  book's own. A bare number, alone on its line, standing further out at the foot than any other
  line, set apart from the body by its own separation and inside the outer tenth, then goes where
  its value is exactly the folio that offset predicts for its page. The 9/11 report prints
  `430 APPENDIX` at the head of 546 pages, stating an offset of -18, and drops `429` to the foot
  of appendix A's opening page, which no run can see because no two opening pages are neighbors
  (#271). Nothing goes on position alone: the narrow 7% footer band is unchanged, a stacked band
  is not admitted, a numbered answer or a table cell would have to state its own page's number,
  and a book whose furniture states no offset — Our Flag removes nothing and sets a folio at the
  foot of every page — keeps every number it prints.
- Each affected page reports `furnitureRemoved` ("Repeated header or footer omitted from the
  reflowed text."); `removeRepeatedHeadersAndFooters = false` keeps everything. This is spatial
  evidence, not tag consumption or a universal header classifier.

Evidence: [local-header-regressions](../measurements/local-header-regressions/record.md),
[report-header-qualification](../measurements/report-header-qualification/record.md),
[stacked-margin-blocks](../measurements/stacked-margin-blocks/record.md),
[drop-folios](../measurements/drop-folios/record.md).

## LayoutReconstructor, PageTypography, LineRole, BlockAssembler

### Columns and paragraphs

Whitespace cuts recover ordinary columns and spanning headings; a narrow cut requires substantial
text on both sides so short name/description cells do not become independent columns. Paragraph
reconstruction joins hard wraps and narrowly supported cross-page continuations; a validated
chapter start or a differing tagged paragraph identity blocks a cross-page join. The separate
page-size estimate governs whitespace cuts and paragraph geometry. Known cross-page splits and
folio joins were raised in #45, which is closed and does not track them: it was closed by
`e1cbc0d0e` ("Join cross-page paragraphs on reading-order body anchors; never join folios") on the
abandoned coordination branch, and `dd160b4` merged that branch with the `ours` strategy, so the
commit is an ancestor of `main` and its content is not
([decision 0005](decisions/0005-abandoned-coordination-branch.md)). `appendPage` here is still the
original bottom-20%/top-20% band test, so the splits and the folio joins are still what this
library does. The fix is readable with `git show e1cbc0d0e` and, per decision 0005, is hand-ported
onto this pipeline rather than cherry-picked; nothing open tracks that port, and
[#231](https://github.com/vocaro/PDFReflowLib/issues/231) holds the reconciliation.

Where no cut separates a group, it is ordered by **column runs** rather than by lines, but only
where the page states that its columns are blocks. A magazine column that runs on into a wider
measure below — around an L-shaped picture frame — bridges the gutter beside it, so no straight
cut exists; and its columns are leaded so tightly that consecutive rows overlap, so no whitespace
band exists either. The elements are chained into runs (each joins the run standing directly
above it, sharing at least half of the narrower measure and separated by at most a body) and the
runs are placed by the same row-major comparator, read off each run's own rectangle. A
single-column group chains into one run and is unchanged. Four conditions gate it: some run must
widen, part way down, by more than a body into a measure another run holds, where the widening is
a text line of at least twelve bodies, all but a body of it is kept by at least two of that run's
elements below and by neither of the two above; no run may hold a single element; every run must
hold a picture or two lines of twelve bodies; and no element of one run may touch an element of
another. Together they separate a column running on from rows the page means to be read across.
One row set across a table's columns widens a run in the same way but is not kept, and a
paragraph's short last line before the next paragraph's full first line widens it without the
narrower measure ever having been kept. A timeline, an index of names against descriptions or a
worksheet's exercise numbers strands a run of one; a list of illustrations against their page
numbers is two stacks of short cells. And a run standing inside another run's rows — an
annotation beside its own working, a figure's labels inside the paragraph that introduces them, a
column the chaining split in two — is that row, however the chaining divided it, which a run-on
measure never is, because it widens across a gutter only where the column beside it has ended
(#137, #174, [column-run-order](../measurements/column-run-order/record.md)).

Before any of that, a straight cut is refused where one side of the white is **the page numbers
of the entries on the other side**, however wide that white is. **A page number a contents entry
runs its leader out to belongs to that entry**, and cutting there takes every entry away from its
own number: Project Blue Book sets its contents and its list of illustrations as a label, a title
and a page number at the right margin, the white the leaders cross is far wider than a gutter, so
each band read out its entries and then their numbers — `Figure 3`, `Figure 4`, both titles, then
`17`, `18`, `19`, `20`. The side must hold nothing else: every element a text piece no wider than
three bodies, standing on the row of a line beside it, and reading as a number — a numeral, a
roman numeral, or a token of at most six characters that holds a digit and spells no word, which
is what a scanned layer leaves when it misreads one (the same book hands back `ti6` for 66). A
page's second column is prose and fails at its first line. The measures are the page's own, so a
line the page lettered sideways is never one of these numbers: its rectangle is as tall as the
line is long and as narrow as the line is thick, and such a group is read along its own direction
(#207, #263, #277,
[contents-page-numbers](../measurements/contents-page-numbers/record.md)).

A cut is refused the same way where one side is **a stack of cells standing on the rows of the
lines beside them**: three or more elements, no two of them on one row, each on the row of a line
on the other side, none of them a text line of a column's measure, and none of them opening a list
marker. The 9/11 report's appendix of names sets a name against an office on twenty-three rows,
and reads column by column — `Thomas Pickering Colin Powell Ronald Reagan …` and then every office
— as soon as the one row the extractor hands back whole is divided at its gutter, which is the
correct reading of what that page prints. Three rows at least, because two cells beside two lines
are a label and a heading; and none of them numbered, because a numbered grid states its own
order, and what to do with a two-per-row exercise grid is an owner decision taken in #195 and
scoped in #219 (#270, #283,
[two-column-lists-read-by-rows](../measurements/two-column-lists-read-by-rows/record.md)).

A fifth condition is that a marker keeps its item. **A bullet is never a column of its own**, so a
stack of bullets describes no column of the page, whatever it chains onto: a page that hangs its
bullets clear of short items sets a column of markers beside a column of item text, and the marker
run only forms at all by chaining onto the paragraph that introduces the list, from which it
borrows the substance the third condition asks for. Read out as columns, every marker arrives
before any of its items and nothing downstream can put them back, because the rule that joins a
marker to the piece on its own printed row reads rows. So where a run holds a marker the page hung
clear of its item and another run holds that item, the group is left to the row-major order, which
reads each marker with its item. The marker and its item must be a marker and its item: the piece
beside it stands within the hanging indent a page hangs a bullet across, never a column's gutter
away, which is the measured gap the hanging-indent bound already draws
(#279, [hung-bullet-columns](../measurements/hung-bullet-columns/record.md)).

The cuts recurse 32 levels. A page whose separating gaps never narrow is cut one block at a
time, so its depth is its block count: uniform leading wider than 110% of the page body, as a
double-spaced typescript sets, reaches the limit at 33 blocks. Ordinary pages do not come near
it: the deepest of the captured source layouts cuts eleven levels. A group the limit leaves
uncut keeps the order it was extracted in, and the page reports `complexLayout` rather than
leaving that silent, as the tag phase reports its own give-up (#224).

A group the page **lettered sideways** is read along its own direction (#263). Every rectangle a
reader hands over is axis-aligned, so a line the page turned arrives as a box as tall as the line
is long, and reading order, `continuesRow` and every paragraph measure read it as though the
writing ran along it. A recognized line carries the quarter turn the page set it at, read off the
same quadrilateral its type size is (#130); where a group's every element is a line and they all
agree on one turn that is not upright, the group's rectangles are taken into the frame that turn
stands upright in and the same cuts and the same row-major sort are made there. The turn is one
rotation applied to every member, so it changes no gap, no shared edge and no overlap — only the
axis each is measured on — and the elements come back in that order, unchanged. A group holding an
upright line, a picture, a table or two opposite turns is read on the page, as before; so is every
natively extracted page, whose lines state no direction and are upright. The paragraph measures
read the same frame: `continuesParagraph`, `continuesRow`, the centered stack, the page's leading
and the start edge all compare two lines where their own writing runs, which for upright lines is
the page itself, to the bit. The CDC graphic novel letters page 17's caption down the side of the
panel — three lines that all reach one top edge, 1.4 and 2.5 points apart across the page — and it
read as `ATLANTA, GEORGIA...` followed by the other two joined backwards as one printed row; it now
reads `SEVERAL DAYS LATER AT THE CENTERS FOR` and then `DISEASE CONTROL AND PREVENTION IN ATLANTA,
GEORGIA...`, which is the caption in its own order, broken where the reading's own
`shouldWrapToNextLine` says the first line stops.

**Every other measure the page takes of such a line reads the same frame** (#276). A page's
**stated leading**, the **ordinary height** of a line at each of its sizes and the **ordinary gap**
beneath one, the **entries it hangs** its wraps under, whether two display lines **stack**, a
**marker's column** and the margin it justifies to, and the **printed rows and column boundary**
the table readers read are all group measures, so each is taken in the writing's own frame only
where every line of the group was set at one turn that is not upright — a group holding an upright
line, or two turns, reads on the page. A measure of one **pair** of lines asks the narrower
question that pair allows, that the two carry the same turn: `continuesHeading`, the broken item's
gap, and the test that the rest of a printed row stands beyond the piece that opened it. The two
predicates all of these are written through, whether two lines **overlap across the writing** and
whether they are **pieces of one row**, move with them, because a sideways line's box is as tall as
the line is long and on the page every line of a sideways caption shares a row with every other.
The table readers hand back the page's own rectangles, which is what a crop is tested against.
Nothing in the corpus exercises any of this: its only sideways writing is the CDC novel's pages 16
and 17, whose caption is three lines, carries no marker and stands in no table.

A **picture across the block's measure** — at least 90% of it — with content on both sides of it
separates what is printed above it from what is printed below it, and is cut at before any gutter
is looked for (#137). A picture at the **head or foot** of the block separates nothing, so that cut
declines it; but it still carries the whole measure with it, and while it stands in the group no
gutter can be found past it either. The FAA handbook opens pages 341 and 391 with exactly that — a
figure across both columns with nothing printed above it — and both pages were read row by row
(#160). So after every straight cut and the column runs have failed, and before the row-major sort,
such a picture is lifted out and the rest of the block re-read. A **line** set across the same
measure within a body of the picture's own top or bottom edge goes with it: it is that picture's
label and bridges the columns exactly as the picture does, and page 341 sets `Figure 14-6…` 7.7
points beneath such a figure. The band grows only from the picture's two edges, so a one-column
page, whose every line spans its block, gives up at most the line above and the line below; only a
picture seeds a band, because cutting at every line of a one-column page would reach the depth
limit and report the page unread. Trying it last is what keeps a page the other readings already
describe: the handbook's appendix of abbreviations opens under a full-measure banner over two
columns of short entries, which the column runs read as two runs and this cut would leave to the
row-major sort, one entry of each column at a time.

- A **picture between the two halves of a paragraph interrupts it; it does not end it** (#203).
  A cross-page join steps over the image blocks standing between the paragraph the page left open
  and the paragraph the next page opens with, on either side of the boundary, and each image it
  steps over keeps the side of that boundary its own page is on: the earlier page's images are
  placed before the joined paragraph, the later page's after it. The marker the join sets stands
  *inside* the paragraph, so placing the earlier page's images after it would carry that page's
  content past the next page's marker. The Fed sets Box 3.5 at the foot of page 47 and the
  paragraph that names it runs on to page 48, so `…(See box 3.5 for more details…) The vast
  major-` was a block of its own and `ity of the Federal Reserve's assets…` another; the box now
  reads before the sentence that refers to it and the word is whole. Boxes and figures are one
  block kind and take one rule. The join's own conditions are unchanged — a paragraph on each
  side, the band test, the tagged-identity test — so an image only stops being a barrier where two
  paragraphs already ask to be joined, and one is added: a block reached *past* a picture is being
  called a paragraph the page interrupted, so it must read as the page's prose (`readsAsSentence`,
  four or more words of two letters or more). A folio, a figure number or a stray mark is not one:
  the 9/11 report prints `145` under page 163's column and page 164 opens with a crop, and that
  folio would otherwise take page 164's opening words. The block directly before a boundary is
  still reached whatever it holds, so #45's own defect — a join anchored on a folio that is simply
  the last block — is exactly as it was. This is what reconstruction must hold back:
  `amendableTail` is the trailing block, or, where images stand at the tail, the paragraph
  beneath them and those images ([decision 0008](decisions/0008-streamed-blocks-to-the-writer.md),
  [decision 0011](decisions/0011-a-picture-keeps-its-side-of-the-page-marker.md)).
- A cross-page join reaches **only a block the page's own text begins at** (#267). Where a crop
  took prose the page printed *before* the first line it reflows, that block is not the other
  half of the sentence the page before left open, and no join is made: the boundary keeps a
  standalone marker and the two fragments stay two blocks. Wallace's page 430 opens `b are the
  other two sides (legs), then we can use the following formula, a² + b² = c²` and the display
  takes that whole row, leaving `to find a missing side.` to reflow, so joining it to page 429's
  `…the hypotenuse of the triangle, and a and` read two fragments a crop had already broken as
  one paragraph. Its page 344 is the same defect along a row rather than down the page: `values
  into x =` stands at the measure with the formula set beside it, so reading order is what
  decides — the cropped line is before the first reflowed one when it stands above it, or on the
  same printed row and earlier along it. Above the line, what the crop took has to be the page's
  own flow: it must read as the page's prose (`readsAsSentence`, as for the crops themselves and
  for a block reached past a picture) and it must **begin the measure the first reflowed line
  begins**, within a quarter of a body. Along the row no such test applies, because a printed row
  the page began inside a crop is that row wherever its pieces read. So a figure's
  number or an axis label above the first line refuses nothing, and neither does a box the page
  sets on a measure of its own — the 9/11 report runs its boxed list of *Operational
  Opportunities* over the foot of page 373 and the head of page 374, indented from the body, and
  `…all involved were` / `responsible for making it work.` is the join the page asks for. Only
  the page a join *opens* with is read this way. The page it leaves is not: the Fed sets a box or
  a figure over the foot of pages 40, 47, 55, 93, 97, 98, 100 and 103, and that crop's own prose
  stands below the paragraph, not before it — asking the same of the earlier page would refuse
  those eight joins and the eleven others like them. A paragraph whose own last line a crop took
  is still #45's reading-order anchor, which is not ported.
- Two lines are one paragraph when they **share a column** (left edges within 1.5 bodies, the gap
  between them from −0.4 to 0.9 of a body, and no further down the page than the leading it
  states) or are **two pieces of one printed row**: they overlap vertically by at least half the
  shorter one's height, the second stands to the right of the first, and less than 0.75 of a body
  separates them — the width a whitespace cut needs for a column, so a table's cells and the two
  ends of a running header remain separate blocks (#57). A short previous line ending a sentence
  closes its paragraph either way. That gap is measured from the line's own depth where PDFKit
  **grew the rectangle to fit what the line carries**: the page's own lines state what an ordinary
  line of each type size measures (the lower quartile of their heights at that size), and where
  two rectangles overlap and the upper one is taller than an ordinary line by more than a quarter
  of a body, the overlap is the rectangle's rather than the page's. Wallace's page 290 reports one
  line of running prose carrying an inline radical 20.46 points high where the rest of its
  paragraph is 11.98, so it reached 5.82 points into the line beneath and broke the paragraph in
  the middle of its own sentence (#230, the same measurement #213 records from the cropping side).
  The adjustment only ever brings a negative gap back towards nothing, so no two lines the reading
  already joins are separated by it.
- **A printed row the extractor split is one line** as far as the next line is concerned, so the
  paragraph's edge is the row's and not the edge of whichever piece closed it, and the row's whole
  width is what says whether the line above stopped short of the measure (#41, #272). The row is
  the two pieces' rectangles together; it ends where the piece that closed it ends, so its text
  and its wrap are that piece's; and it is set in the size the page set the wider piece in, so a
  superscript note marker standing at the end of a row is not the row's measure. Such a row has
  two starts — its own and the piece's — and a line beneath it continues the paragraph if it
  stands on either, so a reference entry whose marker the extractor split off keeps the wrap the
  page hangs under it. The row's own start counts only where the line beneath does not begin more
  than half a body further out than it: a wrap stands on its paragraph's edge or in from it.
- A row stands for one line **only where the page's own spacing says its pieces are consecutive
  words of it** (#272). PDFKit ends a line wherever the page leaves a gap, and a gap of at least a
  quarter of a body is a space the page set between two words. A narrower gap is the seam between
  two runs the page set beside each other — a note marker, a phrase in another face, a piece of an
  equation — and such a row lends its start to nothing; its pieces still join into one block. So
  does a gap the page repeats within a quarter of a body of the same place on three or more of its
  rows, which is a column it set rather than a space, whichever way the writing runs. Writing the
  reading reorders is the one place a seam is a line's own: PDFKit splits those rows at the
  boundary between two bidirectional runs rather than at a gap, which leaves the pieces touching.
  And the piece that closed the row must **read as writing** — at least half of its marks are
  letters, in any script — because the reading takes the row's text and its wrap from that piece.
  A piece of fewer than three marks is asked nothing, since one character says nothing either way.
  A page whose own sizes are unreliable states its columns by neither a recurring seam nor a
  gutter: Project Blue Book's statistical appendix reads every printed row differently, so its
  cells break in a different place on each of them, and five rows of it took the row beneath them
  until a cell of figures stopped standing for a line of prose (#285).
- **Rows of a table the page set without rules** keep their breaks rather than joining into one
  paragraph (#137, #210): a run of at least three rows on one left edge, in one type size,
  stepping down at one leading, where the page also states a column boundary — a cell the
  extractor kept apart on at least two rows that merged rows reach across, or a column of numbers
  on one right edge. The numeric evidence must hold for most of the run, not for three rows of it:
  the FAA handbook's acknowledgments name a chapter at the end of every credit and set each credit
  on its own line, so every row ends in a digit and three of the twenty end within half a body of
  one another, and nothing about that page is a table (#171).
- A run the page **filled to one measure** states no cell boundary, however far apart the
  extractor kept its opening pieces: a cell is set to its content and a paragraph is set to a
  measure, so a table's rows end raggedly and a paragraph's lines end again and again on the same
  edge (#268). Replay Clocks sets its references with the citation number outdented and the entry
  hanging at an indent — `[8]` arriving as a cell of its own, `[9] David L Mills. …` merged whole
  and reaching across it — which is the shape of a two-column table and read as one; seven of the
  eleven rows end within a fifth of a body of 558.2 and the four that fall short are each entry's
  closing line. Three rows at least, and most of the run, must reach that edge, and the edge must
  be carried by words: an edge carried by numbers is the column the rule above already reads, and
  the NOAA chapter contents right-align `4-16`, `5-9` and `7-20` against theirs. Neither the share
  of rows the extractor split nor the share opening on the run's own left edge separates the two —
  both were measured under #171 and both released the 9/11 report's flight timelines, the Blue
  Book's contents, the FAA handbook's cruise table and the USGS statistics along with the
  references.
- A **list the page hangs under an outdented marker column** is one paragraph per entry (#282).
  Not being a table leaves a reference list read as prose, and prose alone does not say where an
  entry begins: the ordinary column test allows two lines of one column one and a half bodies and
  these entries hang further — 1.35 bodies in the Replay Clocks paper, 2.37 in the Census paper —
  so each wrap opened a paragraph; the hung-entry rule above asks the wrap to stop a body short of
  the entry's right edge, which a justified reference list never does; and a marker the extractor
  kept apart stood past the gutter two pieces of one row are joined within, and joined the
  paragraph *above* it, so page 10 read `… Department of Computer Science, 1988. [8]`. The marker
  column itself is the evidence, and it is stronger than any measure of one wrap: three or more
  markers outdented between half a body and three bodies from one edge, each with an entry of at
  least twelve bodies beside it on its own row, and at least one further line hung on that edge. A
  page that has set that column has told the reader where every entry begins, so a line standing
  on the entry edge that opens no entry carries on the one above it, whatever its measure, and the
  entry beside a marker is that marker's own text. Only a bracketed number is read — `[8]`,
  `[ 12]` — because the markers `isList` also reads open the numbered items, headings and worked
  steps this library reads other ways
  ([column-cuts-and-hung-entries](../measurements/column-cuts-and-hung-entries/record.md),
  [hung-marker-entries](../measurements/hung-marker-entries/record.md)).
- The **leading a page states** is the commonest distance between the tops of two vertically
  adjacent lines, set at one size, in one column, to the nearest half point, over the lines its
  crops leave in the prose. At least four such pairs must agree, so a page too bare to say
  anything states none. Tops, not baselines and not the white between the rectangles: PDFKit's
  line rectangle grows downwards by whatever descenders the line carries, so on Wallace page 64
  the rectangle of `• More than often represents addition and is usually built backwards,` is
  20.46 points tall where the line beneath it has 11.98 and the white between the two is
  negative, although the page set them one line apart (#123).
- A line the page set **more than 1.4 times that leading** below the previous one is not the same
  paragraph, whatever the white between the rectangles says. Wallace page 64 sets an item's
  example 21.72 points below the item's own second line, where the page's leading is 14.40; the
  white between them is 9.74 points, inside the 10.76 the column test allows, so the example used
  to be appended to the item's sentence. The bound is the page's own measure because the same ten
  points of white is nothing under display type and a paragraph break under footnotes. A page
  that states no leading is judged by the gap alone, and so is a pair of lines set at different
  sizes, whose tops are not one ascent above their baselines.
- Two lines at that leading are also one paragraph when they are **centered on one axis** (mid
  points within 0.6 of a body) **and the reading says the first one wraps** (#130). A shared left
  edge is a column the page sets and stands on its own; a shared center does not, since a title,
  its author and its date are centered on one axis and are three separate lines. So the center
  joins only where the reading states the wrap: Vision states it for every line it recognizes and
  PDFKit's native reading states nothing, which leaves every natively extracted page as it was.
  The CDC graphic novel letters each speech balloon centered, so page 34's `I'VE BEEN` /
  `THINKING... WE` / `SHOULD REALLY` / `MAKE AN` / `EMERGENCY KIT` stand on five left edges spread
  over eighteen points and on one center within 1.7 points.
- A **stub of prose is closed by the step the next line takes** (#130): a previous line under half
  the width of the line beneath it, with that line set at least half a body further in, opens a
  new block even where no sentence ended. Prose fills its measure, so a line that used under half
  of it ended something, and the step is where the next thing begins; #39 already reads a marker
  set in past the line above it as an item's opening rather than a wrap. The Blue Book's observer
  questionnaire is the case: page 273 sets the spaced answer row `Yes or No` under question 7 and
  the instruction `IF you answered YES, then complete the following questions:` a body further in
  beneath it. Half is where the same book's contents stand — page 5 hangs each entry's wrapped
  line six points in under an opening filling three fifths of it, and the entry stays one
  paragraph.
- A line is also one paragraph with the line above it when the page **hangs** it there as the wrap
  of an entry (#160). Project Blue Book's page 6 sets its list of illustrations from one margin and
  hangs each wrap 48.5 points in at 7.8-point type, six times the size — well past the 1.5 bodies
  the column test allows, unlike its page 5's six points — so twenty-four illustrations reflowed as
  forty-two paragraphs. The indent alone proves nothing: a book that opens its paragraphs on a
  first-line indent sets the same two edges in the same alternation, and `firstLineIndentRun` reads
  the Blue Book's list as one of its own. What separates them is that a paragraph ends on a short
  line that ran out of words while an entry that wrapped ran out of room, so the page must state
  all of: the wrap stands directly beneath the entry, at its size, on the page's own leading, set
  in further than 1.5 bodies, so the rule speaks only where the column test is silent; the entry
  reads as a sentence, fills its measure (twelve of its own sizes) and ends none (past closing
  quotes and brackets); the wrap carries at least two letters and stops a whole body short of the
  entry's right edge, as an entry's tail does and a justified opening line does not; and the page
  hangs at least three entries on one and the same continuation edge.

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
  edge, center or right edge), and, on a recognized page in an English book, `readsAsWords`
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
(`•`, `*`, `−`, `-`, a run of digits or one letter, each followed by a point or a bracket and a
space) keeps its break. A marker is a marker because the page set it at the *start of a printed
line*, so a piece the extractor cut out of the middle of a row is never one: where another line
stands on the same row, ends at or before this line's left edge and is nearer than the 0.75 of a
body a column's gutter needs, the line reads as prose and rejoins the piece before it. Wallace
breaks a row after a raised exponent, so `8x²` is one line and `− 3x + 7− 2x² +4x− 3` the next,
1.89 points to its right, and the minus the page printed between two terms opened an item of a
list in a `<pre>` block of its own, in the middle of the derivation (#203). A page's columns and a
table's cells stand further apart than that, and a piece that opens its row has nothing to its
left, so a genuine marker still opens an item. Both are preformatted blocks that retain native emphasis and scripts;
inserted newlines and indentation are unstyled. Reconstruction has no list model: every such line
is its own preformatted block, and nothing here groups items. A block a marker opened records that
it did (`ReflowBlock.listEvidence`), and `ListBuilder` decides afterwards, from the blocks in the
order they leave reconstruction, which of them are the items of a real list ([Lists](#lists)).

A marker the extractor left **alone on its line** is still a marker (#172). Both tests above want a
space after the point or bracket, because the item's own text follows it there; PDFKit ends a line
wherever the page leaves a gap, so an item whose marker the page hangs a little further out comes
back as two lines and the first matches neither test. Wallace's page 101 returns `17)` and
`(− 16,− 14), (11,− 14)` where every other exercise on the page is one line, so exercise 17 read
as prose and was emitted as a `<p>` paragraph in a page of `<pre>` items. Such a line carries no
text of its own to vouch for it, and a number with a point is also how a citation ends, so the
page must state it twice over:

- **its row is a row of items, not a row of cells.** Everything the page set to its right on that
  row is either within the gutter — the item's own text — or a marker of the same list again, the
  next column of a grid of items. Wallace sets exercises 17 and 18 on one row, four points and a
  column apart. NOAA hangs a reference's number a column from its entry and the Blue Book's tables
  set a figure beside a number; those are rows of cells, which belong to the table readers (#210).
  A piece to the *left* within that gutter means the extractor cut this line out of the middle of a
  row, exactly as above;
- **the page states the list.** Another line of its size, on its own left edge, opens an item of the
  same list — numbered or lettered the same way and closed with the same point or bracket — and
  carries that item's own text after it. The 9/11 report leaves a citation's year on a line of its
  own (`2001.`) in a column whose note numbers are set in from it; nothing on that edge vouches for
  it and it stays the prose it is.

The **rest of an item's own printed row joins that item**, as two pieces of one row are one block
everywhere else (#57, #137): the next piece, standing to its right within that same 0.75 of a body,
is appended to the item's preformatted block with a space. It is the piece the page set beside the
marker, so `17)` and its coordinates are one item again. Nothing on another row joins, and only the
row's own next piece does. An item that *wraps* is still one preformatted block per line: the 9/11
report's numbered findings on page 365 keep `1. The CTC did not analyze how an aircraft, hijacked
or explosives-` as the item and `laden, might be used as a weapon…` as the paragraph beneath it,
which is what "no list model" above means, and item 4 of that list now reads exactly as items 1 to
3 do instead of as two paragraphs. That wrapped line is also what most often keeps a verified run
from becoming a list ([Lists](#lists)): the paragraph it opens stands between two items.

A **bullet** left alone on its line is read the same way, and asks less, because a bullet is a
marker and nothing else: no list has to vouch for it (#261). What the page must state is that the
item is beside it — another line on the marker's own printed row, the nearest one to its right, or
to its left where the writing runs that way. The FAA handbook hangs every bullet of its 499 items
18 points from the item's own edge on a ten-point body, so page 29 comes back as

```
[ 45.00 193.67   3.50 11.47] | •
[ 63.00 193.67 210.01 11.47] | IFR Charts—Enroute High Altitude Conterminous U.S.,
```

Two pieces of one row are one block within the 0.75 of a body a column's gutter needs, which is
the right bound for two pieces of *prose* because a wider gap there could be two columns. **A
bullet is never a column of its own**, so a piece the page set beyond that gutter is still the item
it marks, out to **two bodies** — an indent, not a column. Beyond that the page has set a column or
a row of cells, which belong to the column and table readers (#210). The marker and its item become
one preformatted item, and the bound is the marker's alone: once the item has joined, what stands
further along that row is judged by the ordinary gutter again, so the second of page 29's two
columns of items opens its own block as it always did.

A bullet with **nothing beside it on its row** marks something the reader cannot reflow — a key in
a legend, an item the page set as a picture — and is left exactly as it was; nothing beneath it is
ever taken, because only a piece of the marker's own printed row can join it. A piece to its left
within the gutter means the extractor cut the line out of the middle of a row, so it is no marker
at all, exactly as above (#203). Within the gutter nothing changes either: the two pieces are
already one block by the row rule, and a glyph a hair from the piece beside it is as often a
fraction's rule or a mark in a scan as a marker — Wallace stacks `−` over `3` a quarter of a body
apart on page 269.

A wrapped line of prose can begin with the same token — an initial (`W. Bush`, `U. S. 760`), a
citation abbreviation (`v. Moore`, `p. 785`, `F. 4th`) or a year or day carried over from the line
above (`2016.`, `on January` / `13.`). Such a line **continues the open paragraph** instead of
opening an item when all of the following hold (#39); a bullet, minus, asterisk or hyphen
marker never qualifies:

- the previous line already joined the open paragraph, so the ordinary column and leading test
  above holds and the previous line is not one the reader marked as not wrapping;
- the marker is no more than half a body to the right of the previous line's text start. A marker
  set in from the text above it hangs a new item; a marker to the *left* of it is the ordinary
  outdent of a wrap beneath an indented opening line, and is allowed up to the 1.5 bodies the
  column test already permits;
- the line stands on the left edge shared by more than half of the column — the proportional lines
  of its own size within 1.5 bodies of it — so a hanging marker beside dedented continuations does
  not qualify;
- that column is justified: at least three of its lines reach its right edge within a quarter of a
  body, and the previous line reaches it too. A line that stops short of the measure ended its own
  thought, and a list's ragged item lengths establish no measure to fill;
- the previous line does not end in `.`, `!`, `?`, `:` or `;`, ignoring closing quotes and
  brackets, and reads as prose: at least three runs of two or more letters, which an exercise or a
  formula above a numbered answer does not supply.

A page's own words are unchanged either way; the join only moves a line from its own block into
the paragraph above it, where an ordinary hyphen repair may then close a word the split had
broken.

A line the rule above does not join — the line with nothing running on it — is read against the
page's own edge before it opens an item at all (#171). **A list marks its items**, so where the
page stands at least eight lines of the line's own size on its left edge, within half a body, and
opens fewer than a quarter of them with a marker, it has set no list there: the point belongs to a
name's initial (`T. Graham Giusti` among twenty-five staff names, `P. E. Fansler,` alone among
thirty lines of the FAA handbook's page 18), a page reference or a citation (`U. S. 134 (1944),`
opening Loper Bright's page 64). Such a line opens a paragraph rather than a preformatted item.
Below eight lines the edge states too little either way — a list of one item and a marker
introduced by two lines of prose look alike — and the marker keeps its reading. The paragraph a
line like this opens takes only the wraps the page sets on that line's own edge, within half a
body, because the 1.5 bodies the ordinary column test allows would swallow the next paragraph's
first-line indent.

Evidence: [initial-led-lines](../measurements/initial-led-lines/record.md),
[page-leading-and-ligature-vocabulary](../measurements/page-leading-and-ligature-vocabulary/record.md),
[heading-body-regressions](../measurements/heading-body-regressions/record.md),
[three-fidelity-fixes](../measurements/three-fidelity-fixes/record.md),
[preformatted-styles](../measurements/preformatted-styles/record.md),
[citation-continuations](../measurements/citation-continuations/record.md),
[column-cuts-and-hung-entries](../measurements/column-cuts-and-hung-entries/record.md),
[dga-layout-qualification](../measurements/dga-layout-qualification/record.md),
[markers-alone-on-their-line](../measurements/markers-alone-on-their-line/record.md),
[bullets-alone-on-their-line](../measurements/bullets-alone-on-their-line/record.md).

### Lists

`ListBuilder` turns verified list-shaped blocks into real list items (#292), on the stream of
blocks reconstruction hands the writer. Its evidence is the block: a preformatted block a marker
opened (`ReflowBlock.listEvidence`, set by `BlockAssembler` on a bulleted line and on a numbered or
lettered line standing on an edge the page sets a list on, and never on code, a table row, or any
line of a page the document heads as a chapter's notes), or a paragraph opening with the `+`
bullet. Nothing on a page without such a block is touched, and a book that gains no list is
byte-identical to what it was.

- **Bulleted items** open with `•`, `-`, `+` or `*` and a space. A run of at least two with one
  glyph becomes `<ul>`, each item's text without its glyph. `−` is not a bullet: Wallace's
  derivation rows open with it, and some read as words (`− 7+6x Our Solution`). `* * *` is an
  elision. A `+` is read from the text alone — a plus, a space, a word of two letters or a
  percentage, and the rest reading as words — because reconstruction reads `+` as the operator it
  is everywhere else; the dietary guidelines set their top-level items so, as whole paragraphs.
- **Numbered items** open with one to three digits, `.` or `)`, and a space. A run becomes `<ol>`
  only where its printed numbers ascend by exactly one; a run whose first number is not 1 keeps it
  as the list's `start`. A `1` always opens a new run. A gap, a step back or a repeat leaves the
  whole run preformatted, because an `<ol>` would print numbers the source does not have.
- **A candidate reads as words**: letters in words of three letters or more make up at least 35%
  of the text past its marker. An answer key's `1) 42`, a derivation row and recognition debris do
  not. A **transcription of a scan** (recognized, or an inherited invisible layer) offers numbered
  items only, held to the same rules wherever they occur — the Blue Book questionnaire's
  `22.`–`27.`, the Warren report's conclusions where their numbers run on by one — and its bullets
  stay as they are, being recognition of table rules and headers (`- Per Cent`).
- **A run** chains each candidate to the latest candidate of its family (one glyph; one
  punctuation) on the same page or the page before, whatever blocks stand between; a number
  chains where it is one or two from the last, so a gap of two is verified against and refused
  rather than started afresh. Any list-shaped block that is no candidate ends every run. A run is
  decided once every block of the page after its last member has arrived and one page more, so
  the pass holds a run for at most three pages past its end and nothing else; what a decision
  reads from further back travels as a count or a marker.
- **A numbered run stays preformatted** when its items each stand alone between other blocks
  (numbered section titles; items of another family between them are the list the page set
  inside this one, and do not count); when at least half its entries end on a folio or carry a
  section number (a contents list); when more than half give quantities and ask for one (an
  exercise set's word problems); when at least half open on an author or cite `Author, 2021:`,
  a DOI or an address (a reference list); when its pages hold more numbered entries that read as
  no item, with its punctuation, than it has items (an answer key); when the list-shaped entry
  before or after it, reading as no item, continues its numbering (a transcription's garbled
  notes, an exercise set that opens on conversions of figures); or when the heading in force —
  the last heading before its first item — names an exercise set, with a word *practice* or
  *exercise(s)*, since those problems key the book's answers and wait for their reading order
  (#219 item 4). The book's heading is the evidence, as `NOTES TO CHAPTER` is for a notes page.
- **No one-item lists.** A list element is a piece of an accepted run whose items touch: only
  page boundaries stand between them. A piece of one item is a paragraph that keeps its printed
  marker. A run of one — a marked line with no other list-shaped block on its page or the pages
  beside it — is a paragraph that keeps its marker too (the CDC comic's `1) Get a Kit`), except a
  number whose nearest numbered line of its family, however far back or as far ahead as the pass
  holds, is one or two from it (a section title in a sequence spread over the paper) and a
  note's asterisk (`* Estimated`), which stay as printed; a run of one with a list-shaped
  neighbour within a page stays preformatted, as it was.
- **Items are flat** (#219 item 3). A candidate of another family between two items of a run —
  the 9/11 brief's bullets under its numbered paragraphs, the guidelines' `-` items under a `+` —
  leaves the run intact but ends its list element, so the item before and the item after are
  pieces judged as any piece is, and the inner items are a list of their own. Lettered items
  (`a.`, `b)`) are never candidates and keep their preformatted form.

What stays preformatted, recorded so nobody re-opens it: display maths rows, the FAA's coded
weather reports, OCR debris, the Warren report's elisions and testimony turns, note asterisks,
contents and section titles, lettered sub-items, exercise sets, answer keys, reference lists and
the entries of a notes apparatus. Evidence: [list-conversion](../measurements/list-conversion/record.md).

## HyphenRepair

- A soft hyphen (U+00AD) at a wrap is removed. A hard line-end hyphen is a break whatever opens
  beneath it, and the halves close up on it: the page drew no space there. Where the next line
  opens **in lowercase**, the join is decided on the letters either side, as below. Where it opens
  with a capital or a digit, the page has broken a printed compound at its own hyphen, and that
  hyphen stands unless the book writes the word whole and never the compound — the 9/11 report
  prints `C-130H`, `non-Muslims`, `mid-1980s` and `Israeli-Palestinian` and writes 34 of its 45
  broken compounds closed elsewhere in its own pages, while *The Fed Explained* breaks
  `…operating the Fed-` over `Wire and automated clearinghouse…` and writes `Fedwire` whole twenty
  times (#288). No warning is raised on that side: a compound broken at the hyphen the page prints
  is not the ambiguous case `uncertainHyphen` is about.
- The hyphen is removed silently when the book's own vocabulary holds the joined word and not the
  hyphenated compound. When the vocabulary holds the compound, the hyphen stays silently.
- The vocabulary holds every word lowercased and with the typographic ligatures and other
  compatibility glyphs a font draws resolved to the letters they stand for, and the two halves of
  a break are looked up the same way (#123). Wallace's text font prints `different` with a U+FB00
  `ﬀ`, so the book's own words held `diﬀerent` — 56 times — and never `different`, and had
  nothing to say about `dif-` + `ferent` on pages 50 and 218. Only the evidence folds: the
  ligature the page printed stays in the text the reader gets, on both sides of a join.
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
- A book whose text font encodes the hyphen it draws at a line end as some other character has
  that character read as the hyphen it is (#233). The substitute is decided once for the whole
  document and only from the text the reader will keep: a candidate qualifies when it occurs at
  least eight times, at least 95% of those occurrences end a line directly after a letter, and at
  least 90% of those lines are carried on by a lowercase letter. Sentence punctuation, quotes,
  brackets and dashes are never candidates, because a book could legitimately end every line with
  one; two qualifying candidates disqualify each other. A book that means the character spends
  most of its occurrences inside lines and never qualifies — the 9/11 report's `=` scores 994 of
  1,004 while its `/` scores 4 of 878. Only a line-final occurrence is ever rewritten, so a
  genuine one inside a line, such as a URL's `name=value`, is left as read, and the join itself
  is then decided by the vocabulary and lexicon above, warning where it would warn for a printed
  hyphen. A join the evidence cannot decide keeps a real hyphen, never the encoded character.

- A heading East Asian writing breaks between two characters of one word is one heading: a
  heading line whose break sets no space, at the same size, on the page's own leading, continues
  the heading above it rather than opening another (#42). A display line's PDFKit box carries
  enough leading that two stacked lines of a title overlap — IRS Publication 596's cover overlaps
  by 12.9 points at 31-point type — so the bound is the type size itself. A break between two
  Latin words is a space and says nothing about whether two lines are one title, so Latin
  headings are untouched.
- East Asian writing sets no space between the characters of a word, so a line break between two
  characters drawn one em wide (`CJKText.isFullWidth`: the Wide and Fullwidth blocks, including
  the CJK punctuation a line may end on) joins them with none (#42). A boundary with Latin text
  keeps the source's own spacing in both directions, so `提交表格` + `1040` still takes a space.
- A page written right to left is read that way (#41). Its columns are read from the right of the
  gutter, its rows from their right-hand piece, and a paragraph's lines are joined by the edge the
  writing starts at — their right edge, which stands within a point of the measure while their
  left edges are ragged. A printed row the extractor split is one line as far as the next line is
  concerned, in both directions (above, #272); what is this page's own is that the pieces of such
  a row touch, because the reading reordered them rather than the page spacing them apart.
  The left-hand piece of such a row carries the stop that ends the sentence before it, and the
  page's own space after that stop, so the join adds none of its own. A table's rows are read the
  same way round, so a contents entry ends at the page number its row actually ends at rather than
  at the title on the other side of its leaders. Every one of these keys off
  `ArabicText.readsRightToLeft` over the page's own lines, so a Latin or East Asian page reaches
  none of them.

- An item the page broke mid-word keeps the rest of its word (#245). Where a preformatted list
  item ends in a hyphen, a soft hyphen or the book's line-end substitute, and the line beneath it
  opens in lowercase at the same size on the page's own leading, that line joins the item. The
  9/11 report sets its recommendations as items and breaks one over the block boundary, so
  `• …supervise the planning and direc-` was followed by `tion of the operation;` as a paragraph
  of its own. The marker the page opened the item with makes no difference: a bullet, a minus or a
  hyphen is read as an item outright, and a number or a letter with a point is read as one where
  the page sets a list on that edge, and either way the block it opened is the one the rest of the
  word belongs to (#266). Our Flag numbers its flag-folding instructions and breaks the first at a
  printed hyphen, so `1. …hold the flag waist high and horizon-` stood above `tally between them.`
  A new sentence is not the rest of a word, and neither is the item beneath: the lowercase opening
  and the page's own leading are what decide, so a list whose items each end in a hyphen does not
  fuse.
- What becomes of that hyphen is decided the way a hyphen inside a paragraph is decided, on the
  book's own words and, in an English document, the system lexicon (#266). The page's break says
  the line belongs to the item; it does not say the character was a break rather than a printed
  compound, and the 9/11 report's endnotes stand both on one edge: `Febru-` carries on `ary` and
  loses its hyphen, `explosives-` carries on `laden` and keeps it, with no space added either way.
- That takes one printed line and only one opening in lowercase, so the rest is read over the
  page's **blocks** after everything else has decided what they are, which is how the cross-page
  join has always worked (#280). A block ending where the page broke a word takes **the whole of**
  the block beneath it when that block opens the rest of that word, and keeps its own kind. What
  opens the rest of a word is a lowercase letter; **no letter at all**, because a serial, a
  citation or a measure crosses a break the way a word does — the 9/11 report breaks
  `…serial 1928; 265A-NY-` over `280350-302, serial 16379`, and a line that opens with a marker of
  its own is excluded, since that marker opens an item; or **a capital where the two halves make a
  word the book itself writes**, which is why *The Fed Explained* may carry `…operating the Fed-`
  over `Wire and automated clearinghouse…` and writes `Fedwire` whole twenty times. A word is what
  is broken, so a letter or a digit must stand in front of the break: Project Blue Book's
  inherited OCR ends whole blocks on the runs of dashes it reads its ruled pages as, and none of
  those is a word carrying on. Across a page the same reading admits a preformatted anchor that
  ends broken, which `appendPage` alone reaches.

- A block whose whole text is **one sentence-ending mark** — `.`, `?`, `!`, or the full stop
  Arabic and Urdu draw — is that sentence's own stop and joins the block above it, where that
  block is text on the same page which does not already end in one (#291). Writing set right to
  left puts the mark at the far left of the last line, and the extractor hands it back as a line
  of its own: the USCIS guide reflowed four as blocks and one of those as a heading. #41 reaches
  such a stop only where the extractor split one printed row. One mark and one only — an ellipsis
  is an elision the book prints, a rule of dashes is a footnote's rule, `* * *` is a section
  break, and `=`, `·` and `−` are a worked example's operators — and a picture between the stop
  and its sentence is reason to leave it where it stands.

Evidence: [spine-continuity](../measurements/spine-continuity/record.md),
[a-sentences-own-stop](../measurements/a-sentences-own-stop/record.md),
[broken-numbered-items](../measurements/broken-numbered-items/record.md),
[items-that-carry-their-word](../measurements/items-that-carry-their-word/record.md),
[line-end-hyphen-substitutes](../measurements/line-end-hyphen-substitutes/record.md),
[page-leading-and-ligature-vocabulary](../measurements/page-leading-and-ligature-vocabulary/record.md).

## TableReader: a table read as cells (#210)

A page's tables are read during extraction, where the page itself can still be asked what stands
inside a rectangle, and carried on `PageContent.tables`. Where a table is read, the crop that used
to preserve it as a picture is never seeded, its rows do not reflow as text, and the writer emits
`<table>` markup that carries the association a table exists to state: which value stands under
which heading.

- **Rows and their ink.** A printed row is a row of the page's extracted lines (a raised note
  marker shares its row). Its ink is the run of the page's own text-showing operations on that
  row, merged where they touch — finer than the lines PDFKit hands back, and independent of where
  PDFKit chose to break a row. One walk of the content stream serves this and the spacing repair.
- **Blocks.** A block is a run of at least four rows at one type size and one leading, which the
  first step states and every later step keeps within a third of a body. That is what separates a
  table from the paragraph above it: the USGS summaries set their tables at the body's 11.0-point
  leading and leave 21.7 points above the first row.
- **Columns are the white that runs down every row.** An x range no row of the block puts ink in,
  at least half a body wide, is a corridor; two corridors make three columns. Every row is then
  divided at the corridors' midpoints rather than at its own gaps, which is what divides the
  widest row correctly: `Employment, mine and plant, number 11,000 11,400 12,000 12,600 13,000`
  leaves 5.6 points between its values where the rows above leave 8.4, and no per-row threshold
  reads both. A heading the page sets across several columns closes the corridors under it, so up
  to two such rows are lifted off the top of the block and read against the columns the rows below
  state, which gives `Mine production` and `Refinery production` their `colspan="2"`.
- **A cell's reading.** Where the page's extracted lines divide on a cell's edges, the cell is
  those lines' own content, with the spacing repair, the styles and the links the rest of the
  pipeline gives them. Where one line spans several cells, the cell is the plain characters
  `PDFPage.selection(for:)` reads inside the rectangle: the line's string cannot be divided at its
  spaces, because `1.7¢/kg on lead content.` is one cell with spaces in it and `United States
  1,130 1,100 882 890 47,000` is six cells with the same spaces between them.
- **A cell cannot be lost.** Unless the cells account for every non-space character of the lines
  the block covers, the table is declined and the page keeps the reading it had.
- **Column headings.** The rows at the top of the block that the page underlines with a thin rule
  become a `<thead>` of `<th scope="col">`; only the block's first three rows are consulted,
  because a rule above a total row is not a heading. This is the same evidence #36 reads.
- **A label the page wrapped.** A row putting ink in no column but the first, whose ink reaches
  that column's edge, is the first half of the row below and joins its opening cell: `Stocks,
  refined, held by U.S. producers, consumers, and metal` / `exchanges, yearend 118 117 84 127 70`
  is one row. A group row holding only a label — `Production:`, `Exports:` — stops a fifth of the
  way across and stays the row it is.
- **What is not a table.** Three conditions keep running prose out. *Three columns at least*: two
  columns of prose facing each other across a gutter are a page's layout, and the gutter is one
  corridor. *No column of prose*: a column whose cells fill it again and again — three or more of
  five words or longer, and at least half the column's filled cells — is the page's own text.
  Page 416 of the FAA handbook prints its NDB table in the right column of a two-column page, and
  on geometry alone the left column's prose rows and the table's rows form one grid; this is what
  separates them, and three of the twenty-four rows of the USGS label column reach the column's
  edge without being prose. *A column of values*: some column other than the first must hold three
  cells at least and be two-thirds numbers, where a value is a number, a dash standing for zero,
  or a number an estimate mark or note marker is set against (`e740`, `(2)`, `7100,000`, `—`).
- **What a cell does not carry.** A cell's marks are characters, not markup, where the cell is not
  one whole extracted line: `Reserves6` and `e150` read as the page prints them but the raised
  digit is not a `<sup>`.

Evidence: [tables-read-as-cells](../measurements/tables-read-as-cells/record.md).

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
- **A word a crop cuts in half.** A crop does not take one half of a word whose other half falls
  outside it: where a line the crop takes ends in a hyphen or a soft hyphen and the line directly
  beneath it, in the same column, opens in lowercase outside the crop, the taken line is released
  and both halves reflow. Replay Clocks page 8 breaks a figure caption `…𝛼 = 40 mes-` /
  `sages/second.` and the crop's edge fell 0.49 pt above the second line, so the first half went
  into the picture and the second reflowed alone between two figures; the caption now reads whole
  (#59). Evidence: [painted-underlines](../measurements/painted-underlines/record.md) records the
  neighbouring rule; this one is measured in the commit.
- **The book's own prose (#255).** A crop never admits a line that reads as the book's own prose.
  Where no cut clears such a line while still holding the region's core, the crop keeps its own
  extent rather than growing into it, exactly as the page-furniture rule below does; `takes` then
  leaves the line in the prose, so the picture loses nothing and the sentence is not buried.
  Prose is `readsAsSentence` — four or more words of two letters or more — and, for a line written
  in the Latin alphabet in a book that declares English, it must also read as English words: the
  CIA report's crops sit over handwritten tables whose text layer is
  `0/iLE 1112£ E/(19U/,£r//?/Z/`, which passes the sentence shape and recovers nothing. The word
  test runs only on Latin-alphabet lines of a book that declares English, because an English
  lexicon reads a Chinese or Arabic line as no words at all; in a book declared otherwise — the
  corpus lane declares the Arabic guide `ar` and the Chinese publication `zh-Hans` since #293 —
  the sentence shape alone decides.
  This recovers 45,754 characters across eight of the eighteen corpus books, three quarters of the
  magazine's text among them. One cost is known and recorded: the magazine's recovered lines
  read in its columns' interleaved order (#174's defect, on text that used to be hidden inside
  the pictures). Evidence: [prose-inside-crops](../measurements/prose-inside-crops/record.md).
- **A table's column header (#257).** The rule above never releases a line the page set as the
  label of a table's columns. The CIA report's crops preserve its statistical tables as pictures,
  and the lines that rule let out of them included those tables' headers — `Number Per Cent
  Number Per Cent Nuntler Per Cent`, `Certain Doubtful Total Certain Doubtful Total` — every
  token of which is an English word, so the word test admits them, and which beside the picture
  of their own table say nothing a reader can use.
  A header is read from two things at once, because neither alone is enough.
  *The page set the line in a table's columns:* its printed row holds pieces the page kept apart
  as cells, each beginning at or after the one before it ends, and at least two other rows of the
  page begin a piece on the same column edge. `rowBlocks` cannot read these tables, because this
  book's inherited text layer gives every printed row a size of its own and the crop has taken
  the rows beneath.
  *The line prints one column label once per column:* the same short group of words over and
  over, read against the first group and the group before it, with words compared within an edit
  distance of half the shorter one, because the recognizer spoils words a group at a time and
  letters within a word (`Nuntler` for `Number`, `Ooubtfut` for `Doubtful`). Four repeated words
  in five must agree.
  The recognizer also moves the printed spaces, and then no word has a counterpart to be near:
  page 151's `! lt>mber Per Cent Number Percent` broke `Number` into `lt` and `mber` and closed
  `Per Cent` up into `Percent`. The same repetition is therefore read a second way, on the line's
  letters in order with the spaces taken out: for each number of columns the letters are cut into
  that many pieces of equal length, each cut moved to the nearest word boundary, and the pieces
  are compared against the first and against the one before (#262). A piece is several words
  long, so it agrees within a fifth of the shorter rather than a half — over a label of three
  words that is tighter than the word reading allows one spoiled word inside it — and every word
  of the line must hold a letter, because a label is written in words and a repeating group of
  bare figures is the table's own data or an equation (`0 0 0 200`, `3r + 6+ 3r =30`).
  Geometry alone would not do: the magazine's three-column pages hand back their columns on
  shared baselines, so every row of running prose there has a table's shape, and on geometry
  alone this rule buries 17,340 characters of its articles. With both halves it moves the CIA
  report alone — by 1,457 characters when #257 landed, and by a further 681 when the letters
  reading was added — and every other book is unchanged to the character.
  The report's handwriting is not this rule's to fix: that book's inherited OCR layer is
  unverified, and #216 catalogues what it produces.
  Evidence: [table-headers-inside-crops](../measurements/table-headers-inside-crops/record.md),
  [spoiled-column-labels](../measurements/spoiled-column-labels/record.md).
- **A row a picture's crop reaches into (#207).** `takes` keeps the lines whose middle row a crop
  holds, which is right for a picture's own lettering — a diagram's labels, a chart's axis, a
  legend's entries all stand *inside* the artwork. A page can also print its own reading across a
  picture's footprint, and then the crop is reaching into that row from the side rather than
  holding it. A crop neither takes nor grows into a printed row a piece of which straddles its
  edge — begins more than a point outside the crop and runs into it — nor into the other pieces of
  that row standing to that piece's right, so a released contents entry keeps the page number it
  runs to instead of leaving it behind in the picture. Straddling is what a piece must do: a piece
  standing wholly outside the crop is a cell of its own and says nothing about this one, and the
  Replay Clocks paper sets six figures in three columns and gives each its own sub-caption on a
  shared baseline, where `(a) 𝛼 = 20 messages/s, 𝑛= 32.` is the left figure's lettering rather than
  the beginning of a row the middle figure reaches into.
  Two exclusions carry over from the rules this one sits beside. Only a crop preserving a placed
  raster image is read this way, because a region a page merely paints can still be carved —
  Wallace's fraction crops reach leftwards to the exercise numbers that are part of their
  expressions, and keep them. And a picture covering the page is the page, exactly as in #239: the
  CIA report's crops sit on scans whose inherited layer is unverified OCR, and reading their rows
  this way let 8,340 characters of `~,....,....,....r-T""S....,...,-100` out into the prose. A
  table's column header is its table's here too and is never released (#257).
  Every contents page of the climate assessment sets its entries from the
  left margin to a page number at the right edge and places a decorative line drawing over its top
  right corner; the drawing covers the right end of the first nine rows, no cut clears them, and
  pages 9–18 lost 9,281 of their 14,808 characters — 47% to 73% of a page — into that one picture.
  Evidence: [contents-pages-inside-crops](../measurements/contents-pages-inside-crops/record.md).
- **Page furniture.** A region spanning at least 90% of the page's measure and flush against its
  top or bottom edge is the page's own furniture — a footer or header background — not a figure
  with a claim on the text near it. It keeps its own extent rather than growing to a line it only
  grazes, and a crop takes the lines whose middle it holds. Dietary Guidelines page 2 paints such
  a band to y=80.12 and prints its notes from y=77.49 to y=85.45; growing into the 2.63 points of
  overlap took two of the page's four notes out of the book (#246). Every other region keeps the
  whole-line growth of #36, including a fraction bar, whose terms lie outside its seed by
  construction. Evidence: [footer-band-notes](../measurements/footer-band-notes/record.md).
- **Inline fractions.** A bar at the right edge of a line that reads as a sentence, with a line of
  at most two words beneath it inside the bar's own measure, is an inline fraction whose numerator
  PDFKit merged into the sentence. The denominator joins that line as `numerator/denominator` and
  stops being a block of its own: Wallace page 137 reads `use the slope rise/run to get the next
  point`, where it had set `run` adrift on its own line (#53). `isFractionBar` cannot decide these,
  because a display fraction's test requires the term above the bar to carry no word of three
  letters, which a numerator merged into prose never satisfies. A numerator that is a line of its
  own keeps its crop.
- **Thin rules.** A painted rule at most 6 pt high and at least 12 pt (and three times its height)
  wide, measured after `GraphicsReader`'s two-point padding, is a typographic separator rather than
  a figure. Such a rule seeds no region when it underlines one text line — it lies within that
  line's horizontal extent and between its foot and half its height — and the underlined line keeps
  reflowing; an underlined word inside a paragraph is decoration (#229). A rule that carries a
  fraction (compact, word-free terms directly above and below) keeps the terms it touches; a rule
  inside a short word-free line, such as a vinculum or an exercise bar, keeps that line; a rule
  clear of every line, such as a running-head rule or a box, stays an isolated graphic. A rule no
  single line owns is read against the measure of the printed *row* it strikes through, which is
  the leader a contents entry runs to its page number over (#207): PDFKit reads such a row as one
  line where the entry is short — and the line test already called that leader decoration — and as
  two where it is long, and read against the long entry alone the leader ends far beyond that
  line's right edge and owns nothing, so every long entry of the climate assessment's contents
  pages seeded a figure that buried the entry and its number. Three conditions keep the row the
  rule's own. It must be a row PDFKit read apart, at least two pieces. Each piece must be one the
  rule touches or abuts, within a body of an end of it, because a page sets its columns further
  apart than that and the line the next column happens to set on this baseline is not in this
  rule's row — the Replay Clocks paper's algorithm rules would otherwise be owned by the prose
  half a page to their right. And the row may only take a rule *away* as decoration, never widen
  it to the row's measure: that measure reaches across the page's columns, and unioning a
  mathematical rule with it carried Wallace's fraction crops over the exercise standing beside
  their own. A rule the row does not claim stays the isolated graphic it already was. Our Flag's
  title page is the rule this reads as decoration outside the climate assessment: it sets
  `108th Congress, 1st Session` and `H.Doc. 108-97` at the two ends of one row and draws a rule
  the width of both beneath them, which was preserved as a 310 × 4 pt picture. And a row of
  at least three header underlines, or one short piece underlined whole away from the left margin,
  over at least three tightly leaded rows carrying numbers, is a borderless table
  (`TableRegionDetector.underlinedColumnRegions`) preserved as one region (#36) — unless
  `TableReader` read that table as cells, in which case the seed is dropped and no crop is made
  (#210).
- **Region expansion.** A seed's crop admits only the text lines it captures and the other pieces
  of those lines' rows, never a chain from line to line: PDFKit's line rectangles include leading
  and so overlap on tight leading, and chaining absorbed whole columns. A thin rule captures only
  text it strikes through — its midline inside the middle half of the line's rectangle — not the
  rectangles above and below it. The crop is then trimmed away from any line it merely touches,
  keeping the seed's ink (for a thin rule, its one-point stroke), because layout removes every
  intersecting line from the reflowed prose; a line the crop cannot be trimmed away from is
  admitted instead, and a thin rule left with nothing admitted yields no crop at all (#36, #229).
- **Prose printed over a picture** (`PageDiagnosis.proseOverPictures`, #239). A crop a page's own
  prose sits inside cannot be trimmed away from it, so the words would leave the book. A run of
  lines a crop takes still reflows, while the crop is preserved and shown unchanged, when every
  line of it lies wholly inside one placed raster XObject that covers no more than
  `pageSizedGraphicFraction` of the page, and the run reads as a wrapped paragraph: at least 3
  rows on one left edge (within a quarter of the type size), at one size (within a tenth) and at
  one leading (between 0.8 and 2.2 type sizes, and within a quarter of the run's own first gap);
  every row but the last at least 0.8 of the run's widest row; at least 20 words; fewer than
  `maximumNumericShare` of the tokens carrying digits; and at least `minimumEnglishShare` of the
  words the lexicon judges being English words. A page paints a row twice for a knockout, so that
  it reads over the picture beneath it; an identical rectangle is one row of the paragraph rather
  than a break in its leading, and it reflows once, the repeated copy staying inside the crop.
  Only books declared English are judged. A picture covering the page is the page — a scan, whose inherited
  layer #93 and #176 already decide — and is never read this way. A figure's own lettering fails
  the paragraph test and stays in its crop: a legend runs a whole entry between rows, an axis sets
  each label at its own width, and a scanned table's cells carry digits.
- **`FractionRegionDetector`.** Short horizontal painted bars with compact mathematical terms
  above and below, optionally with a nearby equation prefix, are preserved together in one image.
  Long rules, prose, code and connected table grids are left to existing handling; whole-line
  expansion supplies the crop margin once, and detection does not enlarge complete regions again.
  Arbitrary mathematical structure is outside this detector.
- **`NumberedNoteDetector`.** A top-margin chapter-note heading (`NOTES TO CHAPTER 3`, or
  `NOTES TO CHAPTERS 9-10` where one chapter's notes end and the next chapter's begin, either
  beside a folio), consecutive indented note starts and consistent dedented continuations must
  agree before a bounded native endnote paragraph repair applies; ambiguous layouts keep spatial
  reconstruction. This is layout, not reference-to-note ownership. The pages the heading names
  are also the pages whose numbered lines are never list items ([Lists](#lists)).
- **A table a recognition located (#31).** A recognized page's tables become its crops, so every
  one of them reaches the reader as a picture and none of its cells reaches the text. Such a crop
  is described as what it is — "Table from page N, preserved as an image. Its cells are not
  transcribed; read them in this picture." — rather than as `Preserved region from page N`, which
  tells a reader nothing about where the table's numbers went. The description states no row,
  column or cell count, because the grid the reading returned is the reading's and not the page's.
  A crop owns a table when it holds at least half the table's area, so a figure standing beside a
  table on the same page keeps its own description.
  A table whose cells the reading did *not* transcribe additionally raises `unreadTableCells`,
  once per table. The measure is `TableCellEvidence`: a table the recognizer read fills most of
  its grid, and a grid it drew over writing it could not read is ruled wider than the page and
  left mostly empty. Measured through this library's own rasterizer and reading, the USGS copper
  tables fill 94%, 67% and 63% of their grids and the CIA report's typewritten `TABLE IV` fills
  83%, while that report's handwritten `TABLE A63` fills 27% and 13%; the rule is half, and a
  grid under nine cells says too little either way and is not judged. The share is read from the
  grid rather than from the cells' text, so it needs no lexicon and judges a page of any script
  alike. Signaling is kept separate from repair: a table this measure believes is still only
  preserved and described, never transcribed into the reader's text, because even the reading of
  `TABLE IV` drops one value and corrupts two more.
  Evidence: [scanned-table-cells](../measurements/scanned-table-cells/record.md).
- Preserved regions, page fallbacks and cropped figures are images: cropped text is neither
  reflowable nor accessible as text, and the generic image description names the source page
  rather than inventing a description of the picture. The two exceptions are a wrapped paragraph
  printed over a picture, which reflows as well as being shown inside the crop (#239), and a
  located table, whose crop says that it is one (#31).

Evidence: [rule-and-url-seeds](../measurements/rule-and-url-seeds/record.md),
[preserved-region-regressions](../measurements/preserved-region-regressions/record.md),
[fractions-and-invisible-text](../measurements/fractions-and-invisible-text/record.md),
[numbered-notes](../measurements/numbered-notes/record.md) and its
[recheck](../measurements/numbered-notes/recheck/record.md),
[image-regions](../measurements/image-regions/record.md),
[prose-over-pictures](../measurements/prose-over-pictures/record.md).

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
manufacture headings: an outline entry is not a heading in the text, and writing one would put
words on the page the page does not print. They do supply navigation, which EPUB models
separately — see `OutlineReader`.

Evidence: [chapter-boundaries](../measurements/chapter-boundaries/record.md).

## OutlineReader

The author's own table of contents becomes the EPUB's `nav epub:type="toc"`, nested as the
author nested it, each entry a link to its destination page's marker (#249). Where a document
states no usable outline, navigation stays the flat list of detected headings, which is what
every document had before. Headings keep their ids either way, so nothing in the text stops
being addressable.

Not every outline is a table of contents, and a document whose outline is a machine artifact
would navigate worse than its detected headings, so `isNavigation` gates it on shape alone,
reading nothing: at least two entries; at most 10,000 and at most three for each page of the
book; at most four levels deep; and more than half the titles distinct. Four of the twelve
corpus outlines fail it — the FAA handbook's tagged-structure dump (7,689 entries, eleven deep,
for 522 pages: `Structure Bookmarks`, `Document`, `Article`, `1-1`), the CIA report's 313 entries
all labeled `Figure`, the Warren report's single entry labeled `Test`, and the copper summary's
single entry — and each of those keeps the navigation it had.

An entry's title is normalized as any stated value and bounded at 512 characters; the USCIS
guide's wraps over two lines and is joined. An entry that resolves to no page of this document —
a remote or non-`GoTo` action, as before — groups its children in a `span`, and is left out
where it has none, because a navigation item must name something. Resolution of an entry's
destination is deferred to `EPUBWriter.finish`, where `SpinePacker.pages` holds the finished
page-to-file map: an entry read on page 12 may name page 400, whose spine document does not
exist when the outline is read.

Evidence: [outline-navigation](../measurements/outline-navigation/record.md).

## PageRasterizer and PageAssetWriter: images

- **The source's own picture (#251).** A crop that is exactly one placed JPEG is written as that
  JPEG rather than redrawn: the original stream is what the page holds, and a render can only
  resample it. The magazine's eight extractable figures fall from 2,316,672 rendered bytes to
  316,106, because the render was upsampling a 365 × 322 photograph to 656 × 579. Where a source
  image is higher resolution than the render the bytes go up instead, so the byte budget is
  checked against the real size before the asset is committed and the render is the fallback.
  The conditions are narrow and everything else keeps the render it always had: one placed image
  covering at least 98% of the crop and covered by it to the same degree, nothing else of the
  page's pictures touching that crop, no rotation or skew and an unrotated page, `DCTDecode`
  only, no soft mask, colour-key mask, stencil or `/Decode` array, eight bits a component, a
  device RGB or gray space or an ICC-based one of one or three components, and a JPEG whose own
  frame header states the size and component count the image dictionary does. An ICC profile is
  written into the extracted file as APP2 segments, so its colours stay the page's; nearly every
  `DCTDecode` image in the corpus is ICC-based, so refusing them would leave the rule doing
  nothing. A page whose content stream cannot be walked to the end extracts nothing at all.
  Full-page assets are never extracted: a page image stands for everything on its page, and a
  page can draw text over a photograph. A client that names `.png` for regions gets the render it
  asked for, and `.automatic`'s classifier is bypassed rather than consulted, an extracted
  original having already made that choice.
  Evidence: [embedded-image-extraction](../measurements/embedded-image-extraction/record.md).
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
  policy (`pageImageFallback`; `.always` does not duplicate it). An annotation that did not
  convert reports `annotationsNotConverted` and requires a page reference; a page whose every
  annotation is a converted link requires neither (#247).

Evidence: [raster-dpi](../measurements/raster-dpi/record.md),
[warren-image-encoding](../measurements/warren-image-encoding/record.md),
[client-options](../measurements/client-options/record.md),
[noaa-output-policies](../measurements/noaa-output-policies/record.md).

## Links

- **Converted links (#247).** A link annotation becomes an EPUB anchor. Its rectangle is mapped
  onto characters with #235's geometry: the selection over the annotation's horizontal extent
  within the line's box is the linked text, and the selection from the line's left edge to the
  annotation's start gives the offset, so one occurrence of a word is distinguished from another
  on the same line. The annotation and the line must meet over at least half the line's height,
  and the text PDFKit selects must be the text at the computed offset, or the link is dropped
  rather than placed on guessed words. None of the underline rule's guards against decoration
  apply: the page states outright that a rectangle points somewhere, so a link over a whole line,
  over one letter, or over a line that reads as no sentence is still that link.
- An external target is carried only in the schemes `http`, `https` and `mailto`, at most 2,000
  characters, with no whitespace and nothing XML cannot carry. `javascript:` and `file:` are
  dropped and counted, as is any other scheme and any destination outside this document.
- An internal target names a one-based physical page and is written as a link to that page's
  marker in whichever spine document ends up holding it
  ([decision 0010](decisions/0010-deferred-page-destinations.md)). The token it carries until
  then is padded to a fixed 48 characters, which no resolved href can reach, so resolving it can
  only shorten a body `SpinePacker` has already measured against its byte target.
- One link the page breaks over two printed lines is one anchor: the elements a line join
  separates are merged when only whitespace lies between them. A link whose rectangle covers at
  least half a figure's crop links the figure rather than any text.
- A page whose appearance is preserved whole, and one whose text is an invisible transcription
  over a scan, keep no links: there is no run to anchor, so their links count as unconverted.
- `annotationsNotConverted` states how many links converted and how many annotations did not,
  and is emitted only when something did not. Only such a page requires a page reference, which
  is what that warning has always claimed.
  Evidence: [converted-links](../measurements/converted-links/record.md).

## EPUBWriter, SpinePacker, EPUBTextEncoder

- **Lists (#292).** A run of list items is written as one `<ul>` or `<ol>` — `<ol start="6">`
  where the first item's printed number is not 1 — holding nothing but `<li>` elements, each an
  item's text without its printed marker. A list is packed as one unit, like a table: the writer
  gathers its items until a block that is not an item, a validated chapter start or the end of the
  document arrives, and only then hands the packer the whole list, so a spine document never
  ends inside one; a list larger than the body target is its own document, unsplit. A list may
  contain only items, so a standalone source-page marker that arrives between two items is
  written inside the item it precedes, as its first child, and the marker of an empty page inside
  the item before it; a marker before the first item stands before the list as any marker does,
  and one after the last item travels with what follows the list. A chapter start closes the
  list in one document and the next item opens a new one in the next. The page list names every
  page once, in reading order, wherever its marker was written, and EPUBCheck passes on every
  corpus book that gains a list. An item whose own writing reads right to left carries
  `dir="rtl"`, as a paragraph does.
- **Tables (#210).** A table block is written as an EPUB 3 `<table>`: the rows the page set as its
  column headings become a `<thead>` of `<th scope="col">` and the rest a `<tbody>` of `<td>`, so
  a reading system can announce the heading a value stands under. A cell the page set across
  several columns carries `colspan`; `colspan="1"` is the default and is left out, so the markup
  states only what the page states. The model refuses a ragged table — every row covers the same
  number of columns, or the document is invalid — because ragged markup aligns in no reader. The
  stylesheet collapses the borders, sets cells flush left and top, and rules under the heading row.
- **Base direction (#41).** A paragraph, heading, table or preformatted block whose own text reads right
  to left (`ArabicText.readsRightToLeft`) is written with `dir="rtl"`, a global attribute of
  XHTML5 and valid on each of those elements; nothing else carries the attribute, so a Latin or
  East Asian book's markup is byte-identical to what it was. A book most of whose text blocks read
  that way also states `page-progression-direction="rtl"` on its spine. Together they let a reader
  lay out the numbers, Latin terms and brackets inside each paragraph the way the source page did,
  and turn the book's pages the way it was bound. EPUBCheck 5 passes the Arabic guide with both.
- **Painted underlines (#235).** A page can emphasize a word by painting a rule under it rather
  than by setting an underlined font, which leaves no trace in the text layer. Such a run is
  marked and written `<u>`, which states the appearance the page draws without claiming a link.
  PDFKit's own hit-testing supplies the range — the selection over the rule's horizontal extent
  is the underlined text and the one before it gives the offset — so the 9/11 report's page 161
  marks `gain` and not the `gains` later on the same line. Four guards keep it off what is not
  emphasis: the rule sits inside the line's box rather than above it (a radical's vinculum
  belongs to the line above), starts inside the measure rather than at its left edge (an
  underlined section label is the line's own decoration), spans under 90% of the measure (a
  table's rule), and covers at least two letters on a line that reads as a sentence. Inline
  mathematics inside a prose line is a known exception: four vincula in Wallace are marked, cost
  no text, and would need glyph extents to separate.
  Evidence: [painted-underlines](../measurements/painted-underlines/record.md).

- **Package metadata (#253).** The package document states what the client supplied and, where
  the client supplied nothing, what the document states about itself in its information
  dictionary: `/Title` as `dc:title`, `/Author` as `dc:creator`, `/Subject` as `dc:description`,
  each `/Keywords` entry as its own `dc:subject`, and `/CreationDate` as `dcterms:created`.
  `options.title` and `options.author` win where they are set, as `options.title` always has.
  The two mappings that are not the literal reading of the key names follow XMP's, and the
  corpus shows why: the NBS paper states its whole 433-character abstract in `/Subject`, which
  is a description and not a subject heading; and a creation date is when the file was made, not
  when the work was published — the scans of 1955, 1964 and 1977 works state 2026, 2013 and 2010
  — so it is never written as `dc:date`, which means publication in EPUB 3.
  Every value is untrusted document text, normalized once in `SourceMetadata`: characters XML 1.0
  cannot carry are removed, whitespace runs collapse to one space, and a value states nothing
  when it is blank, has no letter or digit, names its own field, or runs past 1,000 characters
  (dropped whole rather than truncated, because half a sentence misstates the document). At most
  64 keywords are carried, split on commas and semicolons whether PDFKit hands back one string or
  an array, deduplicated without regard to case. A terse value is still a statement: the IRS
  publication's `W:CAR:MP:FP` author converts as written. Metadata taken from the source is a
  function of the source, so byte-reproducible packaging is undisturbed.
- **Printed page numbers (#248).** A page marker and its page-list entry show the page number the
  source prints, where the document states one: `<span epub:type="pagebreak" id="page-3"
  aria-label="i"/>` for a front-matter page a reader sees numbered `i`. EPUB's page-list exists so
  that a reader can jump to a page of the print edition, and a book with front matter used to
  report numbers that matched nothing on its pages. PDFKit resolves the `/PageLabels` number tree
  — roman, arabic, prefixed, restarting — so nothing here parses it. Four corpus documents state
  labels: the Fed report (`a`, `b`, `i`…`vi`, then `1`), the USCIS guide (`front-1`, `cover-i`,
  then `1`), NCA5 and the dietary guidelines.
  A marker inside a continued paragraph shows the same label as a standalone one: it is the same
  marker, and a reader jumping to it is looking for the same printed page. The Fed printed twelve
  of these as physical numbers until #203's cross-page joins made them visible.
  The fragment stays the physical page, because it is an XML id, because internal links aim at it,
  and because two physical pages may print the same number — the dietary guidelines print `1`
  twice, NCA5 prints `i` twice. `ConversionReport` counts and every `ConversionWarning.page` stay
  physical too: a warning names a page a developer can find in the source file. A label is
  normalized as any other stated value and must be at most 32 characters (the corpus's longest is
  `cover-108`); anything else leaves the physical number to speak for the page, as does a document
  that declares no labels at all.
- Output is EPUB 3: XHTML spine documents, a stylesheet, metadata, navigation (`OutlineReader`), a
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
| `ocrUsed` | Recognition replaced the page's text with at least one recognized line. With `ocrLanguageCorrection` on, the message says the text was read with language correction on and that a misread code, number or name may have been changed to a plausible word (#108). |
| `ocrFailed` | Recognition threw, or succeeded and read nothing: the page became an image, the compared layer was retained, or a drawn-text page kept its crops. |
| `incompleteRecognition` | Recognition replaced the page's text and its final reading still leaves at least 8 rows holding at least 20% of the page's text-shaped ink outside every recognized line (#116). The message gives the share and says whether the band retry had already run. Not emitted for a reading the conversion discarded. |
| `uncertainHyphen` | A line-end hyphen neither the vocabulary nor the lexicon could decide is retained; once per page (`HyphenRepair`). |
| `furnitureRemoved` | A repeated header, footer or folio was omitted from this page (`FurnitureDetector`). |
| `imageRegion` | Figures, tables or equations on the page are carried as crops ("Graphical regions retain source appearance as images; their internal text does not reflow."), or a source-page reference accompanies reflowed text ("A source-page reference image accompanies reflowed text to preserve all visual content."). |
| `pageImageFallback` | The page is preserved as one image and does not reflow (rotated, unsupported, unrecoverable or empty-recognition pages). |
| `unsupportedGraphics` | Unsupported or excessive drawing operations require the original page image. |
| `emptyPage` | The page's content stream draws nothing at all: no extracted text, no visible text-showing operator, no painted region (a white ground is not one) and no annotation. A blank page is still carried as an image, so `pageImageFallback` accompanies it. |
| `complexLayout` | The recursive whitespace cuts reached their depth limit before they had separated the page's content; what remained keeps the order it was extracted in (`LayoutReconstructor.ordered`). |
| `annotationsNotConverted` | Visible annotations exist: a page image preserves them (or references are disabled); link and form interactions are not reconstructed. |
| `unreadTableCells` | Recognition located a table on the page and transcribed under half of the grid it returned, so the table's rows, columns and cells are not reconstructed (#31). One warning per such table, beside the picture that preserves it; the message states the share transcribed and the size of the returned grid, never the page's own shape. |
| `referenceImageOmitted` | Analysis recommended a supplementary source-page image and client policy omitted it. |
| `unverifiedTextLayer` | Existing text over a page-sized graphic stands unverified ("Transcription, tables, numbers and reading order may be inaccurate."); a review signal, not an OCR confidence score. |
| `implausibleTextLayer` | An inherited image-backed layer failed the word, misread or ink test, under every policy (`TextLayerPlausibility.message`). |
| `implausibleRecognition` | Recognition of a page did not read as English and was discarded (`TextLayerPlausibility.recognitionMessage`). |
| `damagedTextEncoding` | A font without a usable Unicode mapping is present and the words fail the English statistics; the message is emitted after the recognition outcome is known and says whether recognition replaced the text, the text is retained, or it was discarded and the page became an image (#221). |

Messages whose tail depends on `referenceImages == .never` say "read the source PDF instead" in
place of the accompanying page image.

## Native magazine panels and reading units

`TextBackdrop` examines individual paints before they form crop bounds. A flat rectangular
fill or an explicitly stroke-only frame behind a wrapped native paragraph is decoration;
pattern fills, complex silhouettes and raster pictures remain graphics. A page-sized axial
shading is treated as a backdrop only when both ends extend and its transformed axis spans
at least three quarters of the page's width or height. Radial and mesh shadings keep their
required source crop, including when supplementary reference images are disabled. Backdrop
removal recommends a source-page reference. A tall sidebar needs substantial native fields
and body prose alongside it; three aligned numeric label/value rows within that proved panel
may reflow while their neighboring chart remains graphical.

Photo prose uses complete native paragraph runs, with at least eighteen lexical words,
three consistent rows and three-quarter-width measures. One row must overlap the picture's
crop; the run can continue beyond the crop. Small-type captions adjacent to photographs form
one paragraph reading unit, preventing their rows from alternating with a neighboring body
column. A gallery requires two to four similarly sized, top-aligned pictures with separate
caption measures; proved gutters survive crop clustering, and each picture precedes its own
complete caption. Display quotations require opening/closing quote marks and several rows
of larger native type; they become one `blockquote`, with an adjacent dash attribution, and
never supply navigation headings.

`PrintedColumns` supplements whitespace cuts with sustained body-text margins when a
crossing title or decorative rule hides the gutter. It requires at least six substantial
rows per column and declines floating content across the middle of their writing. Furniture
aliases within half a point are removed only after repetition proves the canonical running
head or foot; native body overprint removal is unchanged. A painted header band requires
repetition of every native row before the band and its contents leave the page.

`OutlinedInitial` recognizes only a bounded opening-paragraph crop beside an outlined
three-row initial. In declared English it may prepend one high-confidence uppercase letter,
with a lexicon check distinguishing an initial word from a standalone `A` or `I`; native
words never come from recognition. Under `ocr: .never` the initial remains graphical. A
successful recovery reports `ocrUsed` and recommends the source page. Recognition failure
keeps the source initial and native paragraph. This is subject to the host Vision service's
recognition variability.

`RuledTableReader` reads native cells from painted horizontal and vertical borders, including
flat-filled headers and merged cells. Unlike a whitespace table, a ruled grid does not need
numeric values. Cell selections must account for every native non-whitespace character
inside the grid, exactly once; incomplete selections leave the table as a source crop.

## Limits

PDF structure is ambiguous. The synthetic suite and the corpus do not establish general
textbook fidelity: untagged borderless tables, arbitrary equations, complex magazine layouts,
footnote relationships, vertical and right-to-left reading order and damaged font encodings
still need broader qualification. The detectors cannot identify every difficult region. Fonts,
original colors, full tagged-PDF semantics, links and interactive elements are not reproduced.
Smaller graphics and undetected scans can still carry transcription errors. Review warnings and
compare the source before distributing a derived book.
