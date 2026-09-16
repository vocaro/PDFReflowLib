# PDFKit loads a tagged document's whole structure tree during text layout

Follow-up to the [page-retention measurement](../page-retention/record.md), 2026-09-15,
macOS 27 / Xcode 27, arm64, plus one physical iPhone 17 Pro Max run. The largest single
memory event in that measurement was FAA's 515 MiB extraction peak, identical under every
retention strategy. This record identifies its cause inside PDFKit, retains a standalone
reproducer, and records a rejected mitigation. No library code changes result from it.
The owner filed it with Apple as **FB24798533** on 2026-09-15 (`submission.json`); a filed report
is not an Apple-confirmed diagnosis, and no fix or workaround from Apple is recorded.

## Finding

On the FAA handbook, the first PDFKit text-layout call on a page that carries `/StructParents`,
in a document whose catalog has `/MarkInfo /Marked true`, allocates about 489 MiB of small
objects. `numberOfCharacters`, `string`, `attributedString`, `selection(for:)` on any
rectangle and `characterBounds(at:)` all trigger it; rendering a thumbnail does not. The cost
is paid once per process: later pages in the same document window cost under 4 MiB, and after
the eight-page window is reopened they still cost under 1 MiB. Releasing the document frees
most of it, but `vmmap` shows about 204 MiB of empty, fully fragmented small-allocation
regions that stay resident afterwards; `malloc_zone_pressure_relief` does not return them.

The device pays the same cost. Converting FAA on the iPhone 17 Pro Max under the spill store
peaks at 517.8 MiB of physical footprint and 793.5 MiB RSS, against 210 MiB for Warren and
236 MiB for NOAA on the same phone. It is the largest known device-side peak in the corpus.

## Bisection

`qpdf --pages` extracts FAA page 2 into a 1.5 MB single-page file that reproduces the full
cost; page 4 extracted the same way costs 1.6 MiB. Editing the single-page file in QDF form
and re-probing `page.string` in a fresh process each time (`bisection.json`):

| Change to the page-2 reproducer | Footprint delta MiB |
| --- | ---: |
| none | 488.7 |
| every font-dictionary edit: Type1 subtype, no descriptor, no ToUnicode, Arial or Courier base font, no Widths, no embedded programs | 488.5 to 488.6 |
| image draws, graphics states or soft masks removed; ICC color space replaced | 488.5 to 488.6 |
| all text removed, empty content stream, empty resources, no transparency group | 487.8 to 487.9 |
| `/StructParents` removed from the page | 0.9 |
| `/StructTreeRoot` removed from the catalog | 1.0 |
| `/MarkInfo /Marked false` | 1.0 |
| full 522-page document with the catalog patched to `/Marked false`, page 2 | 1.1 |

Pages 2, 3 and 5 carry `/StructParents` in the original and cost 489 MiB each in isolation;
page 4 does not carry it and costs nothing. Fonts, JPEG 2000 images, soft masks, color spaces
and the page content are all exonerated. The other corpus books' tagged pages cost 0.3 to
2 MiB, so the cost depends on the shape of FAA's tree, which the library's own reader indexes
at a 120 MB RSS peak and retains at about 38 MiB.

## Rejected mitigation

The library reads the structure tree itself through Core Graphics, so it could hand PDFKit a
clone whose catalog is patched to `/Marked false` through a 569-byte appended incremental
update (`probes/untag.py`; the source file is untouched). Converting the full FAA book from
such a clone with `--reference-images automatic` is not output-neutral and not a memory win:

| Conversion | Peak footprint MiB | Peak RSS MiB | Seconds | Output |
| --- | ---: | ---: | ---: | --- |
| original | 512.0 | 798.9 | 38.5 | reference |
| untagged clone | 682.5 | 1,293.1 | 55.4 | 31 XHTML files and 429 image files differ; 507 reflowed pages instead of 508; one more image, one fewer furniture removal |

PDFKit's line order for tagged documents depends on the tree, and the library's tag-aware
reconstruction matches against those lines, so hiding the tree changes extraction and pushes
pages through slower spatial fallbacks. The approach is rejected. Encrypted documents such as
NOAA could not use it anyway, because the catalog's strings would need re-encryption.

## Implications

- The FAA peak, and any similar tagged document, is a PDFKit property that no retention or
  windowing change in this library can lower. It belongs in device budgets as a floor for
  such documents and in an Apple report (`report.md` is a draft).
- The 204 MiB of fragmented allocator pages left behind persists for the process; a long-lived
  app converting many books pays it once, not per book.
- Vision recognition sets the peak on the CDC comic, and rasterization joins the retained
  model early in reconstruction on NOAA and Warren; those remain the next library-side levers,
  along with streaming blocks to the writer.

## Reproduction

```sh
qpdf corpus/cache/faa-h-8083-25c.pdf /tmp/faa-page2.pdf --pages . 2 --
xcrun swiftc -O measurements/pdfkit-structure-tree/probes/pdfkit-call.swift -o /tmp/call-probe
/tmp/call-probe /tmp/faa-page2.pdf 1 string        # about +489 MiB
/tmp/call-probe /tmp/faa-page2.pdf 1 thumbnail     # about +4 MiB
python3 measurements/pdfkit-structure-tree/probes/untag.py corpus/cache/faa-h-8083-25c.pdf /tmp/faa-untagged.pdf
/tmp/call-probe /tmp/faa-untagged.pdf 2 string     # about +1 MiB
find Sources/PDFReflowLib -name '*.swift' | grep -v -E "EPUBWriter|PDFConverter|EPUBTextEncoder|PDFReflowLibPipeline|PageStore" \
  | xargs xcrun swiftc -O measurements/pdfkit-structure-tree/probes/extraction-steps.swift -o /tmp/extract-probe
/tmp/extract-probe corpus/cache/faa-h-8083-25c.pdf 12 2>/dev/null
```

`feedback/` is the self-contained Swift package prepared as the Feedback Assistant attachment:
the probe, `reproduce.sh`, a README and a fresh `results.txt`. The attachment ZIP adds the
three single-page PDFs (page 2 tagged, page 2 untagged, page 4 control), which are derived
from the public handbook and not committed; ZIP SHA-256 `834b36396a840cff88c253860269304203ff3f2d4a3532feabeb64658794383d`, 3,811,066 bytes.
`probes/pdfkit-call.swift` uses only Foundation and PDFKit; `extraction-steps.swift` and
`attachment-census.swift` compile against the library sources. The QDF edits behind the
bisection table are one-line `re.sub` replacements over `qpdf --qdf` output followed by
`fix-qdf`; the reproducer PDFs are not committed, since they are derived from the public
FAA handbook in the ignored corpus cache. `mutool` and `qpdf` come from Homebrew.
