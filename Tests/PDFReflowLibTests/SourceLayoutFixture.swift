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
        /// The tag the pipeline applied to the line, where the page's structure validated
        /// (captured since #89/#90; absent in older fixtures and on untagged lines).
        var structure: TextStructure?
        /// A recognized line's reading direction `[dx, dy]` when it is rotated (captured by
        /// `capture-ocr-layout-fixture` since #122; absent otherwise).
        var readingDirection: [Double]?
    }
    struct AttributedLine: Decodable {
        struct Run: Decodable {
            var text: String
            var fontName: String
            var fontSize: Double
            var baselineOffset: Double
            /// Drawn in a bold font resource PDFKit does not name bold (#125; absent in fixtures
            /// captured before it, and on runs that are not).
            var bold: Bool?
            /// Drawn in an italic text font resource PDFKit does not name italic (#133; absent in
            /// fixtures captured before it, and on runs that are not).
            var italic: Bool?
            /// Drawn in a maths italic font resource (#142; absent in fixtures captured before
            /// it, and on runs that are not).
            var mathItalic: Bool?
        }
        var text: String
        /// The selection's own bounds, captured beside the runs (absent in older fixtures).
        var rect: [Double]?
        var runs: [Run]
        /// `fontWeights: false` replays PDFKit's runs alone, as extraction read them before #125,
        /// #133 and #142 (no resource bold, italic or maths italic).
        func attributedString(fontWeights: Bool = true) -> NSAttributedString {
            let value = NSMutableAttributedString(string: "")
            for run in runs {
                var attributes: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key(kCTBaselineOffsetAttributeName as String): run.baselineOffset,
                ]
                attributes[.font] = pdfKitGated { FixtureFont(name: run.fontName, size: run.fontSize) }
                if fontWeights, run.bold == true { attributes[FontWeightReader.boldAttribute] = true }
                if fontWeights, run.italic == true { attributes[FontWeightReader.italicAttribute] = true }
                if fontWeights, run.mathItalic == true { attributes[FontWeightReader.mathItalicAttribute] = true }
                value.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            return value
        }
    }
    struct Paint: Decodable {
        var rect: [Double]
        var frame: Bool
        /// Image XObject and fill-operator evidence (#117); absent in older fixtures, read as false.
        var image: Bool?
        var filled: Bool?
        /// The paint fills the box of the transparency-group form drawing it (#158); absent in
        /// fixtures captured before it, read as false.
        var grouped: Bool?
    }
    var sourceSHA256: String
    var page: Int
    var bounds: [Double]
    var lines: [Line]
    var graphics: [[Double]]
    /// Unclustered painted footprints with their frame flag; fixtures captured before #54
    /// carry only the clustered `graphics`.
    var paints: [Paint]?
    struct Blank: Decodable {
        var rule: [Double]
        var field: [Double]
    }
    /// A form's ruled blanks (#152); absent in fixtures captured before it and on pages without
    /// form fields.
    var blanks: [Blank]?
    var attributedLines: [AttributedLine]

    static func load(_ name: String) throws -> Self {
        let url = Bundle.module.resourceURL!.appendingPathComponent("fixtures/\(name)-layout.json")
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    /// The page as extraction hands it to layout. With `paints`, tint removal runs as in the
    /// pipeline; `tinted: false` keeps every painted footprint as a crop seed, as before #54.
    /// Extraction ends by spelling ligatures out (#189), which fixtures captured before it do not
    /// record, so each line is spelled out here as extraction would; `spelledOut: false` replays
    /// the lines as captured. A printed blank (#197) is read from the paints as the pipeline reads
    /// it; `fields: false` drops the captured form fields' blanks, as if the form had none.
    func content(tinted: Bool = true, spelledOut: Bool = true, fields: Bool = true) -> PageContent {
        func rect(_ values: [Double]) -> CGRect {
            precondition(values.count == 4)
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        let textLines = lines.map { source -> TextLine in
            var line = TextLine(text: source.text, rect: rect(source.rect), fontSize: source.fontSize,
                                monospaced: source.monospaced)
            line.structure = source.structure
            line.readingDirection = source.readingDirection.map { CGVector(dx: $0[0], dy: $0[1]) }
            if spelledOut { line.spellOutLigatures() }
            return line
        }
        var page = PageContent(number: page, bounds: rect(bounds), lines: textLines, graphics: graphics.map(rect))
        page.blanks = fields ? (blanks ?? []).map { FormBlank(rule: rect($0.rule), field: rect($0.field)) } : []
        if let paints {
            page.blanks += FormBlank.printed(paints: paints.map { rect($0.rect) }, lines: textLines, fields: page.blanks)
        }
        if tinted, let paints {
            // A blank's rules seed no crops, as in the pipeline.
            let drawn = paints.filter { paint in !page.blanks.contains { $0.rule.contains(rect(paint.rect)) } }
            let composed = TintDetector.compose(drawn.map {
                GraphicsReader.Paint(rect: rect($0.rect), frame: $0.frame, image: $0.image ?? false,
                                     filled: $0.filled ?? false, grouped: $0.grouped ?? false) },
                                                lines: textLines, bounds: page.bounds)
            page.graphics = composed.graphics
            page.tints = composed.tints
            page.separators = composed.separators
        }
        return page
    }

    /// The page with each line's native style runs (emphasis, superscripts), as the
    /// converter extracts them; lines without a matching attributed selection stay plain.
    func styledContent(fontWeights: Bool = true, spelledOut: Bool = true, fields: Bool = true) -> PageContent {
        var result = content(spelledOut: spelledOut, fields: fields)
        // Attributed lines hold PDFKit's characters, ligatures included; they are matched and
        // replayed spelled out as the line is.
        func spelled(_ text: String) -> String { spelledOut ? InlineText.spellingOutLigatures(text) : text }
        let attributed = Dictionary(attributedLines.map {
            (spelled($0.text.trimmingCharacters(in: .whitespacesAndNewlines)), $0)
        }, uniquingKeysWith: { first, _ in first })
        result.lines = result.lines.map { line in
            guard let match = attributed[line.text] else { return line }
            let attributedLine = match.attributedString(fontWeights: fontWeights)
            var styled = NativeTextReader.inlineText(from: attributedLine)
            if spelledOut { styled = styled.spellingOutLigatures() }
            guard styled.text == line.text else { return line }
            var copy = TextLine(content: styled, rect: line.rect, fontSize: line.fontSize, monospaced: line.monospaced)
            copy.structure = line.structure
            // A fixture records the size extraction gave the line when it was captured, and its
            // attributed text before extraction trimmed it. Replay from the line's own runs what
            // `textLine` reads there and older fixtures do not record: the bullet-item size and
            // the word space PDFKit kept at the line's end (#180). A fixture captured before
            // either rule then still shows the defect when the rule is stubbed out.
            if !line.monospaced, let size = NativeTextReader.bulletItemBodySize(in: attributedLine) {
                copy.fontSize = size
            }
            copy.trailingSpace = !line.monospaced && match.text.last?.isWhitespace == true
            return copy
        }
        return result
    }
}
