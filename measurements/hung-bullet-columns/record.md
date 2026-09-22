# A hanging bullet column is not a column (#279)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI, `--no-ocr` with fixed
packaging (`--package-identifier`, `--modification-date`), so two books differ only where the
reading does.
Corpus: every one of the 23 cached sources, the subject being the FAA handbook,
`faa-h-8083-25c.pdf`, SHA-256
`247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7`.
Build: this change over `main` at `8da6d59`, Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0 (26A428,
Darwin 27.0.0, xnu-13432.1.9~1), EPUBCheck 5.3.0; release executable SHA-256
`ff3bbc7e4070a4df9ec44c89918000729c129b8f138d669316933a97c4f72aca`.
Baseline: `8da6d59` itself, executable SHA-256
`1aae76f4eedf524de591ff80c75d2e7cae1f3ca1c47ed545a722654971a183b0`.

## The page

The FAA handbook hangs its bullets 18 points clear of their items on a ten-point body, so PDFKit
returns a marker and its item as two lines on one baseline. Page 31 prints the sport-pilot hours
as six one-line items:

```
[ 285.00 513.67 237.00 11.47] | To become a sport pilot, the student pilot is required to have
[ 285.00 501.17 236.99 11.47] | flown, at a minimum, the following hours depending upon
[ 285.00 488.67  46.37 11.47] | the aircraft:
[ 294.00 471.67   3.50 11.47] | •
[ 312.00 471.67  74.99 11.47] | Airplane: 20 hours
[ 294.00 454.67   3.50 11.47] | •
[ 312.00 454.67 116.92 11.47] | Powered Parachute: 12 hours
…
```

Each marker chains onto the run the introduction opened — it stands within a body beneath that
run's last line and overlaps its measure — and the run is then substantial, because the
*introduction's* lines are wide. The six items form a substantial run beside it. `columnRuns`
reads two columns and hands all six markers over before any of their items, and #261's rule, which
joins a marker to the piece on its own printed row, has no rows left to read by then:

```
<pre>•</pre>  ×6
<p>Airplane: 20 hours Powered Parachute: 12 hours Weight-Shift Control (Trikes): 20 hours …</p>
```

Page 239 does the same with the four items of its ELT inspection list. The two pages are the whole
of it in this book: after #261 the handbook held 10 blocks that were a bare bullet, six here and
four there, against 54 before it. The lines carry no structure tags on either page, so this is the
spatial reading order alone.

## The rule

A bullet is never a column of its own (#261), so a stack of them describes no column of the page,
whatever it chains onto. `markersKeepTheirItems` refuses a decomposition in which a run holds a
marker the page hung clear of its item and another run holds that item: read out as columns, the
two are separated and nothing downstream can put them back. The run holds no substantial line of
its own — it borrowed its substance from the paragraph above it — which is what the substance test
already refuses, one step removed.

The marker and its item must be a marker and its item, not two columns, which is `opensAloneAsBullet`'s
question and `hangingIndentBound`'s measured gap: of 897 bullet-alone lines in the pinned sources,
556 stand within two bodies of the piece beside them, the widest at 1.89, and every one of the 40
beyond 2.09 bodies is a column or a cell — the Blue Book sets one 12.2 bodies from its marker, the
Warren Commission 5.2 and 8.1. Those are read as the columns they are.

## Before and after

All 23 cached sources converted with both executables. **Twenty-two are byte-identical**, including
the Blue Book (71 bare-bullet blocks, unchanged: those are legend keys and columns) and Wallace
(4, unchanged). One book moves:

| book | bare-bullet blocks | documents differing |
| --- | ---: | ---: |
| FAA handbook | 10 → 0 | 3 of 36 |

Page 31 and page 239 now read each marker with the item it marks:

```
-<pre>•</pre> ×6
-<p>Airplane: 20 hours Powered Parachute: 12 hours Weight-Shift Control (Trikes): 20 hours …</p>
+<p>• Airplane: 20 hours</p>
+<p>• Powered Parachute: 12 hours</p>
+<p>• Weight-Shift Control (Trikes): 20 hours</p>
+<p>• Glider: 10 hours</p>
+<p>• Rotorcraft (gyroplane only): 20 hours</p>
+<pre>• Lighter-Than-Air: 20 hours (airship) or 7 hours</pre>
```

The handbook's whole spine text is the same length to the character (1,680,934 both). Every
difference in it is one of these markers moving from a block of its own to the head of its item,
plus one spine boundary: the `PHAK Front Matter` marker moves by one paragraph, so chapter 3 gains
a block (296 → 297) and chapter 4 loses one (242 → 241). No word moved.

## Gates

`swift test` passes with the two new tests; the five OCR tests that fail on this host fail on
`main` at `c56098e` in the same way and for the same reason (Vision returning no text — see
measurements/warren-excerpt-recognition-comparison/record.md). The corpus lane was run whole at
five jobs against this executable: 18 of 18 covered cases `runPassed`, every
`content-assessment.json` opened, all 18 `passed` with zero errors and EPUBCheck clean, the FAA
handbook's own 87 content checks among them.
