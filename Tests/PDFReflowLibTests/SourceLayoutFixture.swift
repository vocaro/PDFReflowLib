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
    /// Styled runs, absent from the earliest captures; those fixtures serve geometry tests only.
    var attributedLines: [AttributedLine]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, sourceSHA256, page, bounds, lines, graphics, attributedLines
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        sourceSHA256 = try values.decode(String.self, forKey: .sourceSHA256)
        page = try values.decode(Int.self, forKey: .page)
        bounds = try values.decode([Double].self, forKey: .bounds)
        lines = try values.decode([Line].self, forKey: .lines)
        graphics = try values.decode([[Double]].self, forKey: .graphics)
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
        }, graphics: graphics.map(rect))
    }
}
