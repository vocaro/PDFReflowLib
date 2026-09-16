# PDFKit text layout allocates ~489 MB loading a tagged PDF's structure tree

Suggested area: macOS / PDFKit (also reproduces on iOS 27). Type: Performance / excessive memory.
Filed as FB24798533 on 2026-09-15; this is the submitted text.

## Summary

For a tagged PDF (`/MarkInfo /Marked true`) whose pages carry `/StructParents`, the first
text-layout call on such a page allocates about 489 MB of small objects. `PDFPage.string`,
`numberOfCharacters`, `attributedString`, `selection(for:)` and `characterBounds(at:)` all
trigger it; `thumbnail(of:for:)` does not. A single-page extract of the public FAA handbook,
1.5 MB, reproduces it. Removing the page's `/StructParents`, removing the catalog's
`/StructTreeRoot`, or setting `/MarkInfo /Marked false` reduces the same call to about 1 MB.
Fonts, images, soft masks, color spaces and the content stream were all bisected out.

After the PDFDocument is released and the autorelease pool drains, `vmmap --summary` shows
about 204 MB of empty, fully fragmented "Malloc Small" regions still resident;
`malloc_zone_pressure_relief` does not return them.

## Environment

macOS 27.0 (26A428), arm64, Xcode 27.0. Also observed on iPhone 17 Pro Max, iOS 27.0, where a
full conversion of the same 522-page document peaks at 518 MiB of physical footprint.

## Steps to reproduce

1. Download the FAA Pilot's Handbook of Aeronautical Knowledge (public domain), SHA-256
   247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7, and extract page 2:
   `qpdf faa-h-8083-25c.pdf page2.pdf --pages . 2 --`
2. Build the attached 40-line probe: `xcrun swiftc -O pdfkit-call.swift -o call-probe`.
3. Run `./call-probe page2.pdf 1 string` and `./call-probe page2.pdf 1 thumbnail`.
4. Optionally apply the attached `untag.py` to the full document and run
   `./call-probe faa-untagged.pdf 2 string`.

## Expected

Text layout of a page with 138 characters should not allocate hundreds of megabytes, and
loading structure information for one page should not require materializing the whole tree.

## Actual

`task_info(TASK_VM_INFO).phys_footprint` before and after the call:

| Call | Before MB | After MB |
| --- | ---: | ---: |
| `numberOfCharacters` | 12 | 501 |
| `string` | 12 | 501 |
| `attributedString` | 12 | 501 |
| `selection(for: cropBox)` | 12 | 501 |
| `selection(for: 20x20 rect)` | 12 | 501 |
| `characterBounds(at: 0)` | 12 | 501 |
| `thumbnail(of:for:)` | 12 | 16 |
| `string`, page 4 of the same document (no `/StructParents`) | 12 | 13 |
| `string`, catalog patched `/Marked false` | 12 | 13 |

Attachment: `PDFKitStructureTreeProbe.zip`, a Swift package with the probe, `reproduce.sh`,
the three single-page PDFs (tagged, untagged, control), a README and a fresh `results.txt`.
