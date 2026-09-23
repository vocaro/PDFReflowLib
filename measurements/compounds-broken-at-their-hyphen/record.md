# A compound the page broke at its own hyphen (#288)

Tier: deterministic Apple PDF stack, isolated macOS arm64 release CLI.
Corpus: every cached source, with *The 9/11 Commission Report* as the subject.
Build: `main` at `8301eaa` with this change, Xcode 27.0, macOS 27.0 (Darwin 27.0.0).
Baseline: `8301eaa` alone.

## The defect

`HyphenRepair.joinOperation` opened with

```swift
guard left.hasSuffix("-"), right.first?.isLowercase == true else { return .space }
```

so a line-end hyphen was read as a break only where the next line opened in lowercase. A compound
the page broke at its own hyphen before a capital or a digit fell through to `.space`, and the two
halves came out a space apart although the page drew none:

```
…vectored an unarmed National Guard C- 130H cargo aircraft, which…
…military intelligence service (Inter- Services Intelligence Directorate…
…mosque in Brooklyn. In the mid- 1980s, it had been set up as…
…since he refused to meet with non- Muslims. The United States…
…disagreements about ongoing Israeli- Palestinian violence…
```

Everything after that guard — the book's own vocabulary, `lexiconVouches`, the `uncertainHyphen`
warning — was unreachable for these lines, so nothing was warned either.

**The book's own text is the evidence.** Of the 9/11 report's 45 distinct broken compounds, 34
appear closed somewhere else in the same book: `pre-9/11` twelve times, `Goldwater-Nichols` nine,
`After-Action` nine, `anti-Taliban` six, `315N-NY` forty-one. The eleven that do not are
`CENT-COM`, `Al-Ballushi`, `non-NATO`, `MI-5`, `Afghan-Bosnian` and report serials, which no
reader takes as two words either.

## The rule

A hard line-end hyphen is a break whatever opens beneath it, and the halves close up on it: the
page drew no space there. Where the next line opens **in lowercase**, the join is decided exactly
as before, on the letters either side. Where it opens with a **capital or a digit**, the page has
broken a printed compound at its own hyphen, so the hyphen stands — unless the book writes the
word whole and never the compound, which is the same lookup the lowercase side already makes.

Two letters are asked either side, as `lexiconVouches` asks for the same reason. Without that
bound the 9/11 report's `…citing 265A-` over `NY-280350-302` reads `a` + `ny` as `any`, a word
that book writes on nearly every page, and the file number came out `265ANY`. With it, `CENT-` and
`COM` still make `CENTCOM`, which that report writes whole.

No warning is raised on that side. `uncertainHyphen` is about a break the book's words cannot
decide; a compound broken at the hyphen the page prints is not that case, and the hyphen it keeps
is the one the page drew.

## What moved, book by book

Every cached source was converted with both executables at `--no-ocr` and fixed packaging, one
book at a time. Twelve of the twenty-two are byte-identical. The ten that move were each converted
again with both binaries and compared block by block and character by character:

| case | blocks | spaces closed on a kept hyphen | hyphens removed |
| --- | ---: | ---: | ---: |
| gpo-911-2004 | 4,992 → 4,992 | 58 | 2 (`CENT- COM` → `CENTCOM`, twice) |
| cia-blue-book-14-1955 | 22,048 → 22,048 | 28 | 0 |
| faa-phak-8083-25c | 8,396 → 8,396 | 5 | 0 |
| `20200002975` (cached) | 448 → 448 | 4 | 0 |
| scotus-loper-bright-2024 | 731 → 731 | 3 | 0 |
| census-rrs2002-01 | 368 → 368 | 3 | 0 |
| `THM…STI-Review` (cached) | 33 → 33 | 2 | 0 |
| arxiv-replay-clocks-2023 | 195 → 195 | 1 | 0 |
| wallace-algebra-2010 | 7,014 → 7,014 | 1 | 0 |
| fed-explained-2021 | 842 → 842 | 1 | 0 |

**No book gains or loses a block.** The character multiset of every book's marks is identical
before and after except the 9/11 report's, which differs in exactly one character: two fewer
hyphens, the two `CENTCOM`s. Everything else this change does is remove 106 spaces that were
never printed.

Each of the two hyphen removals was read. The rest were read as the pairs above and as the
per-book counts; a sample of what the 9/11 report gains:

```
C- 130H            → C-130H              mid- November   → mid-November
Inter- Services    → Inter-Services      Hizbul- Ittihad → Hizbul-Ittihad
mid- 1980s         → mid-1980s           anti- Taliban   → anti-Taliban
non- Muslims       → non-Muslims         Israeli- Palestinian → Israeli-Palestinian
```

## Gates

`scripts/check-all.sh --fast` passes, exit status read directly. The corpus lane passes 18 of 18
covered cases, every case's `runPassed` and content assessment read from its own `result.json` and
`content-assessment.json`. All 678 Swift tests pass.

One test is added to `Tests/PDFReflowLibTests/HyphenRepairTests.swift`, citing #288: the digit and
capital continuations, the two-letter bound with its `265A-`/`NY` case, `CENT-`/`COM` where the
book's word decides, the silence of the warning on that side, and the controls — a lowercase
continuation decided exactly as before, warning and all, and a line that does not end in a hyphen
still taking a space.

One existing assertion changed. `theSubstituteJoinsExactlyAsThePrintedHyphenWould` (#233) pinned
`the total=` + `Next Section` as `the total- Next Section`; it now reads `the total-Next Section`,
because that is the same rule seen through the substitute character, and a page that ends a line
with a hyphen draws no space after it. The case is synthetic; nothing in the corpus depends on it.

## What is not claimed

This is about a hyphen *inside a paragraph the reading has already joined*. It says nothing about
whether two blocks should join, which is #280 — and that issue's serial-number half is downstream
of this one, because it could not be repaired while this rule would spell the result
`265A-NY- 280350-302`. It also leaves the `uncertainHyphen` population exactly where it was.
