# Measurement records

Each directory holds the evidence for one investigation. `record.md` is the record; the other files
support it. Keep a directory small enough that a reviewer can read what it holds.

**Commit:**

- `record.md`, with every number the conclusion rests on written out as prose or a table. Don't
  write "see the log" when the number itself fits in a sentence.
- The scripts and tools that produce the measurement (`*.py`, `*.swift`, `*.sh`) and the exact
  command lines, so the run can be repeated.
- Summaries and identities: `result.json` or `result.json.gz`, conversion reports, content
  assessments, comparison summaries, and `identity.json` with source, converter and fixture hashes.
- Anything code, a test, a doc or an issue reads or links to by path.
- Small crops or renders that show a visual finding, and the rejected patch or mutation log that a
  record's conclusion cites.

**Don't commit:**

- Raw per-case runner output that a summary already captures, such as `progress.log` and
  `memory-samples.json` in each book's lane directory. The runner's `result.json` records the
  progress check (event count and result) and peak memory. Several `collect.py` scripts copy these
  files into the measurement directory, so delete them before you commit.
- Per-page dumps, whole-book lane JSON and raw survey output that a recorded command regenerates,
  unless the record needs a specific file. Name that file in the record.
- EPUBs, original PDFs and other large binaries. Keep them in ignored `.build/` or cache
  directories.
- A text file over about 100 KB in its raw form. Gzip it with `gzip -9n` and name the `.gz` file
  in the record.

Test fixtures live in `Tests/PDFReflowLibTests/fixtures/`, not here. Never trim them: rules read
a page's body size, measure and neighbouring lines, so a trimmed fixture can stop reproducing its
bug without any error.

Issue #196 dropped the raw per-case progress logs and memory samples from existing records. The
records that held them say so.
