# Decisions

One file per architectural decision, numbered in the order they were recorded. Each states the
context, the decision, its consequences, and the measurement record, commit or issue that backs
it. Records under `measurements/` are frozen evidence and are linked, not restated.

| Decision | Backed by |
| --- | --- |
| [0001 Two passes over the pages, with a spill store between them](0001-two-pass-page-retention.md) | [page-retention](../../measurements/page-retention/record.md) |
| [0002 One process-wide gate for PDFKit extraction, drained before it unlocks](0002-pdfkit-extraction-gate.md) | [pdfkit-concurrency](../../measurements/pdfkit-concurrency/record.md), [pdfkit-gate-drain](../../measurements/pdfkit-gate-drain/record.md), [extraction-cancellation](../../measurements/extraction-cancellation/record.md) |
| [0003 Ordered, awaited progress callbacks rather than native progress trees](0003-awaited-progress-callbacks.md) | [progress-composition](../../measurements/progress-composition/record.md) |
| [0004 Byte-identical output is the gate for a refactor](0004-byte-identity-gate.md) | `tools/epub_identity.py`, [page-retention](../../measurements/page-retention/record.md) |
| [0005 The coordination branch is abandoned; features are hand-ported onto main](0005-abandoned-coordination-branch.md) | commit `dd160b4` and the porting commits it lists |
| [0006 Measurements are records, not captures](0006-measurements-are-records.md) | `tools/check_measurements.py` |
| [0007 Records cite commits and paths in prose; nothing pins them by machine](0007-records-cite-commits-in-prose.md) | the pointer lines atop moved records |
| [0008 Reconstruction streams its blocks to the writer](0008-streamed-blocks-to-the-writer.md) | [streamed-blocks](../../measurements/streamed-blocks/record.md) |
| [0009 An unmeasured memory ceiling is reported as unmeasured, not as a failure](0009-an-unmeasured-ceiling-is-not-a-failure.md) | [memory-pressure-false-failures](../../measurements/memory-pressure-false-failures/record.md) |
| [0010 A destination that names a page is resolved after the last spine document closes](0010-deferred-page-destinations.md) | [outline-navigation](../../measurements/outline-navigation/record.md), [converted-links](../../measurements/converted-links/record.md) |
| [0011 A picture a cross-page join steps over keeps its side of the page marker](0011-a-picture-keeps-its-side-of-the-page-marker.md) | [box-placement-and-split-rows](../../measurements/box-placement-and-split-rows/record.md) |
| [0012 An issue is closed by what main's tree holds, not by a commit that names it](0012-an-issue-is-closed-by-what-main-holds.md) | `tools/check_closing_commits.py`, the reconciliation on [#231](https://github.com/vocaro/PDFReflowLib/issues/231) |

Approaches that were tried and rejected without becoming an architectural rule are in
[research notes](../research-notes.md). Open work belongs in GitHub issues, not here.

To add a decision: copy the section headings (Context, Decision, Consequences, Evidence), take
the next number, and add a row above. A decision that supersedes another says so in both files;
neither is deleted.
