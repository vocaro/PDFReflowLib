import Foundation
import CoreText
@testable import PDFReflowLib

struct SourceLayoutFixture: Decodable {
    struct Line: Decodable {
        var text: String
        var rect: [Double]
        var fontSize: Double
        var monospaced: Bool
    }
    struct AttributedLine: Decodable {
        struct Run: Decodable {
            var text: String
            var fontName: String
            var fontSize: Double
            var baselineOffset: Double
        }
        var text: String
        /// The PDFKit line's own rectangle, absent from captures taken before it was recorded.
        var rect: [Double]?
        var runs: [Run]
        func attributedString() -> NSAttributedString {
            let value = NSMutableAttributedString(string: "")
            for run in runs {
                var attributes: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): run.baselineOffset,
                ]
                attributes[.font] = pdfKitGated { PlatformFont(name: run.fontName, size: run.fontSize) }
                value.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            return value
        }
    }
    /// Captures before the version key was introduced decode as version 1.
    var schemaVersion: Int
    var sourceSHA256: String
    var page: Int
    var bounds: [Double]
    var lines: [Line]
    var graphics: [[Double]]
    /// The placed raster image XObjects among `graphics`, captured from schema version 2 on;
    /// an older capture carries none, which is the page every test of them was written against.
    var pictures: [[Double]]
    /// Exact filled rectangles and the source text inside them, captured from version 3 (#215).
    var filledCells: [[Double]]
    var filledCellText: [String]
    /// Styled runs, absent from the earliest captures; those fixtures serve geometry tests only.
    var attributedLines: [AttributedLine]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, sourceSHA256, page, bounds, lines, graphics, pictures, attributedLines, filledCells, filledCellText
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sourceSHA256 = try values.decode(String.self, forKey: .sourceSHA256)
        page = try values.decode(Int.self, forKey: .page)
        bounds = try values.decode([Double].self, forKey: .bounds)
        lines = try values.decode([Line].self, forKey: .lines)
        graphics = try values.decode([[Double]].self, forKey: .graphics)
        pictures = try values.decodeIfPresent([[Double]].self, forKey: .pictures) ?? []
        filledCells = try values.decodeIfPresent([[Double]].self, forKey: .filledCells) ?? []
        filledCellText = try values.decodeIfPresent([String].self, forKey: .filledCellText) ?? []
        attributedLines = try values.decodeIfPresent([AttributedLine].self, forKey: .attributedLines) ?? []
    }

    static func load(_ name: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: fixtureURL("\(name)-layout.json")))
    }
    func content() -> PageContent {
        func rect(_ values: [Double]) -> CGRect {
            precondition(values.count == 4)
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        return PageContent(number: page, bounds: rect(bounds), lines: lines.map {
            TextLine(text: $0.text, rect: rect($0.rect), fontSize: $0.fontSize, monospaced: $0.monospaced)
        }, graphics: graphics.map(rect), pictures: pictures.map(rect))
    }
}

/// One page's *recognition* as Vision returned it, captured by
/// `tools/probes/capture-ocr-layout-fixture.swift` from a checksum-pinned source.
///
/// A recognition is not a property of the library. Vision returns a different reading of the same
/// page image from one run to the next on one host, from one unchanged binary (#173, #284), so a
/// rule that weighs a reading cannot be gated by re-measuring one: the gate would report the host.
/// It is gated by replaying a capture instead, which is what `#173` already does for the tables a
/// recognition locates. What a test built on this fixture says is what the library does with *this
/// reading*, and nothing about which reading Vision will return next.
struct SourceRecognitionFixture: Decodable {
    struct Line: Decodable {
        var text: String
        var rect: [Double]
        var fontSize: Double
        var monospaced: Bool
        var wraps: Bool?
    }
    var sourceSHA256: String
    var page: Int
    var bounds: [Double]
    var lines: [Line]
    var graphics: [[Double]]

    static func load(_ name: String) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: fixtureURL("\(name)-recognition.json")))
    }

    func reading() -> OCRReader.Result {
        func rect(_ values: [Double]) -> CGRect {
            precondition(values.count == 4)
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        return OCRReader.Result(lines: lines.map {
            TextLine(text: $0.text, rect: rect($0.rect), fontSize: $0.fontSize,
                     monospaced: $0.monospaced, wraps: $0.wraps)
        }, tables: graphics.map(rect))
    }
}
