# Warren report as a gated corpus case (#202)

Build: release CLI from `a7a0c50` (`swift build -c release`), SHA-256
`11e33efd7cb6680e79681360a7766f2a0e30106563aa2c44038a04cefb89f170`. Mac: Apple M5 Max, 18 cores,
36 GiB, macOS 27.0 arm64. Five other agents were converting corpus books at the same time (load
average 11–14), so times and peaks are loaded-machine figures. Library defaults throughout; no
converter option was passed.

## Runs

| Run | Conversion wall | CPU | Peak RSS | Peak footprint | EPUB bytes | Entry bytes | Headroom under 512 MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1, `evaluate-real-document.py` | 535.4 s | 483.2 s | 1,114.6 MiB | 516.6 MiB | 531,823,415 | 536,550,940 | 319,972 B (0.060%) |
| 2, `run_corpus_regressions.py --case gpo-warren-1964` | 492.3 s | 453.9 s | 1,081.0 MiB | 510.9 MiB | 531,823,416 | 536,550,940 | 319,972 B (0.060%) |

Both runs exit 0 with 920 pages, 932 images (all JPEG), 910 reflowed pages and 17 recognized
pages, and EPUBCheck reports 0 fatals, errors, warnings and infos. The progress check passes
(3,025 events). Run 2 is the lane itself: EPUBCheck and the content contract (175 checks on 21
pages) add about 7 s, so the whole case takes about 8.3 minutes; the output directory is 514 MB.
The memory gate passed on its first attempt, 1,081 MiB against the new 1,536 MiB ceiling. The 1,800 s
default evaluator timeout is 3.4× the slower run.

The two conversion reports are equal, the ZIP entry lists are equal, and every entry is
byte-identical except `package.opf`, which differs only in the generated `urn:uuid` identifier and
`dcterms:modified`, the two values the reproducibility check pins. That includes the 17
recognized pages and pages 291 and 384, which once reconstructed two ways (#140).

## Budget

The 512 MiB default counts entry bytes. Warren fits it by 319,972 bytes, 3,770 more than the
316,202 recorded under #193 (`measurements/image-encoding-default/record.md`). Image entries are
533,625,871 bytes of it. The case runs with the
defaults every client gets, so no budget override was added: a change that adds about 312 KiB of
image bytes to this book fails the lane, and that failure is the signal that the change costs scanned
books output size. `excludedFullConversions` is now empty.

## Contract review

Pages were chosen to cover the book's classes and were read against 90-dpi Poppler renders of the
source pages: cover with signature annotation (1), title page (7), contents (21), chapter
opening and typed prose (29, 30, 50, 100), photograph exhibit with caption (90), map exhibit
(103), handwritten letter facsimile (291), photograph spread (384), blank page (498), witness list
(520), handwritten hospital notes (549, 553, 556), typewritten facsimile (636), two-column notes
(885, 890), index (910) and back cover (920). Only correct passages, order, paragraph continuity
across page markers, image presence, source-page references and warning codes are pinned.

## Defects seen and not pinned

- **Paragraph breaks lost on dense pages.** 159 pages carry a paragraph over 2,500 characters.
  Page 100 runs three source paragraphs ("Another employee of the Union Terminal Co." and "As the
  motorcade proceeded" each open an indented paragraph) into one, as does page 122. Page 30,
  without note markers, keeps its paragraphs.
- **Numbered lines become `<pre>`.** 7,080 `<pre>` blocks: each numbered note (`415. 8 H 232
  (Delgado).`) and page 50's points 10 and 11 open a preformatted block, and a wrapped note's
  later lines become a separate `<p>`.
- **Recognized handwriting is noise.** Pages 549 and 552–556 fail the plausibility test and are
  recognized again; Vision returns mixed-script text (Arabic and Cyrillic letters) and five of the
  pages carry headings made from it (`Tag De Praciy Glii tant ami She` on 553).
- **Typewritten facsimile layers pass as text.** Page 636's inherited layer is character noise
  (`BS3d v^.ere his things ci^ht be kept`) and reflows with only `unverifiedTextLayer`.
- **Wrong alternative text on photograph crops.** Page 90's photograph, and crops on 552, 556,
  636 and 637, are described as "Mathematical expression".
- Known from before: inherited OCR errors (`bis known contacts witb tbe`, #7), note markers read
  as `^^`, and index entries run together in one paragraph.

## Files and commands

```sh
python3 tools/evaluate-real-document.py --case gpo-warren-1964 \
  --pdf corpus/cache/GPO-WARRENCOMMISSIONREPORT.pdf --converter .build/release/pdf-reflow \
  --output $OUT/warren1 --epubcheck /opt/homebrew/bin/epubcheck --timeout 3600
python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow \
  --epubcheck /opt/homebrew/bin/epubcheck --output $OUT/lane-warren --case gpo-warren-1964
python3 measurements/warren-gated-corpus/compare_runs.py $OUT/warren1 $OUT/lane-warren/gpo-warren-1964
```

`run1-result.json.gz` and `run2-result.json.gz` are the two evaluator receipts (run 1 predates the
case memory ceiling, so it has no memory gate), `run2-content-assessment.json` is the lane's
content result and `repeat-comparison.txt` is `compare_runs.py`'s output. Both EPUBs were deleted
after these numbers were recorded.
