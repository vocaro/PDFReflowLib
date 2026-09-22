# The suspect-text excerpt's page 4 pins the finding, not which reading won (#269, #281)

Tier: deterministic replay of two captures; the variance below was measured on an isolated macOS
arm64 release CLI and on the capture probe built from the same sources.
Corpus: `gpo-warren-1964-suspect-text-excerpt`, `warren-suspect-text-excerpt.pdf`, SHA-256
`bfe984ba3327be017dd38bc4a100251292489efa6faa643b80682dae49b53348`; excerpt page 4 is physical
page 636 of the pinned Warren report, the faint carbon typescript #7 is built on.
Build: this change over `main` at `8da6d59`, Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0 (26A428,
Darwin 27.0.0, xnu-13432.1.9~1), EPUBCheck 5.3.0.

## What the case was pinning

Page 4's layer fails the misread test — 58 of 244 judged words misread, `tcld`, `ftboot`, `ftt` —
so `RecognitionPolicy.plan` returns `.compare`: the page is recognized again and the layer kept
unless the fresh reading misreads a smaller share of its own words. The contract pinned the
verdict of that comparison:

```json
"text": ["and he told me about the things at",
         "At 6:00 PM I instructed the officers to bring"],
"absentText": ["ftboot"],
"warningCodesAnyOf": ["ocrUsed"]
```

All three hold only if the recognition won. It wins by about five points — 18.8% of its own words
misread against the layer's 23.8% — and the losing side is re-measured on every run, because the
reading is Vision's.

## What the reading does between runs

Three captures of the same page image, taken minutes apart in one session with one probe
executable, through `tools/probes/capture-ocr-layout-fixture.swift`:

| capture | lines | characters | `and he told me about the things at` | `At 6:00 PM I instructed the officers to bring` |
| --- | ---: | ---: | --- | --- |
| 1 | 28 | 1,653 | present | present |
| 2 | — | — | the probe died before writing | |
| 3 | 28 | 1,647 | absent | absent |

Same bytes, same host, same source, minutes apart. Capture 1 is what the case's review read off the
source raster and is now checked in as `Tests/PDFReflowLibTests/fixtures/warren-636-recognition.json`;
capture 3 would fail every one of the three contract checks above.

Later the same session, with the host under the load of a 48-conversion measurement, five capture
attempts in a row produced nothing at all:

```
Fatal error: Error raised at top level:
TextRecognition.CRImageReaderError.e5rtError("e5rt_e5_compiler_compile call failed", 11)
```

The lane's page-4 checks would have failed on all five, on a tree that had not changed. That is
the shape #281's own controlled table found: the failures track how busy the Mac is, and `main`
reproduces them on its own once it is loaded.

## What is pinned now

The contract keeps what every run agrees on — the finding, and the page image:

```json
{ "page": 4, "warningCodesAnyOf": ["implausibleTextLayer"], "minimumImages": 1 }
```

`implausibleTextLayer` is raised on both branches of `RecognitionPolicy.reconcile`: a replaced
layer reports it with the `replaced` outcome beside `ocrUsed`, and a kept layer reports it with
`keptOverRecognition`. So the check says what it always said about this page — the library judged
its layer damaged and said so — without asserting the side of a comparison this host does not
decide reproducibly. The contract count falls from 611 checks to 608.

The evidence did not go; it moved to where it can be replayed.
`aMisreadCarbonTypescriptIsReplacedByARecognitionThatReadsBetter` puts the page's own captured
layer (`warren-636-layout.json`, already in the tree) and capture 1 of its recognition through
`RecognitionPolicy.plan` and `resolve` with the real English judge, and holds all of it: the plan
is `.compare(misread:words:)`, the disposition is `.replaced`, `ocrUsed` is raised, both phrases
are in the replacement, `ftboot` is not, and it is in the layer that was discarded. It also holds
the other branch — a failed recognition keeps the layer and still reports the finding — which is
why the contract can pin that finding. This is what #173 already does for the tables a recognition
locates: replay a capture rather than re-measure a reading.

What the test does not say, and says so in its own comment, is which reading Vision will return
next. Nothing in this repository can say that.

## Corpus

The lane was run whole at five jobs on the tree this change sits on, before it: 18 of 18 cases
`runPassed`, every `content-assessment.json` opened, all 18 `passed` with zero errors, including
this case. The flake is not reproducible on demand, which is the point of the issue.
