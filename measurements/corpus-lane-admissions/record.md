# Corpus-lane admissions: the Warren report and the Fifth National Climate Assessment

Tier: deterministic Apple PDF/OCR stack, library defaults, isolated release CLI on macOS 27.0
(26A428) arm64, Xcode 27.0 (27A266a), EPUBCheck 5.3.0. Build: `8faeaab`, `swift build -c release`,
executable SHA-256 `497df75a3954f6c475ef9f6afe480ff695a30fad4b14254ddc6d4ec26d951cad`. Sources:
`gpo-warren-1964`, 920 pages, 81,216,909 bytes, SHA-256
`341cc3471750c9c3be68b95a34b52f6cbdc86c4392427a8483ee1c6bc53cfc19`; `noaa-nca5-2023`, 1,834
pages, 219,876,258 bytes, SHA-256 `1942cbf346dc2c711fea413d6d6543edb8bc1e3a88d4c3a85e733c6b6d3577bf`.

The owner ruled on #242 (2026-09-23) that both full conversions join the corpus lane: NOAA
because it fits the default 512 MiB output budget at library defaults since the page-reference
and embedded-image changes, Warren at the 0.105% margin the ruling accepts. This record is the
admission: what each book costs on this tree, the ceilings the manifest now carries, and the
source basis of every check the two contracts pin. The measurements that preceded it — the
default-budget failures, the explicit-cap NOAA runs and the encoding default — are in
`measurements/gpo-warren-1964/record.md`, `measurements/noaa-nca5-2023/record.md`,
`measurements/noaa-output-policies/record.md` and `measurements/image-encoding-default/record.md`,
and are not restated.

## What each book costs at library defaults

Each book was converted once through `tools/evaluate_real_document.py` — the lane's own
launcher, with its peak-RSS metric (`wait4`/`rusage`), EPUBCheck and progress checks — and then
again inside `tools/run_corpus_regressions.py --case noaa-nca5-2023 --case gpo-warren-1964
--jobs 2`, both books at once, with the ceilings below in the manifest.

| | NOAA, alone | NOAA, lane (2 jobs) | Warren, alone | Warren, lane (2 jobs) |
| --- | ---: | ---: | ---: | ---: |
| Exit, EPUBCheck, structure | 0, 0, passed | 0, 0, passed | 0, 0, passed | 0, 0, passed |
| Wall seconds | 119.3 | 109.5 | 522.9 | 445.6 |
| CPU seconds | 114.5 | — | 448.7 | — |
| Peak RSS, bytes | 929,972,224 (886.9 MiB) | 909,803,520 (867.7 MiB) | 1,231,536,128 (1,174.5 MiB) | 1,204,060,160 (1,148.3 MiB) |
| Ceiling | none yet | 1,280 MiB, passed | none yet | 1,536 MiB, passed |
| Images | 1,609 (354 JPEG, 1,255 PNG) | 1,609 | 934, all JPEG | 934 |
| Entry bytes | 286,429,009 | same archive size | 536,305,614 | same archive size |
| Against 512 MiB | 0.533×, 250,441,903 inside | | 0.9989×, **565,298 inside (0.105%)** | |
| Image bytes | 279,164,430 | | 533,377,590 (3,493,322 inside) | |
| Pages reflowed / recognized | 1,783 / 0 | | 905 / 14 | |
| Final EPUB bytes | 269,760,850 | 269,760,850 | 531,580,058 | 531,580,059 |

"Entry bytes" is the sum of every archive entry's uncompressed size, the figure #242 quotes and
the one the lane's content inspector holds to its own 512 MiB admission ceiling; the writer's
budget is applied to the image bytes by `PageAssetWriter` and to the text separately, so Warren's
margin under the budget that fails a conversion is 3,493,322 bytes, and its margin under the
inspector's ceiling is the 565,298 bytes above. Both are margins of the same OS build's ImageIO,
which is what the ruling accepted. Memory pressure stayed at level 1 (normal) through every run,
so every ceiling was measured, not left unmeasured (decision 0009).

Against the numbers #242 records on `f332c86`, 108 commits earlier: NOAA has 20 fewer images and
17,896,134 fewer entry bytes (1,629 and 304,325,143 there); Warren has 2 more images and 1,691
fewer entry bytes (932 and 536,307,305 there), so its margin is 565,298 bytes where the ruling
read 563,607. Neither difference changes the ruling's terms.

The lane run, `python3 tools/run_corpus_regressions.py --converter .build/release/pdf-reflow
--epubcheck /opt/homebrew/bin/epubcheck --output <dir> --case noaa-nca5-2023 --case
gpo-warren-1964 --jobs 2`, exited 0 with `PASS` for both, each case's `result.json` reading
`runPassed` true and its `content-assessment.json` zero errors. The two archives differ from the
single runs by nothing but the per-run package identifier and date (NOAA's final size is
identical; Warren's differs by one byte of ZIP metadata), so the conversions are repeatable
across runs on this host, as the contracts require. Warren, not NOAA, is the slowest case in the
lane — 523 seconds alone, 446 in the two-job run — with the recognition of its 14 pages and the
JPEG encoding of 934 page scans the bulk of it; NOAA's 119 seconds alone (110 in the lane) still
exceed the 103 seconds decision 0009 records for a conversion of the FAA handbook. The lane
starts its largest sources first, so with `--jobs 2` these two run together from the start.

## The ceilings

`corpus/manifest.json` now carries `memoryBudget.maxPeakRSSMiB` 1,280 for NOAA and 1,536 for
Warren. Each stands about 1.3–1.45× above the peak measured alone, the headroom the corpus's
other ceilings carry (the suspect-text excerpt at 724 MiB under 1,024; the USDA magazine at 279
under 512), and above the 1–13% by which parallel runs read peaks higher than serial ones
([parallel-gates](../parallel-gates/record.md)). They are regression ceilings for release CLI
processes on this Mac, not device budgets. Every ceiling in the manifest now totals 10,752 MiB
(10.5 GiB), against the 7.5 GiB the runbook stated for eighteen cases.

## The contracts, and what they were read against

Every review page was rendered with `pdftoppm -f N -l N -r 100 -png` from the pinned source and
read; the Warren pages were also read against the inherited text layer (`pdftotext -layout`),
because a check on a scanned page may pin only what that layer already holds. Each contract was
then run against the finished conversion with `tools/check_corpus_content.py --case <id>
--evaluation <directory>` before the lane ran: NOAA 57 checks on 9 pages, Warren 87 checks on 9
pages, zero errors, and the same in both lane runs. The page-by-page basis is the `basis` field
of each case in `corpus/regressions.json`; what follows is what the pages showed.

### NOAA

The contents (page 8) prints the front-matter and chapter entries in one column with the painting
and its credit beside them; the contract pins the entries in that order, the painting's presence
and the credit. The converter sets some entries as preformatted lines and the chapter 3 entries
as a table, which is not pinned. The three chapter openers among the review pages (33, 80, 139)
are set alike — a running head over a large title over a photograph — and pages 80 and 139 emit
the title as a heading while page 33 emits the running head and the title in one paragraph; the
contract pins each page's two lines in order and its photograph, and page 33's title neither
way (#296). Page 48 is the state #181 recorded and #231 reconciled as closed with its fix only
on the abandoned coordination branch: the sub-heading's second line, the rest of the left column
and both captions sit inside the figure crop (`image-93`, 1,980 × 1,030 pixels, read to confirm
it holds them), so the contract pins the section heading, the sub-heading's first line and the
first two paragraphs, and the chart's presence. Page 84's Key Message 2.1 box is a crop holding
its own heading; the prose before and after it reflows in order with the running foot removed,
which is what is pinned. Page 1700's "Authors and Contributors" band is a crop; the title is a
heading and the roles and names follow in source order, with "Cover Art" joined to "David Zeiset"
in one paragraph, the class #215 records on page 1738. Page 1834, the back cover of fourteen
agency seals, keeps a page image (`unsupportedGraphics`, `pageImageFallback`).

### Warren

The 14 recognized pages (`ocrUsed` on 103, 201, 502, 545, 555, 566, 601, 602, 627, 629, 630, 632,
633, 635) and the 15 page-image fallbacks include none of the nine review pages except the two
textless cloth covers (1 and 920), which recognition read as nothing (`ocrFailed`) on this run.
Every other review page keeps its inherited layer under `unverifiedTextLayer`, decided by the
word test on the layer's own text, not by Vision; so each pinned line is one the layer holds and
the scan prints plainly, and the covers pin only their page images, because whether a different
compiled model reads nothing or noise on black cloth is not this repository's to pin (#173, #284,
and #269/#281 on the excerpt).

Page 7's seven printed lines reflow in order over a scrawled call number that the layer misreads
(`t ^^:l. f.`, `OL ^`), which is not pinned. Page 21's contents entries reflow in printed order;
the contract skips the three the layer misreads or the output alters — `The Lmicheon Site`,
`Retiu-n to Washington`, and `Chapter I.` set as `ChapterI.` — and pins 36 others. Page 30's
five printed paragraphs each reflow as one paragraph in order. Page 50, the review's h/b page,
pins the `unverifiedTextLayer` notice the review asked for and two sentences the layer holds
correctly; `bis known contacts witb tbe` is the layer's own reading and is pinned neither way.
Page 100 pins three sentences of running prose. Page 890's notes, which the review found
interleaved (415, 477, 416), now read the left column through 476 before 477 opens the right;
page 910's index, which the review found interrupting De Mohrenschildt with Federal Bureau of
Investigation, now reads the left column through Fair Play for Cuba Committee first, and no entry
is a heading. Both are pinned as order. The notes are set as preformatted blocks, the class #195
holds, and are not pinned as such.

Read but not pinned, and filed: on pages 21, 30, 50 and 100 the output drops word spaces the
layer states — `ChapterI.`, `twoon each runningboard`, `wasapproved`, `Houserepresenta-tives`,
`withvarious`, `whichhe`, `mustlook`, `whowere` — where `pdftotext` and the scan both hold the
space (#295).

## What changed in the repository

`corpus/regressions.json` gains both cases and its `excludedFullConversions` list is empty;
`corpus/manifest.json` carries both ceilings and restates each book's review and baseline
status; `doc/corpus.md`, `doc/regression-testing.md` and `doc/conversion-options.md` no longer
describe either book as excluded or over budget; the generated counts in `README.md` and the
runbook read 20 documents and 752 checks on 146 pages. No runtime source changed.
