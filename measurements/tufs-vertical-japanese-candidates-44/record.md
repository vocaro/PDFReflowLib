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
