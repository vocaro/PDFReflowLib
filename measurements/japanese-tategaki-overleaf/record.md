# Vertical Japanese review source for issue #44

## Source

The two-page [Japanese tategaki template on Overleaf](https://www.overleaf.com/latex/examples/ri-ben-yu-zong-shu-kitenpureto-slash-japanese-tategaki-templete/wgpxjxbbbhyh) is listed there as Creative Commons CC BY 4.0. The reviewed PDF is the direct download from that page, 239,493 bytes, SHA-256 `387b3e178eb50b4990df9396728623781950dfc589f956250efc509bb1c417fa`. The PDF and generated EPUB are not stored in this repository.

Rendered pages show Japanese prose in vertical columns read from top to bottom, starting at the rightmost column. Page 1 has a vertical title and author to the right of the prose. Page 2 continues the sentence at the end of page 1: page 1's last body column ends `装飾されべ` and page 2's first column begins `きはずの顔が`.

MuPDF's structured-text extraction finds nine body columns on page 1 and thirteen on page 2. Their left x coordinates descend from 184.691 to 41.229 points on page 1 and from 365.354 to 150.161 points on page 2. A body column begins `吾輩は猫である︒名前はまだ無い︒` after its section number. The PDF pages have no page rotation; the extracted Japanese lines report horizontal writing mode and direction even though each character is positioned vertically. A vertical-layout detector therefore needs character geometry rather than a page rotation or writing-mode flag alone.

## Baseline result

The reviewed baseline EPUB is `/private/tmp/japanese-tategaki-baseline-retry.epub`, SHA-256 `57fca5f09763751fa1c86797fa6f1ec8f1688a1953e45172c0868bfe78b92fa8` (3,980 bytes), produced with `--language ja --no-ocr`. The two pages were reflowed with no image fallbacks. EPUBCheck reported zero errors and zero warnings. These checks establish a valid EPUB package, but its prose reading order is wrong.

The first page's XHTML starts with `こ上て何のか泣`; the title `吾輩は猫である` appears as heading block 106, after the scrambled body. Page 2 starts `てをの`. The EPUB groups characters across horizontal rows instead of following the printed vertical columns. The Japanese-script character multiset is preserved exactly (721 source and 721 EPUB characters), but just **5 of 705** consecutive three-character sequences from the source body order occur in the EPUB order. This is a diagnostic of the failure, not a general fidelity score: it excludes punctuation, numerals, Latin text, title, and author; repeated sequences can overlap by chance; and source body order is inferred from this document's column geometry.

## Reproduce and review

With the pinned PDF and baseline EPUB at the paths above, run:

```sh
python3 measurements/japanese-tategaki-overleaf/measure.py \
  /private/tmp/japanese-tategaki-overleaf.pdf \
  /private/tmp/japanese-tategaki-baseline-retry.epub \
  > /private/tmp/japanese-tategaki-review.json
diff -u measurements/japanese-tategaki-overleaf/review.json \
  /private/tmp/japanese-tategaki-review.json
```

The script verifies the source checksum and derives the column measurements and EPUB order from the artifacts. It uses source-specific bounds to distinguish body columns from the title, author, page number, arrow, and URL. [`review.json`](review.json) records the complete measured result, including each column's bounds, opening and closing text, and text checksum. It is review evidence, not a production acceptance test.

Issue #44 remains open. The [source-reviewed candidate contract](../../corpus/japanese-tategaki-overleaf-review.json) records these targets and explicitly remains unqualified for an active corpus gate. A future conversion should place the title before body prose, read each body column top to bottom from right to left, preserve the page 1 to page 2 continuation, and keep page furniture separate. The source and EPUB should be reviewed visually and with reading-order assertions before this case becomes a regression fixture.
