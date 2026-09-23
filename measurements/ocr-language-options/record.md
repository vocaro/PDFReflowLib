# OCR language options: a correction opt-in and the Cyrillic look-alike mirror (#108)

Tier: Apple PDF stack plus Vision, macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple M5 Max,
three other agents sharing the Mac (one-minute load 8–13).
Build: `main` at `8faeaab` with this change, release CLI. Baseline: `8faeaab` alone, built before
any file was touched. Synthetic type only for item 2; no corpus book is Russian. No PDF, EPUB or
render is committed.

## Item 1: `ocrLanguageCorrection`, off by default

The owner ruled on 2026-09-23 that Vision's language correction stays off and gains an opt-in.
`ConversionOptions.ocrLanguageCorrection` (default `false`) is the only thing that sets
`useLanguageCorrection` on the request `OCRReader.recognitionRequest(options:)` builds; the CLI
takes `--ocr-language-correction on|off` and rejects any other value naming `on` and `off`. The
report has no field for options, so every `ocrUsed` warning of a conversion that used it says so.

The cost the documentation states is the owner's own measurement on #108 (branch record
`15ce93f`, not on `main`): across three compiled model sets on Census, CDC, all 312 Blue Book
pages and the Warren excerpt, correction reads prose slightly better and damages codes and
variable names (Census 72.5% → 65.0%, Blue Book 48.4% → 35.5%), dates and numbers (`11/21/54` →
`11121/54`, `1950` → `11950`) and names (`Euins` → `Buins`); a corrected mistake reads as a real
word. Nothing here re-measures that. What this record measured:

- `scanned.pdf` through the release CLI with `on` and with `off`: both recognize 1 page and write 1
  image; the `on` report's `ocrUsed` reads "Text is OCR transcription read with language
  correction on: a misread code, number or name may have been changed to a plausible word. The
  original page image preserves unrecognized visual content."; the `off` report's is the
  unchanged "Text is OCR transcription. The original page image preserves unrecognized visual
  content."
- `OCRRequestTests`: the request carries correction only when the option says so, and with the
  flag set back the two requests' `TextRecognitionOptions` are equal, so nothing else moves.
- `tools/check_conversion_policies.py`: 18 policy conversions and 28 rejection cases pass,
  including `ocr-language-correction` (every `ocrUsed` message says correction was on),
  `ocr-language-correction-off` and the four rejected values `yes`, `ON`, empty and missing.

## Item 2: `ru` reads all-capital look-alike words as Latin

### Probe

`probe.swift` in this directory (`xcrun swiftc -O probe.swift -o vision-language-probe`) draws a
few lines of Times New Roman into a 1,400-pixel-wide bitmap with Core Text, hashes the pixels, and
reads the same bitmap with `RecognizeDocumentsRequest` (language correction off, as the library
sets it) under the request's default languages and under `ru`, `ru-RU`, `uk-UA` and `en-US`.
The reading below is at 40 pt (pixel digests `6507aa85fda4` for the first page, `513bb072e4d2`
for the control); a second run at 20 pt, the size of scanned body type, is noted where it differs.

On this SDK `supportedRecognitionLanguages` holds 33 region- or script-qualified languages
(`ru-RU`, `uk-UA`, `en-US`, …); `contains` is false for `ru`, `uk` and `en`, and the default
`recognitionLanguages` is `[en-US]`. `OCRReader` applies the declared language only when
`contains` is true, so on `main` `--language ru` reads at the default and `--language ru-RU`
reaches Vision. Set directly on the request, `ru` and `ru-RU` read identically in every case
below.

| Drawn | Default and `en-US` | `ru`, `ru-RU` and `uk-UA` |
| --- | --- | --- |
| `КОМАР ТАРА` | `КОМАР ТАРА` | `KOMAP TAPA` |
| `МОРЕ СОРТ ХОР` | `МОPЕ COPT ХОР` (at 20 pt `МОPE СOPT ХOP`) | `MOPE COPT XOP` |
| `ВОРОН ТОРТ МАМА` | `ВОРОН ТОРТ МАМА` | `BOPOH TOPT MAMA` |
| `ЖУРНАЛ ДОМ`, `ГОРОД ЛЕС`, `ЗИМА ШУМ` | as drawn | as drawn |
| `комар тара`, `море сорт хор`, `ворон торт мама` | as drawn | as drawn |
| `Мама мыла раму.`, `Комар сел на торт.`, `Сахар и кофе на столе.` | as drawn (`кофе` → `коче` at 40 pt) | the same |
| `TAX COMPACT` | `TAX COMPACT` | `TAX COMPACT` |
| `NASA MOCK` | `NASA MOCK` | `NASA MOCK` |
| `Отчёт NASA за год.` | as drawn | as drawn |
| `КОМАР TAX` | `КОМАР ТАХ` | `KOMAP TAX` |
| `PACT ТОРТ` | `PAСТ ТОРТ` (at 20 pt `РАСТ ТОРТ`) | `PACT TOPT` |
| `КОМАР NASA` | `KOMАP NASA` (at 20 pt `KOMAP NASA`) | the same |
| `ТОРТ ЖУК` | as drawn | as drawn |
| `МОСКВА USA` | `MOCKBA USA` | `MOCKBA USA` |
| `МОСКВА` | `MOСKВА` (at 20 pt `MOСKBA`) | the same |
| `ТАСС СССР НАТО` | as drawn (at 20 pt `ТАСС СССР HАТО`) | the same |
| `ОТЧЕТ` | as drawn | as drawn |
| `комар tax` | `комар tax` | `комар tax` |
| `море compact хор` | `моpe compact хop` (at 20 pt `моpe compact xop`) | the same |
| `XX ВЕК` | `XX BEK` | `XX BEK` |
| `ГЛАВА XX` | `ГЛАВА ХХ` | `ГЛАВА ХХ` |
| `XIX ВЕК` | `XIX BEK` | `XIX BEK` |
| `М. ГОРЬКИЙ`, `С. ЕСЕНИН` | as drawn | as drawn |

So the finding of #106's branch record reproduces on this build: under a Cyrillic recognition
language an all-capital line whose every letter is drawn the same as a Latin one comes back
Latin, at 40 pt and at 20 pt, while the default reads such a line as Cyrillic. Three things the
branch did not record also hold, under every language including the default:

- Vision decides the script of a line, not of a word. A Latin word with a letter that has no
  Cyrillic look-alike (`NASA`, `USA`) pulls the whole line to Latin (`KOMAP NASA`,
  `MOCKBA USA`), and a Cyrillic word with a letter that has no Latin look-alike (`ЖУК`) holds
  the line Cyrillic.
- Where nothing anchors the line, single letters of an all-look-alike word come back Latin
  inside otherwise Cyrillic tokens: `MOСKВА`, `МОPЕ COPT ХОР`, `моpe … хop`, `HАТО`.
- A Latin Roman numeral beside a Cyrillic word is returned as Latin when it leads (`XX BEK`) and
  as Cyrillic when it follows (`ГЛАВА ХХ`); initials with a stop are read correctly.

Lower-case words are read correctly under every language, and genuine Latin words in a Russian
line (`TAX COMPACT`, `NASA MOCK`, `Отчёт NASA за год.`, `комар tax`) come back Latin under `ru`
exactly as the misread Cyrillic does. A Russian lexicon that could tell `KOMAP` from `TAX` is not
available: `NLEmbedding.wordEmbedding(for: .russian)` is nil on this host, where the English one
the library uses is not.

### The rule

`OCRReader.repairedScript` now dispatches on the declared language: English keeps the #168 rule
(Cyrillic look-alikes to Latin), and a language whose script is Cyrillic gets its mirror,
`cyrillicRepaired`. The script comes from the tag, `Locale.Language(identifier:).script ==
.cyrillic`, which is the script the tag names or the one it implies: `ru`, `ru-RU`, `ru_RU`, `uk`,
`bg`, `sr`, `sr-Cyrl`, `mk`, `be`, `kk`, `ky`, `tg`, `mn` and `uz-Cyrl` are inside; `sr-Latn`,
`uz`, `el`, every Latin-script tag, `tlh` and an empty tag are outside. It works from the
declared tag rather than from the request's language, so it applies under `--language ru` as well
as `ru-RU`, where the reading is the default's and holds the mixed tokens above.

For each whitespace-separated token holding a Latin letter, with a table of the twelve capitals
`A B E K M H O P C T Y X` and seven lower-case letters `a e o p c y x` that are drawn the same
as a Cyrillic letter — the #168 table read the other way, without `І`, `Ј` and `Ѕ`, which belong
to Ukrainian, Serbian and Macedonian and not to Russian:

- a token with any Latin letter outside the table is kept whole (`NASA`, `USA`, `ISO`, `XIX`);
- a token that also holds a Cyrillic letter is rewritten to Cyrillic whatever its case, because
  no word mixes the scripts (`MOСKВА` → `МОСКВА`, `HАТО` → `НАТО`, `моpe` → `море`);
- a token that is Latin throughout is rewritten only when every letter is a capital and the
  letters do not spell a Roman numeral of `X`, `C` and `M` alone (`KOMAP` → `КОМАР`, `BEK` →
  `ВЕК`; `XX`, `M.` and `tax` are kept).

Applied to the `ru-RU` readings above: `KOMAP TAPA`, `MOPE COPT XOP`, `BOPOH TOPT MAMA`,
`KOMАP NASA`, `MOCKBA USA`, `MOСKВА`, `HАТО`, `XX BEK` and `XIX BEK` come out as the page drew
them; `моpe … хop` at 40 pt does too, while at 20 pt `xop`, read wholly as lower-case Latin, is
kept as read. `TAX COMPACT` becomes `ТАХ СОМРАСТ`, `MOCK` becomes `МОСК`, and the Latin halves of
`KOMAP TAX` and `PACT TOPT` are rewritten with the Cyrillic halves: four genuine Latin tokens on
three lines, every one a capital word from the twelve letters alone. That is the risk the rule
accepts, and it is pinned by `anAllCapitalLatinWordOfLookAlikesIsRewrittenWithTheMisreading` so
that narrowing it is a decision. The narrowing considered — rewrite only when the line also holds
Cyrillic — would leave the observed failure unrepaired, because `ru-RU` returns the whole line
Latin; the other — a lexicon vote — has no Russian lexicon to vote with. Either way the token
renders the same: the cost falls on search, copying and any later rule that reads the text, not
on the page.

Tests: `ScriptRepairTests` (`cyrillicCapitalsReadAsLatinAreReturnedToTheirScript`,
`latinThePageDrawsInACyrillicDocumentIsKept`, the accepted risk above, and
`theCyrillicRuleReachesOnlyCyrillicScriptLanguages`). `anotherLanguageKeepsItsOwnScript` keeps
its assertion that `СОТ РОТ` under `ru` is returned unchanged: the mirror touches only Latin
letters, so that reading holds by design, and only its comment moved.

## Byte identity at defaults (decision 0004)

Every cached source but the full Warren report and NOAA, converted by the baseline and by this
build one at a time at library defaults with `--package-identifier urn:uuid:identity
--modification-date 2026-01-01T00:00:00Z`, compared with `tools/epub_identity.py` (EPUB and
report), the pair deleted after each comparison.

With the two binaries under their own names (`pdf-reflow-baseline` and `pdf-reflow`), 18 of the
22 are byte-identical, EPUB and report: the Loper Bright opinion, the Fed, Our Flag, the USDA
magazine, the NASA close-out report and the two NASA papers, the earth-data slides, the Arabic
guide, the Chinese IRS publication, Geltman, the USGS copper sheet, the arXiv paper, the civil
complaint, DGA, the 9/11 report, the Wallace algebra book and the FAA handbook.

The four books with recognized pages differed — Census 38 entries, CDC 2, the Warren excerpt 8,
Blue Book 21 — and every difference is a recognition: all four are identical at `--no-ocr`. The
baseline binary, run for the first time under a name of its own, compiled a Vision model set of
its own (56 s for Census against 7 s), and a compiled set reads a page its own way (#173, #269,
#281): Census through the baseline's set reported no `incompleteRecognition` and 36 images, and
through the candidate's set nine such pages and 32 images; the Warren excerpt's page 4 was
`ocrUsed` through one and not recognized through the other; Blue Book recognized the same 56
pages through both and read them differently. Copied to one name in two directories
(`scratch/a/pdf-reflow-108` and `scratch/b/pdf-reflow-108`, sharing `~/Library/Caches/pdf-reflow-108`),
so both read with one compiled set, all four are byte-identical, EPUB and report. So every one of
the 22 completing sources is identical once the two binaries read with the same models, which is
what the change claims: the request is built exactly as before when the option is off, and no
corpus book declares a Cyrillic-script language.
