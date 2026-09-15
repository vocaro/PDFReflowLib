# EPUB test reader

The optional local reader opens a PDFReflowLib EPUB without importing it into an external book library. It supports scrolling through complete chapters, Previous/Next chapter,
EPUB contents, physical source-page navigation, text size and reading-width controls. It is a
development tool for human verification, separate from the shipped conversion library.

From the repository root:

```sh
scripts/view-pdf-reflow.sh /path/to/output.epub
```

For a retained comparison bundle, pass its `pdfreflow.epub` file. Open the printed localhost URL.
The default port is 8768; use `--port 8772` if another process occupies it. The reader and
comparison viewer can remain open together. No Xcode build, Poppler installation or conversion
is needed to read an existing EPUB. Python 3.11+ and a modern browser are sufficient.

The equivalent direct Python command is:

```sh
python3 Tools/view_epub.py /path/to/output.epub --port 8768
```

The command verifies the reader's vendored file identities, copies the EPUB into a temporary
workspace, checks and extracts the archive, and serves only that workspace on `127.0.0.1`.
Ctrl-C stops the server and removes its temporary copy. The source EPUB is never modified.
The original download link returns the exact archive; its SHA-256 appears in the terminal and
the book title's tooltip. Nothing is uploaded. Browser state is temporary;
there is no annotation library, saved reading position, account, DRM support or synchronized shelf.

## Rendering and limits

[foliate-js](https://github.com/johnfactotum/foliate-js) supplies EPUB container, metadata, spine
and contents parsing at pinned commit `78914aef4466eb960965702401634c2cb348e9b1`. The
package carries only its MIT-licensed EPUB parser and CFI dependency, with identities in
`Tools/epub-reader/assets.json` and the license text beside the files. It does not load foliate's
full pagination UI, ZIP handler or non-EPUB format loaders. The test shell uses browser chapter
scrolling. No new Swift package dependency is introduced.

The parser reads the original EPUB resources. The browser displays whole chapters using the
comparison harness's XHTML-to-HTML serialization: non-void self-closing tags expand, including
source markers inside joined words, while text, emphasis, source CSS and image references
remain intact. The selected text size changes the body's font size. This is a useful visual
check, not independent EPUB conformance validation or a substitute for the production reader.
Use EPUBCheck for conformance and test integration in each consuming application.

The Contents menu comes from the EPUB's own navigation. Chapter numbering follows its spine,
which can differ from a source book's chapter numbering because PDFReflowLib splits long content.
Source-page navigation uses the converter's physical PDF page markers across the complete book,
not just the comparison tool's selected review pages. A marker can sit inside a paragraph;
preceding context can remain visible when scrolling reaches the chapter's end. The source-page
selector follows scrolling, while Contents is a jump menu rather than a current-heading label.

Admission deliberately covers PDFReflowLib's current XHTML/CSS/PNG output profile, with source-page
markers. This is not a general-purpose EPUB importer. Active markup, script files, resource-loading
CSS, external links, unsupported resources, invalid archive paths and oversized archives are
rejected before serving. Chapter frames also disable scripts, forms and remote resources through
sandboxing and Content Security Policy. The parser reads only inventoried publication resources.

## Verification

```sh
python3 -m unittest discover -s Tools -p 'test_*.py'
```

Reader controls verify the vendor pin, reject active/external content, preserve original EPUB
and XHTML bytes, keep source navigation, and protect existing output directories. The shared
comparison tests cover archive limits/path safety, marker preservation and HTTP restrictions.
Visual checks remain necessary for text, images, navigation and readability at narrow widths.
