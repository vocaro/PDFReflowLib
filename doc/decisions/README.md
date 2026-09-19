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

Approaches that were tried and rejected without becoming an architectural rule are in
[research notes](../research-notes.md). Open work belongs in GitHub issues, not here.

To add a decision: copy the section headings (Context, Decision, Consequences, Evidence), take
the next number, and add a row above. A decision that supersedes another says so in both files;
neither is deleted.
