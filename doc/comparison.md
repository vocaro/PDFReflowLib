# Comparing PDF conversion quality

`Tools/compare_pdf.py` builds a local review bundle from one PDF snapshot. The viewer places
PDFReflowLib's EPUB beside Poppler's `pdftohtml` output, with an optional third pane rendered from
the original PDF by `pdftoppm`. It is a manual development aid, not a fidelity score or a speed
benchmark. Poppler can make different mistakes, and both Poppler views share the same parser.
Use the original PDF in an independent reader when the reference raster is in doubt.

## Running a comparison

Requirements: macOS, Python 3.11+, full Xcode 27, and an independently installed Poppler with
`pdftohtml` and `pdftoppm` on `PATH`. Poppler is an optional, GPL-licensed external development
tool; it is not linked, vendored, bundled, or added to the Swift package or app dependencies.
The harness does not install tools or download documents.

From the repository root:

```sh
swift build -c release
python3 Tools/compare_pdf.py --converter .build/release/pdf-reflow \
  --pdf /path/to/book.pdf --pages 1,16,90-92,121 \
  --output /tmp/book-comparison --serve
```

The repository shortcut builds the release executable before invoking the same tool:

```sh
scripts/compare-pdf-reflow.sh --pdf /path/to/faa-h-8083-25c.pdf \
  --pages 1,16,91,121,176,401,511 --output /tmp/faa-comparison --serve
```

Select the installed Xcode using `DEVELOPER_DIR` if needed. Paths containing spaces need shell
quotes. The output directory must be new. `--pages` accepts one-based **physical PDF page
numbers**, inclusive ranges, or `all` (the default), not printed page labels. The FAA corpus
manifest supplies useful review pages. Start with a small selection for long books: each page
requires two Poppler conversions and a source raster, and the retained bundle can be large.
Poppler may append the book's entire outline even when converting one selected page.

PDFReflowLib converts the complete book, retaining whole-book vocabulary, recurring-header and
paragraph-continuation context. `--pages` only limits Poppler and reference preparation. The
terminal relays the converter's progress and then reports prepared pages separately; these are
different workloads. `--no-ocr` disables PDFReflowLib OCR; Poppler has no OCR step. Scans can
therefore produce image-only Poppler output without indicating a harness error.

`--pdftohtml` and `--pdftoppm` accept explicit executable paths. `--timeout` bounds each command
(default 1,800 seconds); interruption or timeout kills and reaps an active child. Failed bundles
retain diagnostics and a failed status rather than appearing ready. No existing review is
overwritten. Converter input/output resource limits still apply; these do not impose a total
disk or runtime budget on Poppler.

`--serve` starts a server after generation, bound only to `127.0.0.1`, until Ctrl-C. Open the
printed URL; `--port` selects a different port. To reopen retained results without conversion:

```sh
python3 Tools/serve_comparison.py /tmp/book-comparison --port 8765
```

Use this server rather than opening `index.html` as a file. The viewer fetches a local manifest,
and the server supplies the document security policy. It disables scripts, external resources
and forms in previews; sandboxed frames prevent top-level navigation. Source hyperlinks are
inert in the preview. Archive extraction rejects traversal, symlinks, duplicate/case-colliding
paths and oversized content. The server rejects symlink escapes and directory listing. This is
a loopback development server, not a public hosting service. The bundle contains a copy of the
input and its derived content; keep it local unless you intend to share those materials.

## What the views show

- **PDFReflowLib:** the actual EPUB chapter, aligned to the selected source-page marker. Neighboring
  pages remain present, and a marker can occur inside a paragraph or a joined word. Near the
  end of a chapter the browser may retain preceding context because scrolling reaches its limit.
  Browser previews serialize XHTML as HTML with expanded non-void tags and a UTF-8 declaration;
  text, inline style nesting, image references and EPUB CSS are retained. Original XHTML and the
  EPUB archive remain unchanged. The viewer does not reconstruct or repair the output again.
- **Poppler simple HTML:** `-noframes -enc UTF-8 -f N -l N`. Generated text, line breaks, styling
  and extracted images remain as emitted. This helps expose reading-order and word-join issues.
- **Poppler positioned HTML:** the same arguments plus `-c -s`. Absolute positions and page
  backgrounds retain more of the source appearance. The viewer scales this page to fit, which
  does not make it reflowable or establish its text reading order. `-s` implies complex output
  in the tested Poppler, so the simple mode deliberately omits it.
- **Original page:** a PNG rendered by `pdftoppm -singlefile -scale-to 1400 -png` for that physical
  page. This is a reference rendering, not a third conversion to reflowable content.

Page selection and Previous/Next move all panes to the same physical page. Panes scroll
independently because the outputs have different lengths. Reading-width presets set the EPUB
and Poppler frame width; an oversized preset scrolls horizontally rather than silently shrinking
it. The original reference scales with its pane. Return to page start resets the comparison.
PDFReflowLib warnings are filtered to the selected page; the complete report remains available.

Record reading order, lost/duplicated text, hyphen decisions, images/labels, and fallback scale
under **Run details & review notes**. Notes are held in the current tab; export them before
closing. The JSON export records source, converter and EPUB identities with per-page observations.
It does not upload anything. Turn confirmed findings into source-derived regression cases rather
than asserting that either converter's output is correct by definition.

## Reproducibility and tests

`comparison.json` records source SHA-256/bytes, converter SHA-256, harness source identities,
platform, Poppler version, exact commands, exit status, durations, selected pages and the
conversion report. Each command retains stdout/stderr; the bundle also retains the input PDF,
EPUB, extracted originals, browser previews, Poppler output and source rasters. Recorded
durations have different scopes and include polling overhead; use the dedicated memory harness
for converter performance qualification.

```sh
python3 -m unittest discover -s Tools -p 'test_*.py'
```

The comparison controls cover page selection, inline source boundaries, browser serialization,
asset paths, archive safety, child failure/timeout, output protection, failed-run reporting and
HTTP policy/path containment. They require neither Poppler nor a listening socket. Actual
Poppler/EPUB rendering is a separate integration and visual check using the synthetic fixtures
and selected real-document pages.
