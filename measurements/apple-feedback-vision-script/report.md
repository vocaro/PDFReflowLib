# Vision returns Cyrillic characters when recognition is restricted to English

Suggested area: macOS / Vision. Type: Incorrect/Unexpected Behavior.
Drafted 2026-09-20; not yet filed.

## Summary

`RecognizeDocumentsRequest` with `textRecognitionOptions.recognitionLanguages = [en-US]` returns
transcriptions containing Cyrillic characters, which cannot occur in English. On a hand-lettered
comic page it reads `HUH?!` as `НИН?!` (U+041D U+0418 U+041D), `OKAY, MAYBE NOT` as
`ОКДУ, МАУВЕ NOT` and `YAYY!!` as `УДУУ!!`.

Setting the recognition language does not restrict the character set of the result, so a caller
that has declared its document's language still has to filter the output by script.

## Environment

macOS 27.0 (26A428), arm64, Xcode 27.0.

## Steps to reproduce

1. Download the CDC's *Preparedness 101: Zombie Pandemic* graphic novel (public domain), SHA-256
   `d95e9ec2d8cf52cb8c218a6195e132ec140725018358fd2122928bab8a13efc3`, from
   <https://stacks.cdc.gov/view/cdc/6023>.
2. Build the attached probe: `xcrun swiftc -O probe.swift -o vision-probe`
3. `MODE=en ./vision-probe cdc_6023_DS1.pdf 5`

The probe rasterizes the page with PDFKit at 180 dpi, prints the SHA-256 of the pixels it hands
Vision so the input is pinned, and prints every recognized line. `MODE` selects the options:
`en` sets the recognition language only, `correct` enables language correction only, `correct+en`
both, and `library` matches what our converter does.

## Expected

With `recognitionLanguages = [en-US]`, the transcription contains characters that can occur in
English. A glyph the recognizer cannot read as English is better returned as a low-confidence
Latin candidate, or omitted, than as a character from another script.

## Actual

The same page, the same pixels (`image sha256 20a2…`), in all four configurations:

| Mode | `recognitionLanguages` | `useLanguageCorrection` | Line as returned |
| --- | --- | --- | --- |
| `library` | `[en-US]` | false | `НИН?!` |
| `en` | `[en-US]` | false | `НИН?!` |
| `correct` | default | true | `НИН?!` |
| `correct+en` | `[en-US]` | true | `НИН?!` |

Neither restricting the language nor enabling language correction changes the result.

Across the 27 recognized pages of that document the transcription contains 14 tokens holding
Cyrillic. Four are pure homoglyph substitutions a caller can map back (`МАУВЕ` → `MAYBE`,
`HА` → `HA`, `OН` → `OH`, `UН?` → `UH?`). The other ten turn on `Д` where `A` is drawn and `И`
where `U` is drawn — `ОКДУ` for `OKAY`, `НИН` for `HUH`, `УДУУ` for `YAYY` — which are not
homoglyphs and which no mapping recovers.

## Notes

The pages concerned are hand-lettered all-capital exclamations in speech balloons, so this is a
hard recognition case. The report is about the script of the output rather than the accuracy of
the reading: whatever the recognizer's confidence, an English-restricted request returning
`U+0418` is a result the caller cannot use.

Attachment: `probe.swift`, a single file using only Foundation, PDFKit, Vision and CryptoKit.
