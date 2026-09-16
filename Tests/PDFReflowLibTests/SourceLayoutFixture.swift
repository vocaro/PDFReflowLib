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
        /// The selection's own bounds, captured beside the runs (absent in older fixtures).
        var rect: [Double]?
        var runs: [Run]
        func attributedString() -> NSAttributedString {
            let value = NSMutableAttributedString(string: "")
            for run in runs {
                var attributes: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): run.baselineOffset,
                ]
                attributes[.font] = FixtureFont(name: run.fontName, size: run.fontSize)
                value.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            return value
        }
    }
    struct Paint: Decodable {
        var rect: [Double]
        var frame: Bool
    }
    var sourceSHA256: String
    var page: Int
    var bounds: [Double]
    var lines: [Line]
    var graphics: [[Double]]
    /// Unclustered painted footprints with their frame flag; fixtures captured before #54
    /// carry only the clustered `graphics`.
    var paints: [Paint]?
    var attributedLines: [AttributedLine]

    static func load(_ name: String) throws -> Self {
        let url = Bundle.module.resourceURL!.appendingPathComponent("fixtures/\(name)-layout.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    /// The page as extraction hands it to layout. With `paints`, tint removal runs as in the
    /// pipeline; `tinted: false` keeps every painted footprint as a crop seed, as before #54.
    func content(tinted: Bool = true) -> PageContent {
        func rect(_ values: [Double]) -> CGRect {
            precondition(values.count == 4)
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        let textLines = lines.map {
            TextLine(text: $0.text, rect: rect($0.rect), fontSize: $0.fontSize, monospaced: $0.monospaced)
        }
        var page = PageContent(number: page, bounds: rect(bounds), lines: textLines, graphics: graphics.map(rect))
        if tinted, let paints {
            let composed = TintDetector.compose(paints.map { GraphicsReader.Paint(rect: rect($0.rect), frame: $0.frame) },
                                                lines: textLines, bounds: page.bounds)
            page.graphics = composed.graphics
            page.tints = composed.tints
            page.separators = composed.separators
        }
        return page
    }

    /// The page with each line's native style runs (emphasis, superscripts), as the
    /// converter extracts them; lines without a matching attributed selection stay plain.
    func styledContent() -> PageContent {
        var result = content()
        let attributed = Dictionary(attributedLines.map {
            ($0.text.trimmingCharacters(in: .whitespacesAndNewlines), $0)
        }, uniquingKeysWith: { first, _ in first })
        result.lines = result.lines.map { line in
            guard let match = attributed[line.text] else { return line }
            let styled = NativeTextReader.inlineText(from: match.attributedString())
            guard styled.text == line.text else { return line }
            return TextLine(content: styled, rect: line.rect, fontSize: line.fontSize, monospaced: line.monospaced)
        }
        return result
    }
}
