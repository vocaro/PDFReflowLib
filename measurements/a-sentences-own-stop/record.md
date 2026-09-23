# A sentence's own full stop is not a block (#291)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: every cached source, with the USCIS Arabic guide (`M-618_a`) as the subject.
Build: `main` at `dd24ee6` with this change, Xcode 27.0, macOS 27.0 (Darwin 27.0.0).
Baseline: `dd24ee6` alone.

## The defect

The USCIS guide sets its writing right to left, so the mark that ends a sentence sits at the far
left of the last line and PDFKit hands it back as a line of its own, standing clear of the rest.
Four of them reflowed as blocks, and **one as a heading**:

```
[558] <p>  تعد المساعدة المؤقتة للأسر الفقيرة بمثابة برنامج فدرالي يقدم المساعدة …
[559] <h2> المساعدة الخاصة بالمهاجرين من ذوي الاحتياجات الخاصة
[560] <h2> .
[561] <p>  قد يكون المهاجرون ذوي الاحتياجات الخاصة مؤهلين للحصول على الرعاية الطبية …
[562] <h2> مراكز رعاية الأفراد المتوقفين عن العمل.
```

The same page sets the same kind of heading with its stop attached, at `[562]`.

[#41](https://github.com/vocaro/PDFReflowLib/issues/41) already puts such a stop back against its
sentence where the extractor split one **printed row** — `ArabicText.setsNoSpace` closes it up
with the page's own space — but a stop that is a whole line is no piece of a row, so nothing
reached it.

## The rule

`carryStrandedStops` joins a block whose whole text is one sentence-ending mark to the block
directly above it. One mark and one only — `.`, `?`, `!`, or the full stop Arabic and Urdu draw —
because every other word-less block in this corpus is something the page meant:

| what | where | count |
| --- | --- | ---: |
| footnote rules `——————` | *Loper Bright*, IRS 596 | 21 |
| an elision `...` inside a quotation | 9/11 report | 3 |
| a section break `* * *` | *Loper Bright* | 1 |
| the operators `=`, `·`, `−`, `+` of a worked example | Wallace | 46 |
| an inherited OCR reading of a ruled page | Project Blue Book | ~1,000 |

And only where the block above is **text the sentence could have come from**, on the same page,
that does not already end in a stop of its own. A picture between them is reason to leave it: the
guide's page 86 sets its stop between two preserved regions, and which sentence it closes is not
something this rule can see, so that one stays as it was.

## What moved

**Sixteen of the twenty-two cached sources are byte-identical.** Six move, and in every one **the
text is identical character for character** — only block boundaries change:

| case | blocks | marks | sites |
| --- | ---: | ---: | ---: |
| uscis-m618-arabic-2015 | 815 → 812 | 94,511 → 94,511 | 3 |
| cia-blue-book-14-1955 | 22,470 → 22,452 | 613,523 → 613,523 | 18 |
| faa-phak-8083-25c | 9,016 → 9,015 | 1,429,887 → 1,429,887 | 1 |
| wallace-algebra-2010 | 9,187 → 9,186 | 366,232 → 366,232 | 1 |
| Pro Se 1 complaint | 175 → 174 | 7,020 → 7,020 | 1 |
| `20190030725` (cached, not in the manifest) | 410 → 409 | 28,406 → 28,406 | 1 |

All twenty-five sites were read. The three in the Arabic guide are the ones this issue names,
including the heading. The other four in books that set left to right are the same shape, and each
closes a sentence the page prints closed:

```
…principal place of business in the State of (name)   +  .  →  …(name).
…Figure 5-59. Radius at 120 knots with bank angle of 30°  +  .  →  …30°.
…developed a method to solve problems with x3         +  .  →  …x3.
```

Project Blue Book's eighteen are its inherited OCR: a stray `.` or `?` that was a block of its own
becomes part of the noise line above it — `I 40.`, `2-Airtraft?` — which is one fewer meaningless
block each time and no worse in any case. Nothing is added, and no book gains or loses a mark.

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. The corpus lane passes 18 of 18
covered cases, every case's `runPassed` and content assessment read from its own `result.json` and
`content-assessment.json`. All 686 Swift tests pass.

One test is added to `Tests/PDFReflowLibTests/BrokenNumberedItemTests.swift`, citing #291: a stop
standing clear of the sentence it closes, joined with nothing between them; an ellipsis, a rule of
dashes, a section break and two operators each left as a block of their own; and a stop under a
sentence that already ends in one, left alone. With `carryStrandedStops` removed, the first two
assertions fail.

## What is not claimed

The twenty-five sites were read as the text above; no page was read against its own rendering, and
the Blue Book's eighteen are judged only as noise that was already noise. A stop separated from
its sentence by a picture is left where it is, which is the guide's page 86 and is the one of its
four this does not reach.
