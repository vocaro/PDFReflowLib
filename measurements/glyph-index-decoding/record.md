# Index-named glyphs decoded from the document's own words (#143's port, #226)

Corpus `census-rrs2002-01` (`corpus/cache/rrs2002-01.pdf`, SHA-256
`0f97380ae4308581bd70013b7317faafd7c217654236bd31d1448f26eae56905`). Tier: deterministic Apple PDF
stack, macOS 27.0 arm64, release CLI, library defaults unless stated. Date 2026-09-19, on `f806309`
("Stop the spine-continuity contract from pinning where the packer ends a document").

#143's decoder was never on `main`: it was closed by `a4b0f30` on the abandoned coordination
branch, which `dd160b4` merged with the `ours` strategy without changing `main`'s tree
([decision 0005](../../doc/decisions/0005-abandoned-coordination-branch.md), #226). This is its
hand-port, adapted to `main`'s pipeline, with the relaxed gate #149 item 2 asks for. Nothing was
copied from the branch's records: every offset below was re-measured against the file and against
150- and 110-dpi Poppler renders (`pdftoppm -r 110 -f N -l N -png`).

## What the file states, and what it does not

The pages were extracted with `qpdf --qdf --object-streams=disable` and every font dictionary,
`Encoding`/`Differences` array and page content stream read directly.

Every body font is a Type 1 font with an embedded `FontFile3`, no `ToUnicode`, and an `Encoding`
dictionary without `BaseEncoding` whose `Differences` renumber the codes from 1 and name them
`G<n>`: `dcr10084` has 80 such codes (`[1 /G90 /G108 /G111 /G100 …]`), `dctt10075` has 24
(`[1 /G126 /G122 /G108 /G111 /G100 …]`), `cmmib10084` has one (`[1 /G66]`). The embedded CFF
charset names its own glyphs the same way, its built-in encoding places `G<n>` at code `n`, and the
descriptor's `CharSet` lists the same names. **Nothing in the file states which character a slot
holds**, so decoding the glyph names or the charstrings cannot work: the names are the indices.

PDFKit reports a one-letter-prefix index name as the character whose code point is the index, for
an index in 33–126 or 161–255, and as nothing anywhere else. That is why `dcr`'s letters come out
three on (`Wklv sdshu`) and its ligatures vanish (`G30`, `G31` report nothing, so `files` reads
`ohv`).

## The offsets, verified glyph by glyph against the renders

| Font | Rule | Evidence in this file |
| --- | --- | --- |
| `dcr`, `dcti`, `dcbx`, `dctt` | Cork (T1) slot + 3 | page 20's `G100 G113 G103` = `and`; `G30` is the ff ligature at T1 27; page 2's `G126 G122 G108 G111 G100 G112` = `{willam`'s opening characters |
| `cmr10084` | OT1 slot + 3 | `G64` = `=`, `G46` = `+`, `G43` = `(`, `G52` = `1`, `G44` = `)` |
| `cmsy10084` | OMS slot + 3 | `G115` = the radical at OMS 112, matching page 20's `√1 + d` |
| `cmmib10084` | OML slot + 3 | `G66` = the star at OML 63, page 2's title footnote mark |
| `cmmi10084` | OML slot + 0, Latin letters only | `G65`–`G90` are `A`–`Z`, `G97`–`G122` are `a`–`z`; `G134`, `G140`, `G149`, `G154`, `G158`, `G163`, `G168` are Greek and symbols no encoding in the file explains (`G140` draws the Σ of `covariance (1 + d) Σ`) |
| Type 3 `T3` | `c<n>` at + 0 | `c115` draws the subscript `s` of `Z_s` |

Every one of these was read against the render, and every one is **correct**. Only four of them can
be *established from the document*, which is what the library may use: `dcr`, `dcti` and `dcbx`
have thousands of glyphs of English prose each, and `dctt` takes their offset by family
corroboration. `cmr` sets five short words (`Cov`, `Pr`, `max`, `min`, `log`), `cmsy`, `cmex` and
`cmmib` set no letters at all, `T3` sets isolated italic letters, and `cmmi`'s Latin block sets
one- and two-letter variable runs. No statistics over the document's own words can separate their
true offset from a wrong one, and nothing else in the file states it. They stay undecoded, and
their glyphs are written U+FFFD.

## Decodability per page

Counted by decoding every index-glyph show of every page with the offsets above
(`survey.py` in the scratch tree; the counts are reproduced by the same qpdf/regex walk the
decoder's Swift does over Core Graphics):

| Page | Stated | Unstated | Fonts |
| --- | --- | --- | --- |
| 2 | 1983 | 2 | `cmmib` 0/1, `T2` 0/1; `dcbx` 79/79, `dcr` 1841/1841, `dctt` 63/63 |
| 3 | 1425 | 0 | `dcbx`, `dcr` |
| 4 | 2186 | 22 | `cmsy` 0/9, `cmmi` 40/53 |
| 5 | 1849 | 39 | `cmsy` 0/12, `T3`/`T4` 0/9, `cmex` 0/2 |
| 6 | 2463 | 41 | `cmsy` 0/21, `cmex` 0/4, `cmmi` 38/54 |
| 7 | 2454 | 33 | `cmex` 0/13, `T5` 0/5, `cmsy` 0/6 |
| 8 | 2021 | 46 | `cmsy` 0/21, `T5` 0/14, `cmex` 0/6 |
| 9 | 1894 | 62 | `cmex` 0/36, `T5` 0/13, `cmsy` 0/9 |
| 10 | 1546 | 8 | `cmex` 0/6, `cmmi` 80/82 |
| 11–17 | 889–2368 | 0 or 1 | `dc` fonts, with `cmmi`/`cmr` fragments on 13 |
| 18 | 1722 | 75 | `T5`/`T6` 0/24, `cmex` 0/10, `cmmi` 30/68 |
| 19 | 978 | 126 | `cmex` 0/43, `T5`/`T6` 0/32, `cmmi` 15/52 |
| 20 | 238 | 8 | `cmsy` 0/3, `cmex` 0/2, `cmmi` 13/16 |

## Result at library defaults

| | Before (`f806309`) | After |
| --- | --- | --- |
| Recognized pages | 19 (2–20) | 12 (4–9, 11, 16–20) |
| Pages reflowing their own text | 0 | 7 (2, 3, 10, 12, 13, 14, 15) |
| `damagedTextEncoding` | pages 2–20 | pages 4–9, 11, 16–20 |
| Images | 53 | 42 |

Read against the renders of pages 2 and 3:

- **Page 2** (`pdftoppm -r 110 -f 2 -l 2`). Title `Disclosure risk assessment in perturbative` /
  `microdata protection` followed by U+FFFD where the render draws the `cmmib` star; byline
  `William E. Yancey, William E. Winkler, and Robert H. Creecy`; `U.S. Bureau of the Census`; and
  the typewriter line exactly, character for character:
  `{william.e.yancey,william.e.winkler,robert.h.creecy}@census.gov` (#149 item 2). The
  letter-spaced heading reads `1 Introduction`, its word gap restored from the 1.10 em of
  character spacing the source cancels with +1120 adjustments; `re-identiﬁcation`, `conﬁdential`
  and `diﬀerent` carry the ligatures PDFKit drops. `[ 18]` and `[ 5]` keep the source's own
  spacing, which the render shows.
- **Page 3**. `2 Data Files`; `Two data ﬁles were used.`; all sixteen numbered fields in order,
  `12. Aged exemption ﬂag` through `16. Schedule F ﬂag` (recognition read these as `Ilag`);
  `59,315`; `(http://www.census.gov/DES)`; `public-use CPS ﬁle.`

## Page 20 and #149 item 1

The render of page 20 shows `and for different noise proportion parameters d, we compute a masked
data set`, with `d` in math italic, then the display `Z = X + dY.`, then `Since the resulting data
set Z theoretically has covariance (1 + d) Σ, for each d`, a fraction, and `where μ is the (sample)
mean vector of the masked data.`

The decoder reads the prose line's `dcr` glyphs exactly, including the ff ligature of `diﬀerent`.
But its italic `d`, every character of `Z = X + dY.`, the Σ and the μ̄ are drawn in `cmmi`, `cmr`,
`cmsy` and `cmex`, whose offsets **nothing in the document states**. #226's `cmmi` +0 and `cmr` +3
were established by reading a render, which the library may not do. Page 20's eight unstated
glyphs against roughly 330 extracted characters therefore keep its damaged-encoding diagnosis and
its recognition, and #149 item 1 is not reachable from the document's own evidence. Page 20 is the
smallest page in the book, so the same share of unstated glyphs that leaves pages 4, 6, 7 and 10 on
recognition also catches it.

## Pages 11 and 16: #149 item 3, after a decoder runs

Page 16's prose decodes completely (2238 of 2238 glyphs) yet the page keeps its recognition,
because PDFKit reports one drawn row as several overlapping lines with duplicated `t`s (#149
item 3). The two rows affected are exactly the ones #149 names:

```
The first is that the suitable test files are needed. The test
files should have variables in which the distributions are representative of actual
```

Their shows cannot be attributed to a single line, the repair declines, and the rows would
otherwise ship as `Wkh uvw lv wkdw wkh vxlwdeoh whvw ohv duh qhhghg1 Wkh whvw`. `unreadGlyphs`
counts them, so the page keeps #38's path instead. Page 11 loses two lines the same way
(`However, when the perturbations get`, `does a little better than the`). Fixing #149 item 3 would
move both pages off recognition; so would carrying surplus glyphs to the next line of a row, which
page 17's references need (`[2] Dalenius, T. and Reiss, S. P. …` and eleven more). The second of
those is #237, measured below; page 16 is still #149 item 3's and is unchanged by it.

# A row PDFKit splits into a line per column (#237)

Date 2026-09-19, on `da544ad`, same tier as above. Every string below was read against
`pdftoppm -r 150 -f N -l N -png` of the source page.

## What the file draws and what PDFKit reports

TeX sets each of page 17's fourteen references as **one** `TJ` show. PDFKit reads eight of them as
two lines — the number and the body — and the whole show's glyphs anchor to the number, whose
rectangle holds the show's origin:

```
L12 rect=(134.8,477.9,9.7,10.3)    text="^5` "     71 glyphs offered
L13 rect=(156.2,477.9,324.4,10.3)  text="Gdohqlxv/ W1 dqg Uhlvv/ …"   0 glyphs offered
```

The number cannot spell 71 glyphs and the body is offered none, so both declined and the row
shipped PDFKit's index-shifted reading. Page 11's table rows have the same shape (a 53-glyph row
offered to the 9-character cell line `uqnvzs38 `), as do pages 12, 13 and 15's.

## The rule

A line whose own glyphs spell it is rebuilt exactly as before — the alignment is run first with no
surplus allowed, so nothing that already repaired can change. Only a line they cannot spell may
stop at its last character and hold the rest for the next line of the row, and only where the next
held glyph **opens a word**. The gap between two printed columns is always a word gap, so that is
where the cut falls; a glyph continuing the word the line ends with is refused, and the line stays
as PDFKit read it. The next line must begin at or after the row's right edge (every rectangle the
row has covered, unioned) with its own middle inside the row's band of baselines. Page 17's
`[ 6]` line ends at x=147.5 and its body begins at x=156.2 on the same baseline; the line *below*
begins at x=156.2 too but its middle is 11 points down, and it is refused.

**Getting it wrong costs the repair, not the words.** The next line still has to spell the carried
glyphs *and* its own exactly, so a carry that does not belong fails there, both lines keep PDFKit's
reading, and `GlyphIndexDecoder.unreadGlyphs` counts the glyphs against the page — the same state
the row was in before. Across pages 11, 12, 13, 15 and 17 no carried glyph was dropped: every one
landed on the line that continued its row.

## Result at library defaults

| | Before (`da544ad`) | After |
| --- | --- | --- |
| Recognized pages | 12 (4–9, 11, 16–20) | 10 (4–9, 16, 18–20) |
| Pages reflowing their own text | 8 (2, 3, 10, 12–15) | 10 (2, 3, 10–15, 17) |
| Images | 37 | 35 |

Pages 12, 13 and 15 already reflowed but shipped their table rows index-shifted
(`uqnvzs38` / `79144 7:139 79199 …`); they now read `rnkswp05` / `46.11 47.06 46.66 …`, every
figure matching the render. No page's text lost a word: pages 1–10, 14, 16 and 18–20 are
character-for-character unchanged.

## Page 17 against the render

The whole page is native text now. Read against the raster, reference by reference:

- The first paragraph ends `… speciﬁc characteristics of data.` — recognition dropped the closing
  `data.` entirely.
- `[ 1] Dempster, A. P., Laird, N. M. and Rubin, D. B.: Maximum Likelihood from Incomplete Data
  via the EM Algorithm, Journal of the Royal Statistical Society, B, 39 (1977) 1–38.`
- `[2] Dalenius, T. and Reiss, S. P. Data-swapping: A Technique for Disclosure Control of
  Microdata, Journal of Statistical Planning and Inference, 6 (1982) 73–85.`
- `[ 6] Fellegi, I. P., and Sunter, A. B.: A Theory for Record Linkage, Journal of the American
  Statistical Association, 64, (1969) 1183–1210.` — the line #237 quotes, which shipped as
  `^ 9` / Ihoohjl/ L1 S1/ dqg Vxqwhu/ …`.
- `[ 7] Fuller, W. A.: Masking Procedures for Microdata Disclosure Limitation, Journal of Oﬃcial
  Statistics, 9, (1993) 383–406.` — recognition read `Jourxal of Oficual Stalistics`.
- `[ 13] Moore, R.: Controlled Data Swapping Techniques for Masking Public Use Microdata, U.S.
  Bureau of the Census, Statistical Research Division Report 96/04 (1996).` — recognition read
  `U.S. Bureau of Whe Census`.
- `[ 14] Roque, G. M. , Masking Microdata Files with Mixtures of Multivariate Normal
  Distributions, Unpublished Ph.D. dissertation, Department of Statistics, University of
  California–Riverside (2000).` — recognition read `Masking Microdato Fües with Mirtures`.

Every en dash the references print (`1–38`, `73–85`, `95–103`, `421–435`, `1183–1210`, `383–406`,
`303–308`, `456–461`, `114–119`, `313–331`, `California–Riverside`) is a Cork slot the decoder
reads; recognition rendered several of them as hyphens or as `1-38`. The ﬃ of `Oﬃcial` and the
`’` of `’2001` come from the font's own `Differences` names. The page carries **no** U+FFFD:
all 2368 of its glyphs are stated.

Each reference's number still stands in a paragraph of its own where PDFKit reported it as a
separate line; joining them is `BlockAssembler`'s business, not this reader's, and no word is
lost by it.

## Page 11 against the render

Table 1 now reads `rnkswp05 0.129 0.091 0.000 0.130 0.000 0.016 0.036 0.055 0.027` and its twelve
sibling rows exactly as printed, against recognition's `rukswp05` and `TI.1 IL1a I.2 IL3 II4 IL.5
80 81` for the column heads (`IL1 IL1s IL2 IL3 IL4 IL5 s0 s1 s2`). The two lines #149 names come
back: `does a little better than the ` and `However, when the perturbations get`, and the
paragraph ends `… to large values.`, which recognition dropped.

Page 11 carries 14 U+FFFD, and every one of them is a `cmmi` or `cmr` glyph nothing in the
document states — the italic `d` and `l` of `the d method` / `the l method` (five occurrences),
the `1%` of `a 1% noise level`, and the `IL1` and `IL1s` of the closing paragraph. Recognition had
read those seven runs, so they are the one thing page 11 gives up by leaving recognition; that is
#226's rule (`a plausible-looking wrong letter is worse than an admitted gap`), not a new one, and
14 replacements against 2738 characters sit well inside the `max(2, characters/50)` the diagnosis
allows. Pages 2, 10, 13 and 14 already ship 1, 25, 8 and 4 of them.

## Page 16 after this change: unchanged, and why

Page 16 still decodes completely and is still recognized. PDFKit reports its two affected rows as
**four overlapping lines sharing one rectangle** `(134.8, 399.3, 345.9, 23.6)`, two of which read
only `"w"` and one of which holds a newline. The shows' origins lie in all four, so
`indexGlyphs` attributes none of them to any line — this fix changes which line a glyph reaches
*after* attribution, and page 16 has no attribution to work from. Nothing is carried into those
lines either: the line above them (`For the research community, …`) consumes all 65 of its own
glyphs, so there is no surplus to offer. `unreadGlyphs` counts the two rows, page 16 keeps
`damagedTextEncoding`, and its extracted text is byte-identical to before. It remains #149 item 3.

## Controls

All eighteen corpus cases pass `tools/run_corpus_regressions.py` with EPUBCheck, including the
books deliberately left on recognition (`gpo-warren-1964-suspect-text-excerpt`,
`cdc-zombie-pandemic-2011`), the book whose glyph evidence the neighbouring reader supplies
(`usda-ars-agresearch-2012-11`, #217), and the twelve English and non-English books with no
index-glyph font at all (9/11, FAA, Fed, Wallace, Supreme Court, Our Flag, DGA, NBS, arXiv, USGS,
Blue Book, the Arabic and Chinese cases and the slide deck). `scripts/check-all.sh --fast` passes,
322 Swift tests and 169 Python tests pass, and `DamagedEncodingTests`'s own `'`-drawn Type 3
fixture — which this decoder deliberately does not read — keeps every one of #38's assertions.

### Controls, re-measured for #237

Every source in `corpus/cache` was converted with the `da544ad` CLI and the changed one, both with
`--package-identifier urn:uuid:fixed --modification-date 2026-01-01T00:00:00Z`, and the EPUBs
compared by SHA-256. **Only the Census report differs.** Byte-identical: the two deliberate
recognition controls (`warren-suspect-text-excerpt`, `cdc_6023_DS1`), the #217 magazine
(`November-December2012`), and 9/11, FAA, Fed, Wallace, Supreme Court, Our Flag, DGA, NBS, arXiv,
USGS, Blue Book, the Arabic and Chinese cases, the slide deck, the civil-case form and the three
NTRS documents. (`GPO-WARRENCOMMISSIONREPORT` and `noaa_61592_DS1` stop at the default
image-output ceiling at the same page either way, as they do on `main`; their gated excerpts are
in the list above.) `DamagedEncodingTests`'s `'`-drawn Type 3 fixture is untouched, because
`GlyphIndexDecoder` still refuses a page that uses `'`.
