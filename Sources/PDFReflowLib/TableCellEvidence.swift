import CoreGraphics
import Foundation

/// Whether a table a recognition *located* on a scanned page is a table it *read* (#31).
///
/// Vision returns a document's tables as a grid of cells, and it returns one for a page of
/// handwriting as readily as for a page of type. Nothing in the result says which it read: both
/// come back as rows and columns, with no confidence attached to the grid and none to a cell.
/// Believing the grid is how a reader is handed a table of invented numbers, which is the mirror
/// of the trap this issue names on the signaling side — a warning is not evidence of correct
/// cells, and neither is a grid.
///
/// The evidence that separates them is the grid's own emptiness. A table the recognizer read
/// fills most of its cells, because the page printed a value in most of them; a grid it drew over
/// writing it could not read is ruled far wider than the page and left mostly blank, because only
/// the few pieces it did transcribe have anywhere to go. Measured through this library's own
/// rasterizer and reading (`tools/probes/probe-table-cell-evidence.swift`):
///
/// | Page | Grid | Cells transcribed |
/// | --- | --- | --- |
/// | USGS copper 1 (tariff) | 6 × 3 | 17 of 18 (94%) |
/// | Blue Book 74 (typewritten `TABLE IV`) | 12 × 5 | 50 of 60 (83%) |
/// | USGS copper 1 (salient statistics) | 24 × 6 | 97 of 144 (67%) |
/// | USGS copper 2 (world production) | 21 × 6 | 79 of 126 (63%) |
/// | Blue Book 150 (handwritten `TABLE A63`) | 15 × 26 | 104 of 390 (27%) |
/// | Blue Book 150 (second grid) | 15 × 25 | 49 of 375 (13%) |
///
/// The lowest table the recognizer read and the highest it did not are 36 points of fill apart,
/// with nothing between them, so the rule is `minimumTranscribedCells`: half. Page 150 states the
/// cost of believing the other side. The page rules four grids of 25 columns; the reading returns
/// two, of 26 and 25 columns, so half the page's tables are missing before a cell is read, and
/// what it does return holds `276） 110 450`, `E罗丝` and `即多點由名，以后` where the page has
/// `270 180 450` in ink. Neither page's reading says any of this: both come back as tables.
///
/// The share is read from the grid, not from the cells' own text, so it needs no lexicon and
/// judges a page of Chinese or Arabic exactly as it judges this one. What the cells say is
/// evidence of nothing: page 74's `7,14` for `7.14` and `29.05ł` for `29.05` read as data and are
/// wrong, which is why a table this measure believes is still only preserved and reported, never
/// transcribed into the reader's text.
///
/// A grid smaller than `minimumJudgedCells` says too little either way and is not judged, so no
/// two-cell region the recognizer happens to call a table changes what a page reports.
enum TableCellEvidence {
    /// How much of a located table the reading transcribed. The rectangle is the table's, in
    /// whatever space its recognition was mapped into.
    struct Reading: Equatable, Codable, Sendable {
        var rect: CGRect
        /// The grid the recognition returned. It is the *reading's* shape, not the page's: on a
        /// page it could not read, the two disagree, which is part of what this measures.
        var rows: Int
        var columns: Int
        /// Cells in that grid, and those holding any transcription at all.
        var cells: Int
        var transcribedCells: Int

        init(rect: CGRect, rows: Int, columns: Int, cells: Int, transcribedCells: Int) {
            self.rect = rect
            self.rows = rows
            self.columns = columns
            self.cells = cells
            self.transcribedCells = transcribedCells
        }

        /// The share of the grid's cells carrying a transcription.
        var transcribedFraction: Double {
            cells == 0 ? 0 : Double(transcribedCells) / Double(cells)
        }

        /// Whether this grid is small enough that its fill says nothing.
        var isTooSmallToJudge: Bool { cells < minimumJudgedCells }

        /// Whether the reading transcribed this table's cells. A grid too small to judge is
        /// believed, which is what every recognition already assumed before this measure existed.
        var cellsWereRead: Bool {
            isTooSmallToJudge || transcribedFraction >= minimumTranscribedCells
        }
    }

    /// The share of a located table's cells that must carry a transcription for the reading to
    /// be one of its cells rather than a grid drawn over writing it could not read.
    static let minimumTranscribedCells = 0.5
    /// A grid with fewer cells than this is not judged.
    static let minimumJudgedCells = 9

    /// Reads a located table's grid, given its rows as the recognition returns them: one entry
    /// per cell, in reading order, holding that cell's transcription. A cell spanning several
    /// columns counts once, as the recognition counts it.
    static func reading(rect: CGRect, rows: [[String]], columns: Int) -> Reading {
        let transcribed = rows.reduce(0) { total, row in
            total + row.count { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return Reading(rect: rect, rows: rows.count, columns: columns,
                       cells: rows.count * columns, transcribedCells: transcribed)
    }

    /// The same table in another space, for mapping a reading out of normalized coordinates or
    /// back from a band of the page.
    static func placed(_ reading: Reading, in rect: CGRect) -> Reading {
        Reading(rect: rect, rows: reading.rows, columns: reading.columns,
                cells: reading.cells, transcribedCells: reading.transcribedCells)
    }

    /// Two readings of one table joined, which is what a table crossing a band retry's split
    /// becomes: the grid they cover together, and the cells each of them read.
    static func joined(_ first: Reading, _ second: Reading) -> Reading {
        Reading(rect: first.rect.union(second.rect), rows: first.rows + second.rows,
                columns: max(first.columns, second.columns),
                cells: first.cells + second.cells,
                transcribedCells: first.transcribedCells + second.transcribedCells)
    }
}
