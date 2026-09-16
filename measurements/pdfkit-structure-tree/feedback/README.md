# PDFKit text layout allocates ~489 MB loading a tagged PDF's structure tree

`page2-tagged.pdf` is page 2 of the public-domain FAA Pilot's Handbook of Aeronautical
Knowledge (faa-h-8083-25c.pdf, SHA-256 247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7),
extracted with `qpdf --pages`. Its catalog has `/MarkInfo /Marked true` and the page carries
`/StructParents 2395`. `page2-untagged.pdf` is the same file with one appended incremental
update that sets `/MarkInfo /Marked false`; nothing else changes. `page4-control.pdf` is
page 4 of the same document, which has no `/StructParents`.

Run `./reproduce.sh` (or open the package in Xcode and run the `StructureTreeProbe`
executable with the arguments `<pdf> 1 string`). Each call runs in a fresh process and prints
the process physical footprint (`task_info(TASK_VM_INFO).phys_footprint`) before and after
the call, and again after the document is released and `malloc_zone_pressure_relief` runs.

Observed on macOS 27.0 (26A428), arm64, Xcode 27.0, and on iPhone 17 Pro Max, iOS 27.0:

- Any text-layout call on `page2-tagged.pdf` (`numberOfCharacters`, `string`,
  `attributedString`, `selection(for:)` with any rectangle, `characterBounds(at:)`) grows
  the footprint by about 489 MiB. `thumbnail(of:for:)` grows it by about 4 MiB.
- The same calls on `page2-untagged.pdf` and on `page4-control.pdf` grow it by about 1 MiB.
- After the document is released, about 204 MiB of empty, fully fragmented "Malloc Small"
  regions remain resident (`vmmap --summary`); `malloc_zone_pressure_relief` does not
  return them.
- In the full 522-page document the cost is paid once per process; later pages cost under
  4 MiB. A complete conversion of the document on the iPhone peaks at 518 MiB because of it.

Bisection over the single page (fonts, JPEG 2000 images, soft masks, color spaces, the
transparency group and the entire content stream removed one at a time) leaves the cost
unchanged; only `/StructParents`, `/StructTreeRoot` or `/Marked` change it. `results.txt`
is a fresh run of `reproduce.sh` on the machine above.
