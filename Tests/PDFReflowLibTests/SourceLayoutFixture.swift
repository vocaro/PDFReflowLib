import Foundation
import CoreText
#if os(macOS)
import AppKit
private typealias FixtureFont = NSFont
#else
import UIKit
private typealias FixtureFont = UIFont
#endif
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
                attributes[.font] = pdfKitGated { FixtureFont(name: run.fontName, size: run.fontSize) }
                value.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            return value
        }
    }
    var sourceSHA256: String
    var page: Int
    var bounds: [Double]
    var lines: [Line]
    var graphics: [[Double]]
    var attributedLines: [AttributedLine]

    static func load(_ name: String) throws -> Self {
        let url = Bundle.module.resourceURL!.appendingPathComponent("fixtures/\(name)-layout.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
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
