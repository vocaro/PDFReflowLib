# A page number a contents entry runs its leader out to belongs to that entry (#277)

Tier: deterministic Apple PDF stack; source-derived extraction fixtures for the two pages, and an
isolated macOS arm64 release CLI at `--no-ocr` with fixed packaging for the corpus comparison.
Corpus: `cia-blue-book-14-1955` pages 5 and 7,
`CIA-UAP-015-Project_Blue_Book_Special_Report_No_14.pdf`, SHA-256
`90e05e77fc088c29758c2ddda514c0c12f317e5686ee213d348db2f9da152ee3`, with
all 23 cached sources converted for the comparison.
Build: this change over `main` at `2001391`, Xcode 27.0 (27A266a), Swift 6.4, macOS 27.0 (26A428,
Darwin 27.0.0, xnu-13432.1.9~1); release executable SHA-256
`78416ee97cbbf61a04fe7142e5cabe40552d5611ea5d7c3d407f23b208c70b67`, against `2001391`'s
`ff3bbc7e4070a4df9ec44c89918000729c129b8f138d669316933a97c4f72aca`.

## The page

Project Blue Book sets its contents and its list of illustrations in three columns: the `Figure N`
or `Table N` label at x≈82, the title at x≈125, and the page number at the right margin, x≈536.
The white between the titles and the numbers is what the leaders cross — well over a hundred
points, where a gutter needs three quarters of a body — so `LayoutReconstructor.ordered`'s
straight column cut was made, and each band read out its entries and then their numbers:

```
Figure 3
Figure 4
Distribution of Object Sightings by Evaluation for All Years With Comparisons of Each Year …
Distribution of Object Sightings by Evaluation for All Years and Each Year
17
18
19
20
```

Until #264 the geometry of these pages was unusable: the rule the book paints down its margin was
merged into the line beside it, so no gutter was found at all and the lines fell through to the
row sort. With the rule kept out of the line the gutters are visible for the first time, and this
is what they expose.

## The rule

A straight cut is refused where one side of the white is the page numbers of the entries on the
other side. The side must hold nothing else: every element a text piece no wider than three
bodies, standing on the row of a line beside it, and reading as a number — a numeral, a roman
numeral, or a token of at most six characters that holds a digit and spells no word. That last
form is what a scanned layer leaves when it misreads one: this same book hands back `ti6` for the
page number 66, in a column where every other entry reads as a figure, and without it the band
holding Tables IV to VII was still cut.

It is deliberately narrow. A page's second column is prose and fails at its first line, and the
measures are the page's own, so a line the page lettered sideways — whose rectangle is as tall as
the line is long and as narrow as the line is thick — is never one of these numbers (#263).

## Before and after

Both pages now read label, title, number, and then the next entry. Page 5's list of illustrations
runs `Figure 1` … `17`, `Figure 2` … `18`, and so on through `Figure 13` … `29`; page 7 runs
`Table IV` … `64`, `Table V` … `65`, `Table VI` … `ti6`, `Table VII` … `67`. No band hands its
numbers over in a run of their own, which is the whole of the defect, and that is what
`aContentsEntryKeepsThePageNumberItsLeaderRunsOutTo` holds.

The same guard was first written to cover the 9/11 report's appendix of names as well (#283),
where twenty-three rows of a name against an office read column by column as soon as the one row
PDFKit hands back whole is divided at its gutter. Generalized to *any* short cell standing on the
row of a line beside it, it moved ten of the twenty-two cached books, several of them by dozens of
blocks, so it was narrowed back to the page numbers this issue is about. #283 stays open, and the
measurement of the general form is the reason.

## Corpus

All 23 cached sources converted with the executable before this change and with it, at `--no-ocr`
with fixed packaging. The full Warren report and the NOAA assessment are excluded, as the corpus
lane excludes them (#242, #5). This change and #282's share one measurement run; each book is
named by the rule that moved it. **Eighteen of the twenty-two are byte-identical.** Two move here:

| book | documents | what moved |
| --- | --- | --- |
| `cia-blue-book-14-1955` | 6 of 20 | page numbers rejoin their entries; every document keeps its character count to the character |
| `complaint_for_a_civil_case` | 1 of 2 | the form's title is read before the section number beside it |

The Blue Book's six documents hold its contents pages, its list of illustrations and four of its
index pages, and every edit in them is a number moving to sit with the entry it belongs to:
`17`, `18`, `19` on the contents pages, `140`, `141` and `220`, `222` in the index. No document
gains or loses a character — 52,289, 49,959, 40,189, 37,554, 49,189 and 46,821 before and after —
which is what a reordering looks like and what a lost or duplicated cell would not.

The civil-complaint form prints `I.` beside `COMPLAINT FOR A CIVIL CASE`, and the roman numeral was
being cut away as a column of its own and read first:

```
-<p><strong>I.</strong></p>
-<p><strong>COMPLAINT FOR A CIVIL CASE</strong></p>
+<p><strong>COMPLAINT FOR A CIVIL CASE</strong></p>
+<p><strong>I.</strong></p>
```

The other two books that move in this run, the Replay Clocks paper and the Census paper, are
#282's and are measured there.

## Gates

`swift test` passes with the two new tests, and both fail on this tree with the guard disabled —
`Figure 2 is missing, or stands before 4` on page 5, which is the defect this issue reports.
