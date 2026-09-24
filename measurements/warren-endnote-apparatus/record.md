# Warren endnote apparatus prerequisite (#219)

Read-only qualification on 2026-09-24, `main` at `a7827fbc`. The pinned source is `corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf`, SHA-256 `341cc3471750c9c3be68b95a34b52f6cbdc86c4392427a8483ee1c6bc53cfc19`. The one-page physical page 848 extraction, made with `pdfseparate -f 848 -l 848`, is SHA-256 `a22b937fab435158e73488429b7da680a7df8be3032d4041e8040c0b377ba0ef`. Its one-page EPUB is SHA-256 `5744fdafd2e0df6d4cb8d0b37a3bc57905596f7086433657a29912bd85f70668`. The PDF/EPUB and source render remain in `/private/tmp`, outside the repository.

The printed page 848 has two note columns. The left opens notes **1, 2, 3, 4 … 66** and the right continues the previous note before **67 … 122**. Visual review of the source render establishes that its first four markers are 1, 2, 3, 4, and the marker between 10 and 12 is 11. The inherited text returns `I.`, `a.`, `8.`, `4.`, and `II.` at those positions. `pdftotext -layout` on pages 860, 900 and 905 likewise shows dense two-column note pages headed `NOTES TO PAGES …`, not `NOTES TO CHAPTER N`.

The current page-848 EPUB reports one reflowed page, `unverifiedTextLayer` and a source-page image. Its XHTML begins `I.` as a preformatted block, interposes right-column continuation prose, emits `a.` and `8.` separately, then alternates `4.`, `67.`, `5.`, `68.`. Wrapped note lines become independent paragraphs. For example, the source's note 69 wraps onto `226 (Miller).`, which is a separate paragraph after note 69's preformatted opening. The source's note 11 is an unmarked `II. Ibid.` paragraph. The note's number and its continuation therefore cannot be inferred from the current block sequence.

`NumberedNoteDetector` currently requires a native, nonsynthetic, nonimage page headed `NOTES TO CHAPTER N`, one shared opening edge, and consecutive numeric markers. Warren's page fails the heading, two-column and marker conditions; the conversion also warns that the text layer is unverified. The abandoned-branch chain through `9803329` built scoped linking for cleaner 9/11 chapter notes, but does not establish Warren's `NOTES TO PAGES` ownership or recover OCR-misread numbers. A `NoteLinker`/writer port would either be unreachable for Warren or risk linking a call to the wrong note.

Before Warren entries can become keyed notes, a source-backed reader must establish column order and note continuation boundaries, then either verify each printed number or leave uncertain markers unlinked. This must hold across the mixed inherited-text and Vision-replaced endnote run; [the OCR text-loss measurement](../ocr-text-loss/record.md) found Vision replacing 16 of pages 850–880. No production change or note link is proposed by this record. #219 stays open.

Reproduce the bounded checks:

```sh
pdfseparate -f 848 -l 848 corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf /private/tmp/pdfreflow-warren219-848.pdf
.build/debug/pdf-reflow /private/tmp/pdfreflow-warren219-848.pdf /private/tmp/pdfreflow-warren219-848.epub
pdftotext -f 848 -l 848 -layout corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf -
pdftoppm -f 848 -l 848 -r 120 -png -singlefile corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf /private/tmp/pdfreflow-warren219-848
```
