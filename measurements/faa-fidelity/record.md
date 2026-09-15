# FAA fidelity observations

The retained comparison screenshots show physical pages 91 and 121 of FAA-H-8083-25C,
522 pages, source SHA-256 `247929cace0ab56b376e683eba540cc4c8f39f199ab35414e8b604e24f395cb7`.
They are historical observations on macOS 27 arm64, before standalone publication; the
conversion algorithm is unchanged in the initial standalone implementation `5c38c48`.
The source is the FAA's Pilot's Handbook of Aeronautical Knowledge, a U.S. Government
publication. These are rendered comparison excerpts; the source PDF is not included.

- Page 91: left-column prose ending "must be defined." should precede right-column text
  beginning "The computation of density altitude". The conversion interleaves those columns.
- Page 511 (text inspection, not pictured): the left glossary's "Wind direction indicators."
  and "Wind shear." are interrupted by the right column's "Zone of confusion.".
- Page 121: the whole-page fallback has excessive white margins and undersized content
  compared with the original page. Incorrect rendering transforms are a hypothesis, not a
  proven root cause.

The corpus manifest records these open defects and reproduction pages. The current comparison
harness can regenerate results with `scripts/compare-pdf-reflow.sh --pdf /path/to/faa-h-8083-25c.pdf
--pages 91,121,511 --output /tmp/faa-review --serve` (run as one shell command).
These findings do not establish the correctness of other source pages.
