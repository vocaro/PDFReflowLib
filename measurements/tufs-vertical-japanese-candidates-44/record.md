# TUFS vertical Japanese source candidates (#44)

Two articles from Tokyo University of Foreign Studies' *Trans-Cultural Studies* have
substantial, rendered vertical Japanese body text and explicit CC BY 4.0 statements in
their page footers. Both PDFs are direct publisher downloads, small enough for a fast
source comparison, and were tested with the release converter on 2026-09-24. Neither is
admitted to the corpus gate: the current output silently reverses the order of body
columns and joins text from different columns.

| Article | Direct PDF | Identity | Source review and baseline |
| --- | --- | --- | --- |
| Tomoyuki Hoshino, “二十一世紀に日本語作家として生きる―考えること、ことばにすること,” *Trans-Cultural Studies* 21 (2017) | [Publisher PDF](https://www.tufs.ac.jp/common/fs/ics/journals/2017ics21/23.hoshino.pdf) | 206,229 bytes; SHA-256 `d918a16d011d4da245a3dcf3b344cd0debd6f9a3f9fc1d2f6d07300fed6b75ad`; 3 A4 pages | Rendered physical page 1 compared with the EPUB. `--language ja --no-ocr`: 3/3 reflowed, 0 recognized, 1 image, EPUBCheck 5.3.0: 0 errors/warnings. |
| Hiroko Miyokawa, “聖家族のエジプト逃避行―形ある伝説,” *Trans-Cultural Studies* 23 (2019) | [Publisher PDF](https://www.tufs.ac.jp/common/fs/ics/journals/2019ics23/11.miyokawa_essay.pdf) | 464,824 bytes; SHA-256 `c49eccbee45e2f8466556522255f2bad5941a9403aaa21ad67ce51fd92029d2e`; 6 A4 pages | Rendered physical page 1 compared with the EPUB. `--language ja --no-ocr`: 6/6 reflowed, 0 recognized, 5 images, EPUBCheck 5.3.0: 0 errors/warnings. |

The Hoshino PDF's first page begins its main vertical prose at the upper right with
`新聞記者を辞めてメキシコに行ったのは`. The EPUB puts `伝えようとしても、伝わりません` first, then concatenates prose from the ends and starts of different printed columns. The title and author appear after most of the body text. The Miyokawa PDF's first vertical column opens `マタイによる福音書は、聖家族のエジプト逃避行について`; the EPUB starts with the journal running head and later gives `れるという。` before the opening. These are source-visible reading-order failures, not missing licenses or EPUB packaging errors. The reports contain no `complexLayout` or equivalent warning for this failure.

Both sources state that the author retains copyright and supplies the article under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.ja), with a license URL printed
on the reviewed page. The PDFs, rendered pages, and EPUBs remain in `/private/tmp` and are
not committed. A corpus contract cannot currently assert meaningful vertical prose order;
the [earlier Overleaf candidate](../japanese-tategaki-overleaf/record.md) also failed its
source-order check. A future candidate should enter the lane only with a source-reviewed
contract that catches column order and either a corrected reflow or an explicit readable
image fallback and warning.

## Bounded native-column recovery (2026-09-24)

PDFKit returns Hoshino page 1 as intact vertical selections: its title is a 30-by-527
point box, and the first body column begins `新聞記者を辞めてメキシコに行ったのは` in a 12-by-323
point box at x=430. The body columns proceed toward the left and occupy two vertically
separate bands. The horizontal journal head stands above them; the licence text,
image and folio stand below. `VerticalJapaneseColumns` now labels this source-proven
shape as downward writing, and `LayoutReconstructor` reads the isolated vertical
group in that direction between the two horizontal bands. The gate requires at least
four long, narrow Japanese columns holding most of the page's Japanese characters;
short table heads, one margin label and horizontal Japanese prose do not pass.

The revised three-page Hoshino EPUB was generated with `--language ja --no-ocr` from
the pinned PDF above. Page 1 now emits the journal head, title, author and opening
body column in that source order; the two body bands follow right-to-left. Pages 2
and 3 have other content inside the vertical writing band, so the conservative
rule preserves each as a full-page image with `verticalJapaneseFallback` and
`pageImageFallback` warnings. The EPUB has one reflowed page, two page-image
fallbacks and three image assets; EPUBCheck 5.3.0 reported zero errors and warnings.
The output is `/private/tmp/tufs-hoshino-44-oriented-fallback-v2.epub`, SHA-256
`861c303bf3edfaf6dfc257ea0c279b5d9abea146eeeeeba0b490a22ef07bf4fe`.

Miyokawa page 1 has a horizontal item inside its vertical prose band. Its one-page
EPUB now explicitly preserves the page image, with the same two fallback warnings
and EPUBCheck 5.3.0 clean. The output is
`/private/tmp/tufs-miyokawa-44-p1-fallback-v2.epub`, SHA-256
`79e9da55a43bb69bd74e88fadae977dc2366bf1c33623f6de5a7396f977ad1c5`.

The Overleaf candidate remains unqualified: PDFKit divides its vertical prose into
mostly single-glyph selections, which the intact-column gate intentionally rejects.
This increment does not claim an automatic image fallback for that fragmentation.
