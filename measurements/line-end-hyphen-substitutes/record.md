# Line-end hyphen substitutes

`gpo-911-2004`'s text font encodes the hyphen it draws at a line end as `=`, so every word the
page breaks arrives from PDFKit as `hijack=` + `ers`. The hyphen-repair apparatus looks for a
hyphen, so none of those words was ever joined and the reflowed book printed the equals sign
inside them. This record measures the evidence that decided the repair in #233.

Host: macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max, 36 GB. Library source at `e57b2ca`
plus the #233 change. Measured 2026-09-20 with the release CLI at library defaults.

## The book's own characters say which glyph the hyphen is

Every candidate character in the 585-page book, counted over the lines the reader keeps:

| Character | Occurrences | Ends a line after a letter | Next line opens lowercase |
| --- | ---: | ---: | ---: |
| `=` | 1,004 | 994 (99.0%) | 993 of 994 |
| `/` | 878 | 4 (0.5%) | 3 of 4 |
| `_` | 25 | 1 (4.0%) | 1 of 1 |
| `*` | 6 | 0 | 0 |

The separation is three orders of magnitude, so the 95% share the rule requires is not a delicate
threshold: `/` would have to move from 0.5% to 95% to be mistaken for a hyphen. The ten `=` that
do not end a line are the query strings of cited web addresses (`?ReportID=145`,
`?theme=45&content=3498`); they are why the rule is a share rather than unanimity, and because
only a line-final occurrence is rewritten they survive the repair untouched.

## What the repair changed

| | Before | After |
| --- | ---: | ---: |
| `=` in the reflowed text | 988 | 19 |
| Words broken across a line by `letter= ` | 969 | 0 |

The 19 that remain are 10 genuine `=` inside cited URLs and 9 words broken at a `</pre>`–`<p>`
boundary, where the halves are in different blocks and no join is attempted at all. Those nine
would read `direc-` / `tion` rather than `direc=` / `tion` if the block boundary were the only
problem; they belong to the preformatted/list classification work, not here.

Word counts move the way the join predicts: `terrorist` 541→552, `operatives` 161→171,
`government` 399→408, `hijackers` 255→258, `organization` 138→141, `personally` 9→11.

## No other book is touched

The full corpus lane passes (18 of 18). Comparing the reflowed text of every case against the
same lane before the change, **17 of the 18 books are character-for-character identical** and only
`gpo-911-2004` differs. No other corpus book has a character that qualifies, which is the
intended outcome: the rule is document-wide evidence, and a book that means its characters keeps
them.
