# Validated structures and the remaining list classes (#17, #195, #219)

Implemented against `ebc93fb4` on 2026-09-24. The owner chose paragraphs retaining the
printed citation numbers for NOAA, and grouped Warren endnotes with references linked only
where number and scope are verified; uncertain OCR markers remain unlinked beside the
existing source image.

## Structure tags

The existing paragraph/heading path validates RoleMap, inherited page/MCID association,
ParentTree ownership and complete groups before changing spatial order. The existing Fed
source tests also establish row headers on page 77 and author-supplied alternate text on
page 126's single-image screenshot; page 102's multipart vector chart refuses that ownership.
This change admits the equivalent single-item Figure representations: integer MCID, page
MCR dictionary and one-item array. Form namespaces, wrong pages, multiple content items and
wrong ParentTree owners cannot grant alternate text. The neutral model and EPUB writer keep
heading levels, table header roles and figure descriptions. Unsupported content retains
spatial reconstruction and preserved images; full arbitrary PDF semantics are not claimed.

## Lists and bibliography

#292's list model, CIA verified-number rules and no-one-item-list policy are already on main.
The existing lettered-list tests establish nesting from indentation, not marker family, and
Wallace's source-backed exercise/answer tests establish number order and preservation of the
printed keys. Verified text exercise runs become lists; values and unsupported mathematics
keep their printed keys and source crops rather than acquiring inferred counters.

The hanging bibliography join is already on main. After that join, source-proved numbered
citation entries become paragraphs and keep their printed numbers. Source checks on NOAA
pages 31 and 122 cover both inline and detached markers, long author lists and DOI endings.
These checks pass through ListBuilder as well as reconstruction so the result cannot be
reclassified as a generated list counter.

## Warren endnotes

Source: `GPO-WARRENCOMMISSIONREPORT.pdf`, SHA-256
`341cc3471750c9c3be68b95a34b52f6cbdc86c4392427a8483ee1c6bc53cfc19`.
New source-layout captures cover physical pages 848, 849, 860 and 905. A source sweep reads
all 62 note pages (845–906) through PageReader, accepts their note-column plans and checks
that every extracted line survives exactly once.

A NOTES TO PAGES running head and repeated numeric-marker edges establish two columns.
Each column reads downward, with chapter/appendix bands between runs. Dedented citation
continuations join their entry, including continuation lines whose citation numbers resemble
new markers. Damaged range text can still establish a note-page layout but cannot establish a
link scope. The original marker text is never rewritten: page 848 still carries `I.`, `a.`,
`8.` and `II.` where the inherited OCR misreads numbers. Margin debris and ambiguous rows
remain unlinked. Page 881's `CE 1027, 283. See id. at 475-476.` is one such row: a standalone
PDFKit probe found character rectangles shifted across the gutter and into the next row, so
splitting it from those rectangles was rejected. It remains a separate unlinked text boundary,
with the source image retained. This is not a claim to repair that inherited transcription.

Grouped entries receive stable neutral identifiers and EPUB endnote semantics. Grouping is
page-local: an unowned continuation at a page boundary stays unlinked, and the generic prose
join cannot merge two identified notes. A potential
reference needs a numeric marker supported by both neighboring numbers, a unique matching
note-page range, and an explicit numeric source page label. Plain numbers, mathematical
exponents, existing links and ambiguous scopes are not linked. The writer resolves each link
to the spine document actually holding its target; an entry lost to fallback leaves the
reference's text unlinked. **The Warren PDF has no PageLabels in its catalog**, so this source
does not acquire guessed links based on physical-page offsets. Its uncertain scan text and
source images remain available. Deterministic tests exercise successful cross-spine linking,
missing targets, ambiguous scopes and unsafe/duplicate identifiers.

EPUBCheck rejected an initial use of the deprecated ARIA `doc-endnote` role. The final markup
uses `epub:type="endnote"` and `role="note"`; the complete 61-page intermediate notes EPUB
passed EPUBCheck 3.3 with zero errors or warnings. The complete corpus receipt below records
the final implementation, including the later coverage improvements.

## Regressions found by the full checks

The starting tree had an ungated PDFKit selection in printed-form inspection and a Wallace
page-478 crop test failure: releasing an answer title discarded the evidence needed to split
its columns. The selection now uses NativeTextReader's extraction lock, and the column split
retains the released title as evidence. Existing regression tests cover both. Standalone
probes also lacked VerticalJapaneseColumns or FormBlank in their compilation source lists;
the shared lists now include both. The repeated-conversion harness needed a fresh scratch
build because its cached ZIPFoundation checkout was incomplete.

## Final validation

`WORK=/private/tmp/pdfreflow-goal-repeated-clean scripts/check-all.sh --corpus` passed
all 14 gates in 578 seconds on macOS 27 arm64 (2026-09-24): 971 Swift tests,
258 Python tests, release build, extraction concurrency, 15 standalone probe source lists
and 6 documented builds, generated counts, issue citations, closing commits, fixture EPUBs,
conversion policies, structure-index memory, repeated conversions and all 24 corpus cases.
The corpus lane includes EPUBCheck, source-content contracts, progress and each case's
configured memory ceiling; it does not qualify every page's fidelity or physical-device memory.

The final-runtime [corpus receipt](corpus-summary.json) records each source case's pass,
converter identity, output identity and peak RSS. In that complete Warren output, 6,522
grouped entries cover pages 845–906, with zero speculative reference links; EPUBCheck 3.3
reports zero errors and zero warnings. The fresh combined run reconfirmed every corpus case.
The repeated-conversion rerun measured 1,754.5 leaked objects per conversion against the
existing 4,050-object ceiling; it does not claim the upstream PDFKit leak is fixed.

Only documentation/receipt updates followed the successful combined gate. The refreshed
issue-citation check, generated-count check, measurements policy and `git diff --check`
were rerun before publishing.
