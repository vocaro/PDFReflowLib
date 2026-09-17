# Book language and Vision recognition languages (#106)

Tier: Apple PDF stack plus Vision, library defaults, macOS 27.0 (26A428) arm64, release CLI.
Trees: `bc5eb8c` (baseline release SHA-256 `de3af24a142bb894…`) and `36c6265` plus this change
(candidate `742251c14d636928…`). Six agents shared the Mac (one-minute load 12–18). No PDF or
EPUB is committed.

## Summary

The issue's diagnosis is inexact. Vision does **not** ignore a bare language code: set on the
request, `ja`, `zh`, `th`, `ar`, `hi`, `ko` and `ru` behave exactly like `ja-JP`, `zh-Hant`,
`ar-SA`, `ru-RU` and so on (probe 2). The bare code never reached Vision because `OCRReader`
applied a language only when `supportedRecognitionLanguages.contains(Locale.Language(identifier:))`,
and that list holds only qualified languages, so `en`, `fr` and every other bare code were dropped
and the request kept its default, `en-US`.

The fix maps the book language to a listed language (likely subtags, then language and script,
then language code) and reports a language Vision does not list once per conversion, in the first
`ocrUsed` message. English output is unchanged (`en` maps to `en-US`, the default, so the request
value is equal): Census, CDC, Blue Book and `scanned.pdf` are identical on shared compiled models.

The issue's expected benefit does not reproduce on this SDK. With the library's request
(automatic language detection on, language correction off) synthetic French reads the same under
`en-US` and `fr-FR`, clean or degraded, and so do the other scripts tried. The selected language
is now correct, but it does not by itself improve accented French text.

## Probes

`probe-recognition-languages.swift` (`swiftc -O probe-recognition-languages.swift -o
probe-ocrlang106`; usage `probe-ocrlang106 <fr|de|ru|ja|vi|uk|zht|th|ar|hi|ko|homo|frshort|en>
<font-size> <scale> <correction 0|1> <language|default>...`; without arguments it prints probe 1).
It has its own model cache, and all settings compared ran in one process, so they shared compiled
programs. It renders
lines with Core Text (Times New Roman), optionally draws them at a reduced scale and upsamples
(a soft scan), and runs `RecognizeDocumentsRequest(.revision1)` with `recognitionLanguages` set
directly (no `contains` gate), detection on and off.

1. **Supported list.** 33 languages, all region- or script-qualified: `en-US`, `fr-FR`, `it-IT`,
   `de-DE`, `es-ES`, `pt-BR`, `zh-Hans`, `zh-Hant`, `yue-Hans`, `yue-Hant`, `ko-KR`, `ja-JP`,
   `ru-RU`, `uk-UA`, `th-TH`, `vi-VT`, `ar-SA`, `ars-SA`, `tr-TR`, `id-ID`, `cs-CZ`, `da-DK`,
   `nl-NL`, `no-NO`, `nn-NO`, `nb-NO`, `ms-MY`, `pl-PL`, `ro-RO`, `sv-SE`, `fi-FI`, `hi-IN`,
   `mr-IN`. Default `recognitionLanguages` is `[en-US]`. `contains` is false for `en`, `fr`, `de`,
   `pt`, `zh`, `zh-TW`, `en-GB`, `fr-CA`, `tlh`, true for `en-US`, `fr-FR`, `zh-Hans`. A bare
   code set on the request is kept verbatim (`Language(en, nil, nil)`), not normalized.
2. **Does Vision honour bare codes?** Detection **off**: Japanese reads `ПОXКТД.` under the
   default, `fr` and `fr-FR`, and correctly under both `ja` and `ja-JP`. Traditional Chinese reads
   `È* 4*É. / ЖАУхШÈХ` under the default and correctly under `zh`, `zh-Hant` and `zh-TW`. Thai,
   Arabic, Hindi and Korean read empty under the default and correctly under the bare code (and
   `ar-SA`). Yes: bare codes are honoured.
3. **French, detection on (library setting).** 34 pt, six lines with accents. Scale 1, 0.35 and
   0.25: default, `en`, `en-US`, `fr`, `fr-FR` give identical text (at 0.25: `ou lété`,
   `répétent`, `dù` in every setting). Scale 0.2: identical under default and `fr-FR` (`géaéral`,
   `Beianpon`, `bibliethéque`). With language correction **on**, 0.2 improves greatly
   (`Besançon`, `numéros`, `première`) but again identically for default and `fr-FR`. Short
   isolated words (`été`, `sœur`): identical. Detection off: identical too.
4. **Other scripts, detection on.** Vietnamese, Ukrainian, Russian, Japanese, Traditional Chinese
   (also at scale 0.3), Thai, Arabic, Hindi, Korean read the same under the default as under their
   own language.
5. **Where the language does matter with detection on.** Capital Cyrillic words made only of
   Latin look-alike letters (`КОМАР ТАРА МОРЕ СОРТ ХОР / ВОРОН ТОРТ МАМА КАРТА САХАР`) read as
   Cyrillic under the default and as **Latin** (`KOMAP TAPA …`) under both `ru` and `ru-RU`,
   detection on or off. Ordinary Russian sentences read correctly under `ru`. This is the only
   input found where the choice changed output, and it went the wrong way (defect noted below).

## Change

- `OCRReader.recognitionLanguage(for:supported:)`: the listed language whose `maximalIdentifier`
  equals the tag's (`en` → `en-US`, `pt` → `pt-BR`, `zh` → `zh-Hans`, `zh-TW` → `zh-Hant`), else
  the first with the same language code and script (`fr-CA` → `fr-FR`, `en-GB` → `en-US`,
  `pt-PT` → `pt-BR`, `vi` → `vi-VT`, `ar` → `ar-SA`), else the first with the same language code,
  else nil. The issue asked for exact then first variant; the script step keeps `zh-TW` from
  landing on Simplified Chinese.
- `recognitionRequest(language:)` applies the match; with nil it keeps the SDK default.
- Fallback report: no public API or warning-code change. `ConversionReport` has no OCR summary, so
  the conversion's first `ocrUsed` warning appends `Vision does not recognize the book language
  tlh; OCR used its default language (en-US) with automatic language detection.` It appears only
  when a page was recognized, which is the only time the language matters. `ocrFailed` pages get
  no note.
- Docs: README OCR bullet, `doc/conversion-options.md` (OCR section; the #94 sentence claiming only
  region-qualified tags apply was removed), `ConversionOptions.language` doc comment.

## Tests

- `OCRRequestTests.ocrRequestMapsBookLanguagesToSupportedRecognitionLanguages`: 16 tags mapped
  as above with no note; `tlh`, `el`, `he`, `x-private` map to nil, keep the default request
  languages and produce the exact note. `ocrRequestPinsRevisionAndTextRecognitionOptions` still
  expects `[en-US]` for `en`, and `ocrRequestPinnedValuesAreTheSDKDefaults` still finds the `en`
  request equal to an unconfigured one.
- `OCRLanguageTests.frenchScanIsRecognizedWithTheFrenchLanguageAndReadsItsAccents`: renders six
  accented French lines at 150 dpi (half resolution, upsampled) into a two-page image-only PDF
  and converts it with `fr`, `en` and `tlh`. The `fr` request carries `fr-FR`. It counts 15
  distinctive accented words found on both pages: measured **15/15 under all three languages**,
  so the test asserts `fr` ≥ ⅔ of the words and `fr` ≥ `en` rather than strictly better
  (probe 3). `tlh` yields exactly one note, on page 1's `ocrUsed`; `fr` and `en` none.

## English controls (shared compiled models)

Both binaries were copied to the same unique name `pdf-rfl106` in separate directories, so
they shared `~/Library/Caches/pdf-rfl106`. The first run (baseline Census, without the probe,
discarded) compiled 5 programs, fingerprint `22614cb0d67a8299…`. Every later run, baseline or
candidate, reused them (`mode: inherited`, before = after). Here, alternating binaries of one name
did not trigger the recompile #94 saw. `run_corpus_regressions.py` with EPUBCheck, the capability
probe and `--execution-context host-terminal`, one case per call, then
`compare_conversion_runs.py --allow-different-converters`, then an entry-by-entry EPUB diff.

| Case | OCR pages | Baseline / candidate | Comparator | `sameVisionPrograms` | EPUB entries |
| --- | ---: | --- | --- | --- | --- |
| census-rrs2002-01 | 19 | pass 5 s / pass 6 s | pass, no changed pages, OCR pages, images, navigation or report fields | true (`22614cb0…`) | 59, all identical except `package.opf` UUID and time |
| cdc-zombie-pandemic-2011 | 9 | pass 8 s / pass 7 s | pass, nothing changed | true (`22614cb0…`) | 48, same |
| cia-blue-book-14-1955 | 0 | pass 34 s / pass 33 s | pass, nothing changed | true (`22614cb0…`) | 448, same |

`scanned.pdf` through both binaries with `--package-identifier urn:test:106
--modification-date 2026-01-01T00:00:00Z`: identical EPUB SHA-256 `7a09bb522eb7366d…`. The
reports differ only in `outputURL`; the cache fingerprint stayed `22614cb0…`.

The CLI has no language option, so every corpus conversion (including `uscis-m618-arabic-2015`
and `irs-p596-zhs-2025`) uses `en`; no corpus book exercises a non-English OCR language.

## Limitations

- Synthetic rasters only; no real French or other non-English scan was measured.
- One SDK (macOS 27.0, 26A428); iOS not measured.
- Mapping edge cases (standalone check of the same rule): `no`, `nb`, `nn`, `ars`, `yue` match
  themselves; `ar` → `ar-SA`, `zh-HK` → `zh-Hant`, `vi` → `vi-VT`; `EN` and `en-us` → `en-US`;
  `sr`, `tlh` and `x-private` (no language code) have no match and fall back.
