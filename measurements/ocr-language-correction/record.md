# Language correction on the English OCR books (#108, item 1)

Tier: Apple PDF stack plus Vision, macOS 27.0 (26A428) arm64, tree `63680df`, standalone probe
built from the library's own sources. Six agents shared the Mac (one-minute load 7–45). No PDF,
EPUB, render or transcription is committed. **No library code was changed.**

## Summary

Recommendation: **leave `useLanguageCorrection` off**, and do not switch it on by book type. It
could be added later as an opt-in option for plain prose scans, but this evidence does not justify
building it now.

On the English OCR pages, correction trades code and number fidelity for somewhat better prose.
All three independently compiled model sets agree on this, and the changes themselves are almost
the same in each set (below).

- **Prose gets better.** Against the hand-transcribed passages, word recall rises from 93.7% to
  95.1% (Census), 75.3% to 80.6% (Blue Book, mostly typed titles) and 96.7% to 97.5% (Warren).
  Fixes include `Buresu`→`Bureau`, `algoritbm tor`→`algorithm for`, `Kuby`→`Ruby`,
  `Garfleld`→`Garfield` and `Sichtings`→`Sightings`.
- **Codes get worse.** Code recall (tokens with letters and digits) falls from 72.5% to 65.0%
  (Census variable names) and from 48.4% to 35.5% (Blue Book table codes): `IL1`→`ILL`,
  `add10`→`add 10`, `rnkswpl5`→`rakswpls`, `IL3,I14,`→`113, 114,`, `A141,`→`A 141,`.
- **Numbers mostly stay the same, but specific values get damaged.** Total number recall per
  book is unchanged (Census +1 token, Blue Book and Warren equal). Correction still loses the
  handwritten date `11/21/54`→`11121/54` (Blue Book page 1) and a chart year `1950`→`11950`
  (page 27). Across Blue Book it also splits or merges values: `15.4`→`15. 4`, `100`→`1 00`,
  `0.3 27`→`0.32.7`, `2,232`→`2, 232`.
- **Proper names go both ways, and the wrong ones look plausible.** Correction fixes `Dowhey`,
  `Ddwin`, `Garfleld`, `Snsder`, `Delgndo` and `farvey`, but turns the witness `Euins` into
  `Buins` and `ruller` (Fuller) into `ruler`. A corrected mistake is a real-looking word, which is
  harder for a reader to spot than obvious OCR noise, and the converter has no per-word
  confidence to flag it.
- **The mechanical classifier sees many more code and number edits than word gains.** Over all
  changes in the four books, per set: about 1,070 dictionary gains, 240 dictionary losses, 1,470
  digit-count changes, 1,040 punctuation-only and 1,030 spacing-only edits, and about 810
  deletions involving digits.
- **In the hand review, fixes and damage are about equal.** Census: 41 better, 41 worse. Warren:
  21 better, 9 worse. Blue Book sample of 100: 8 better, 13 worse, 56 neutral, 20 not judgeable
  without the source cell.
- **Correction is not needed for form fields and handwriting.** It does not make the
  handwritten Blue Book tables readable (number recall 45 to 47 of 132, both near noise) and
  damages the one handwritten date.
- **Cost is small.** Median recognition time per page changed by −1% to +11% across sets and
  books (Blue Book +3–6%, 0.325 s to 0.340 s in set a).

The corpus's English OCR books are the pages where correction does harm: Census body pages
(variable names, table values, citations, math), Blue Book statistical and list pages, and
Warren notes and index. Correction's gains are concentrated in running prose, and Census mixes
prose with tables and codes on the same page, so choosing by book type or by page would need a
content classifier the library does not have.

## Method

### Probe

`probe-language-correction.swift` is compiled together with `OCRReader.swift`,
`PageRasterizer.swift`, `ConversionTypes.swift`, `DocumentModel.swift` and
`ReflowDocument.swift`, with the command in its header. It uses no hook or public option. For
each page it:

- rasterizes the crop box once, exactly as the converter does (`PageRasterizer`, default
  `ConversionOptions`, 180 DPI);
- builds the converter's request, `OCRReader.recognitionRequest(language: "en")`;
- recognizes the same image twice in the same process, once with
  `textRecognitionOptions.useLanguageCorrection` false and once true, and prints each
  `document.text.lines` top candidate as the converter reads it.

Because both settings run in one process, they always share one compiled model set (#94).

`run-model-set.sh` copies the probe to a never-used name, which forces a fresh compile into
`~/Library/Caches/<name>`. It records `conversion_provenance.vision_model_cache` before and
after, and runs:

| Book | Pages |
| --- | --- |
| Census `rrs2002-01` | 2–20 (all OCR pages under defaults) |
| CDC `cdc-zombie-pandemic-2011` | 2, 13, 15, 16, 17, 36, 38, 40, 41 (the nine `ocrUsed` pages of a default conversion at `63680df`) |
| Blue Book `cia-blue-book-14-1955` | all 312 pages (what `.always` recognizes; it has no OCR pages under defaults) |
| Warren | source pages 1, 7, 21, 30, 50, 100, 890, 910, 920 (the pages of the nine-page excerpt, rasterized from the full PDF, so no excerpt file was written) |

### Model sets

| Set | Order | Fingerprint after (`programsSHA256`) | Programs | Transcription |
| --- | --- | --- | ---: | --- |
| `lc108a` | off then on | `22614cb0d67a8299…` (the same bytes #106 recorded) | 5 | clean #94 draw (`re-identification`, `[ 18]`) |
| `lc108b` | on then off | `6c271c616e6eb57d…` | 5 | **lossy draw** (below) |
| `lc108c` | off then on | `2dda869df5640452…` | 5 | same text as `lc108a` on every Census, CDC and Warren page, and 98.6% of Blue Book changes identical |

Every set started from an empty cache (before-fingerprint `4f53cda1…`, zero programs).

### Metrics

- **Dictionary-word rate** (`analyze.py`): the share of lowercase alphabetic words of four or
  more letters, edge punctuation stripped, found in `/usr/share/dict/words`, plus the same rate
  over all such words case-folded. These are raw Vision lines, not converter EPUB text
  (hyphenation not joined), and the word list has no inflections. The absolute values are
  therefore lower than #94's 88.45%; only the off→on difference matters. The rate also rises
  when junk tokens are deleted, so it overstates Blue Book's gain.
- **Ground truth** (`ground-truth.json`, `score.py`): ten passages transcribed by hand from
  renders (zoomed crops where needed; Census page 12 values rechecked at 5×).
  - Census: pages 12 and 14 tables and prose, page 3 field list, page 6 prose.
  - Blue Book: page 1 form and release stamp, page 27 pie-chart labels, page 111 list of
    tables, page 132 handwritten table.
  - Warren: page 50 prose with names and dates, page 910 index.
  - Tokens are split into numbers, codes and words and matched as multisets against the page's
    OCR. Passages that don't cover a whole page can over-count repeated tokens (page 132's zeros).
- **Every changed token** (`analyze.py --changes`): a difflib token diff of each page, off
  against on.
  - `classify.py` sorts all changes mechanically.
  - All 219 Census, CDC and Warren changes in `lc108a`, and a seeded random sample of 100 Blue
    Book changes (`random.seed(108)`), were judged by hand against the renders:
    `changed-token-review.tsv`.
- **Volume** (`volume.py`): lines, tokens and digits under each setting.

## Per-book results

### Dictionary-word rate and changes

| Book | Set | Pages changed | Lines off→on | Tokens off→on | Dict. rate, lowercase ≥4 | Dict. rate, all ≥4 |
| --- | --- | --- | --- | --- | --- | --- |
| Census | a, c | 19/19 | 923→911 | 6794→6753 | 78.09→78.47% | 76.30→76.93% |
| Census | b | 18/19 | 567→555 | 2213→2179 | 74.38→75.84% | 72.64→74.45% |
| CDC | a, b, c | 2/9 | 20→19 | 56→55 | no qualifying words | 79.31→79.31% |
| Blue Book | a | 268/312 | 42579→42297 | 90803→89217 | 71.03→72.89% | 50.52→57.38% |
| Blue Book | c | 268/312 | 42579→42317 | 90803→89330 | 71.03→72.85% | 50.52→57.27% |
| Blue Book | b | 259/312 | 41716→41406 | 81342→79734 | 66.40→69.49% | 45.03→52.95% |
| Warren | a, c | 6/9 | 518→514 | 2312→2282 | 75.33→76.32% | 71.00→71.67% |
| Warren | b | 5/9 | 486→482 | 1971→1940 | 75.65→77.38% | 70.03→70.80% |

CDC is barely affected. Four of its nine OCR pages yield no lines at all (2, 38, 40, 41), and
the three changes are one balloon (`(WHINE!) UН? WHД?`→`(WHINE!> ИН? WHA?`), a masthead fragment
(`CERTERG`→`CENTERE`) and one dropped junk line.

### Ground truth: recall with correction off→on

Sets a and c are identical on every passage.

| Book | Class | GT tokens | Sets a, c | Set b |
| --- | --- | ---: | --- | --- |
| Census | numbers | 176 | 96.6→97.2% | 86.4→86.4% |
| Census | codes | 40 | **72.5→65.0%** | 70.0→65.0% |
| Census | words | 615 | 93.7→95.1% | 54.3→56.4% |
| Blue Book | numbers | 222 | 55.0→55.0% (lost `11`, `21`, `1950`, `8.6`, `68.6`, `55`; gained `100`, `2.9`, `6`×3, `9`) | 55.0→55.0% |
| Blue Book | codes | 31 | **48.4→35.5%** (lost `A141`, `A142`, `A150`, `A154`) | 32.3→32.3% |
| Blue Book | words | 396 | 75.3→80.6% | 61.4→63.4% |
| Warren | numbers | 148 | 82.4→82.4% | 81.8→81.8% |
| Warren | words | 361 | 96.7→97.5% (gained `Edwin`, `Downey`, `Garfield`, `various`; lost `Euins`) | 90.9→91.7% |

Per passage (sets a and c):

- `census-12-tables` codes 18→16 (`add10` ×2 split); header word `Sscore`→`Score` ×2.
- `census-14` codes 11→10 (`IL1`→`ILI`).
- `census-6-prose` words 243→254 (12 gained, `univariate` lost).
- `bluebook-1-form` numbers 8→6 (`11/21/54`→`11121/54`); words 28→31 (`Authorization`,
  `Act`, `Reviewed`).
- `bluebook-27-figure` numbers 55→55 (`1950`→`11950`; `100` gained).
- `bluebook-111` codes 14→10, words 248→261.
- `bluebook-132` handwritten: numbers 45→47 of 132, both unreadable.
- `warren-50` words 223→224.
- `warren-910` words 126→128.

### Mechanical classification of all changes (`classify.py`)

| Set, book | Spans | Dict. gain | Dict. loss | Other letters | Digits gained / lost / changed | Punct. | Spacing split / join | Delete num. / text | Insert num. / text |
| --- | ---: | ---: | ---: | ---: | --- | ---: | --- | --- | --- |
| a Census | 150 | 27 | 1 | 49 | 5 / 13 / 0 | 19 | 11 / 10 | 4 / 9 | 0 / 2 |
| b Census | 83 | 19 | 1 | 24 | 5 / 10 / 0 | 7 | 5 / 0 | 4 / 7 | 0 / 1 |
| a Blue Book | 8807 | 1027 | 238 | 1768 | 795 / 576 / 73 | 1013 | 858 / 140 | 800 / 384 | 974 / 161 |
| b Blue Book | 8685 | 978 | 239 | 1691 | 801 / 566 / 73 | 1008 | 820 / 136 | 836 / 400 | 983 / 154 |
| c Blue Book | 8830 | 1039 | 234 | 1785 | 787 / 569 / 72 | 1017 | 870 / 139 | 804 / 383 | 972 / 159 |
| a Warren | 66 | 11 | 1 | 25 | 3 / 5 / 2 | 7 | 1 / 7 | 2 / 1 | 0 / 1 |
| a, b, c CDC | 3 | 1 | 0 | 1 | 0 | 0 | 0 | 0 / 1 | 0 |

Set c's Census and Warren rows equal set a's. Set b's Warren row differs from a's only in
dictionary gain (10), punctuation (6) and total (64). Blue Book's digit-token count rises with
correction (44,107→45,556), because letter junk in handwritten cells becomes digits
(`UNKNONA`→`14000`).

## Changed-token review (`changed-token-review.tsv`)

| Scope | Spans | Better | Worse | Mixed | Neutral | Junk line dropped | Unclear |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Census, all (set a) | 150 | 41 | 41 | 4 | 56 | 8 | — |
| Warren, all (set a) | 66 | 21 | 9 | 1 | 32 | 3 | — |
| CDC, all | 3 | 1 | — | 1 | — | 1 | — |
| Blue Book, random 100 of 8,807 (set a) | 100 | 8 | 13 | 3 | 56 | — | 20 |

### Census

- **Better (41):** almost all running prose or bibliography: `Buresu`, `adlitive`, `Becaase`,
  `disasreements`, `tne matcnine weignts`, `assumpuions`, `identihable`, `Oficual Stalistics`,
  `Procecdings`, `Americon`, `Wiukler`, `Surney`, `(Х)` (Cyrillic) → `(X)`.
- **Worse (41):**
  - 15 variable names or codes: `IL1`→`ILL`/`ILI`, `IL1a`→`ILla` ×3, `IL1s`→`ILls`,
    `IL3,I14,`→`113, 114,`, `IL3`→`I L3`, `rukswp10`/`add10`/`mixadd10`→split,
    `rnkswpl5`→`rakswpls`, and a table header row reduced to `sl m kawp05`.
  - 11 citation brackets: `[ 5]),`→`[5),`, `([`→`(|`, `[`→`|`, `[8], [`→`8],`.
  - 9 math symbols: `≤`→`S`, `k`→`&`, `(i,j)`→`(i,)`, `u`→`¡`, `Z=Х+dY` deleted, `N`→`A`.
  - 2 table headers (`Sscore`→`Score`).
  - 1 value (`0.1009`→`0.1009.`).
  - 3 prose tokens (`clerical`→`clerica!`, `ruller`→`ruler`, a stray `|`).
- **Dropped (8):** garbled formula lines such as `Wnj = max({Waj - (Wgr - Wdie)|2 - b1], Wais).`
- **Neutral (56):** mostly bracket spacing (`[ 7]`→`[7]`, the source prints `[ 7]`) and math
  junk that stays junk.

### Warren

- **Better (21):** names (`Kuby`→`Ruby`, `farvey`→`Harvey`, `(Delgndo)`→`(Delgado)`,
  `F'olsom`, `deorge`→`George`, `Snsder`→`Snyder`, `Dowhey`, `Ddwin`, `Garfleld`), words
  (`varions`, `chutch`, `tocumenes`, `bave`), and note abbreviations (`CF:`/`CB`→`CE`,
  `Oet.`→`Oct.`).
- **Worse (9):** the witness `Euins`→`Buins`; note numbers `306`→`36`, `310 6,322`→`3106, 322`
  and `S H 300`→`$ H300`; the volume letter `H`→`1`; `cf.`→`c.` and `cf.`→`ef.`; item label
  `(h)`→`(½)`; and a `see …` reference cut to `se8`.
- All but 8 of the 66 changes are on page 890 (tiny, noisy notes) and page 910 (the index).

### Blue Book sample

- **Better (8):** `MORTH`→`NORTH`, `Pvaluation`→`Evaluation`, `Oblect Signtings`→
  `Object Sightings`, `ANE`→`AND`, `BURATION`→`DURATION`, `SIATED`→`STATED`,
  `AL YEATE`→`ALL YEARS`, `ㅭ`→`No`.
- **Worse (13):**
  - numbers split or merged: `15.4`→`15. 4`, `2.15 82 18.0`→`2. 15 8.218.0`, `100`→`1 00`,
    `0.3 27`→`0.32.7`, `0.12`→Arabic letters;
  - recognizable row labels or headings dropped: `3-Balxen 3-Ught Phoce 5 Clauda, Dest, efc.`,
    `SI6ATINES BY SIGNTING RELIRGILITY`→`SIGATINES`, `IM CAR SOUTOCORS`→`SOUTOCORS.`;
  - `Balicon`→`Bal icon nC ne`.
- **Neutral (56):** handwritten-table junk becoming other junk.
- **Unclear (20):** digit edits in handwritten cells that can't be judged without reading the
  cell (`/0.3`→`10.3`, `54184`→`5418.4`, `25560`→`251560`).

## Robustness across compiles

The changes correction makes are nearly the same in every compile. Sets a and c share all 150
Census, 66 Warren and 3 CDC changes, and 8,683 of 8,807 Blue Book changes. Set b's own changes
are 82 of 83 in set a (Census) and 7,745 of 8,685 (Blue Book). Every conclusion above holds in
all three sets, which is more than the two-compile rule from #94 requires.

## Other finding: a compile that drops text (for #94)

`lc108b` (`6c271c61…`) returned far fewer lines on Census under **both** settings: 567 against
923. Whole sentences are missing. Page 3 keeps the headings and field list but loses the body
sentences between `Two data files were used.` and `values or zeros were used.`, and page 2 yields
5 lines against 33. Warren (486 against 518) and Blue Book (41,716 against 42,579) lose lines
too.

Rerunning that name with its cached programs reproduced the same Census output. So besides the
wording differences recorded in #94, a compile draw can also silently drop body text, which the
converter would ship with only `ocrUsed`. One of three fresh compiles here, and it was the only
lossy one, so its frequency is unknown. Worth adding to the #94 Feedback report and to any
sampler, for example by checking line counts against the clean draw.

## Limitations

- Raw Vision lines from a probe, not converter EPUB text. The raster and request are the
  converter's, and `lc108a`'s fingerprint equals the one #106 recorded for the converter. EPUB
  structure effects (joined hyphenation, `wraps`, table regions from `document.tables`) were
  not measured.
- English only, one SDK (macOS 27.0 26A428), no iOS. Ground truth is ten passages transcribed
  by one reviewer. Handwritten Blue Book cells are hard to read even from 3.5× renders, which is
  why 20 sampled changes are left unclear.
- Blue Book was recognized on all pages (the `.always` equivalent). Under defaults the converter
  recognizes none of them, so Blue Book results only apply if a client opts into `.always`.

## Files

- `probe-language-correction.swift`: the probe.
- `run-model-set.sh`: one fresh model set over the four books.
- `analyze.py`: dictionary rates and the off→on token diff (`--changes`).
- `classify.py`: mechanical classes.
- `score.py`, `ground-truth.json`: recall against the ground-truth passages.
- `volume.py`: line, token and digit volume.
- `changed-token-review.tsv`: hand review.

Transcriptions, renders and the three model caches were deleted after recording.
