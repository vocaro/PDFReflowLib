# Inherited handwriting still passing the text-layer check (#216)

Source: checksum-pinned Warren survey at commit `4afe5c39`,
`measurements/suspect-text-layers/scores-inherited.tsv` and its `record.md`. The current
`TextLayerPlausibility` word and ink rules leave the inherited layers on these pages under the
automatic OCR policy. The other explicit #216 examples are covered by `720ef267` (Warren 555),
`10be4931` and `642aaf51` (carbon typescripts), and `fe76dc7f` (OCR headings).

| Warren page | English / judged words | Misread / all words | Uncovered rows | Uncovered ink | Current finding / disposition |
| ---: | ---: | ---: | ---: | ---: | --- |
| 289 | 11 / 15 | 3 / 24 | 5 | 54.3% | Fewer than 20 judged words; fewer than 7 uncovered rows |
| 291 | 12 / 18 | 2 / 30 | 7 | 73.4% | Fewer than 20 judged words; uncovered ink below 75% |
| 292 | 22 / 37 | 6 / 65 | 59 | 53.3% | Now flagged above the 8.5% misread cut; comparison keeps the layer when recognition reads worse |
| 301 | 23 / 24 | 0 / 30 | 24 | 40.2% | Printed heading reads well; handwritten body does not leave enough uncovered ink |
| 339 | 17 / 22 | 0 / 37 | 35 | 56.4% | No misread words; uncovered ink below 75% |
| 547 | 16 / 27 | 3 / 44 | 0 | 0% | OCR boxes cover the handwriting |
| 548 | 7 / 17 | 2 / 48 | 0 | 0% | Fewer than 20 judged words; OCR boxes cover the handwriting |
| 550 | 10 / 18 | 3 / 31 | 0 | 0% | Fewer than 20 judged words; OCR boxes cover the handwriting |
| 551 | 12 / 21 | 2 / 52 | 17 | 60.5% | Misread share below cut; uncovered ink below 75% |

The survey also includes unaffected sparse pages. Blue Book 148 has 52.4% English judged words
and 75.8% uncovered ink, but is a numeric table; Warren 148 is a photographed group of printed
forms and handwritten marks with 75.6% English, 6.2% misread and 35.3% uncovered ink. NOAA 139
is a chapter cover with only eight English words and 63.3% uncovered ink. Warren 225 is a floor
plan with 26 English words, 39 uncovered rows and 40.3% uncovered ink. A lower English or ink
threshold across these pages would also catch source content that the current rules correctly
keep. Page 301 and 339 have no misread words at all, while pages 547, 548 and 550 have no
uncovered rows, so neither existing signal alone can solve the remaining handwriting cases. The
surveyed fresh OCR of page 292 has only 94 English words of 233 judged and is discarded as noise.
`RecognitionPolicy` therefore keeps the flagged inherited layer under its compare mode, as it
must for damaged printed typescripts whose new OCR reads worse.

No additional heuristic was adopted from these measurements. #216 still needs a
document-independent way to distinguish a legible printed heading or table over a scan from
handwriting whose OCR layer only looks plausible in aggregate, with controls for both classes.
