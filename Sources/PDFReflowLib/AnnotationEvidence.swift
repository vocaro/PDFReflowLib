import CoreGraphics
import Foundation
import PDFKit

/// Decides which unconverted annotations change what a reader sees, so only those earn a
/// source-page reference image (#151). Converted links are handled before this judgment.
///
/// Before, any annotation added a reference. On the English corpus that was 1,857 FAA links, 257
/// Fed links, 157 of 161 9/11 links, 75 Replay Clocks links, 55 USDA magazine links and 10 NASA
/// Word-paper links, none of which draws anything, and 77 unfilled US Courts form widgets. The judgment:
///
/// - **Form fields** (widgets) are read for what they hold. A push button (Print, Reset) is a
///   viewer control, not content. An unchecked box, and a text or choice field that is empty or
///   holds only text the page already prints beneath it (the form's `__________ Division`), show
///   nothing beyond the printed page. A checked box, a radio button that is on, and a field whose
///   value is not printed beneath it show content the reflow does not carry. Any other widget (a
///   signature seal) is judged by its drawing, as below.
/// - **Every other annotation** (links, markup, stamps, ink, notes) is judged by its drawing, the
///   way `PageRasterizer` draws it into the page image: first alone, over transparency, within its
///   bounds; one that inks nothing draws nothing. One that inks is drawn again over the page's
///   own rendering of that area, and shows only if it changes a pixel by more than
///   `pixelTolerance` levels: a white highlight, multiplied over the page, changes nothing (FAA
///   page 362). A link with a one-point border and no color (9/11 pages 570, 571 and 575) shows.
///
/// A hidden annotation (`shouldDisplay` false, or the Hidden or NoView flag, which PDFKit's drawing
/// does not honor) shows nothing in a PDF viewer and is ignored.
enum AnnotationEvidence {
    /// The channel difference, 0–255, below which an annotation's drawing is not a visible change.
    static let pixelTolerance = 2
    /// Box glyphs a checkbox widget sits on are rewritten as these (`☐`, `☒`).
    static let uncheckedBox = "\u{2610}", checkedBox = "\u{2612}"

    /// A checkbox or radio widget over a printed glyph: its bounds, whether it is on, the glyph.
    struct Box: Equatable {
        var bounds: CGRect
        var on: Bool
        var glyph: String
    }

    struct Judgment: Equatable {
        /// Annotations whose drawing changes the page as a reader sees it.
        var visible = 0
        /// Links, and form fields, that draw nothing a reader needs; their interaction is lost.
        var links = 0
        var formFields = 0
        /// Other annotations that draw nothing (a popup, a white highlight).
        var invisible = 0
        var boxes: [Box] = []

        var isEmpty: Bool { visible + links + formFields + invisible == 0 }
    }

    static func judge(_ annotations: [PDFAnnotation], on page: PDFPage, bounds: CGRect) throws -> Judgment {
        var judgment = Judgment()
        for annotation in annotations {
            try Task.checkCancellation()
            guard annotation.shouldDisplay, !isHidden(annotation) else { continue }
            if annotation.type == "Widget" {
                switch try widgetShows(annotation, on: page, judgment: &judgment) {
                case true?: judgment.visible += 1; continue
                case false?: judgment.formFields += 1; continue
                case nil: break
                }
                if try changesRendering(annotation, on: page, bounds: bounds) { judgment.visible += 1 }
                else { judgment.formFields += 1 }
                continue
            }
            if try changesRendering(annotation, on: page, bounds: bounds) {
                judgment.visible += 1
            } else if annotation.type == "Link" {
                judgment.links += 1
            } else {
                judgment.invisible += 1
            }
        }
        return judgment
    }

    /// A visible text or choice widget whose lower edge overlays a printed writing rule.
    static func blanks(on page: PDFPage, paints: [CGRect]) -> [FormBlank] {
        let fields = page.annotations.filter { annotation in
            annotation.type == "Widget" && annotation.shouldDisplay && !isHidden(annotation)
                && (annotation.widgetFieldType == .text || annotation.widgetFieldType == .choice)
        }.map(\.bounds)
        return FormBlank.under(fields: fields, paints: paints)
    }

    /// The annotation flags Hidden (bit 2) and NoView (bit 6).
    private static func isHidden(_ annotation: PDFAnnotation) -> Bool {
        guard let flags = annotation.value(forAnnotationKey: .flags) as? NSNumber else { return false }
        return flags.intValue & (2 | 32) != 0
    }

    /// Whether a form widget shows content, from what it holds; nil when only its drawing can tell.
    private static func widgetShows(_ widget: PDFAnnotation, on page: PDFPage, judgment: inout Judgment) throws -> Bool? {
        switch widget.widgetFieldType {
        case .button:
            switch widget.widgetControlType {
            case .pushButtonControl:
                return false
            case .checkBoxControl, .radioButtonControl:
                let on = widget.buttonWidgetState == .onState
                let under = try printedText(under: widget.bounds, on: page)
                if under.isEmpty {
                    // A widget can be the page's only drawing of its box (#170). Give that
                    // state a text mark even where there is no glyph to replace.
                    judgment.boxes.append(Box(bounds: widget.bounds, on: on, glyph: ""))
                } else if under.count == 1, let scalar = under.unicodeScalars.first,
                          !CharacterSet.alphanumerics.contains(scalar) {
                    judgment.boxes.append(Box(bounds: widget.bounds, on: on, glyph: under))
                }
                return on
            default:
                return nil
            }
        case .text, .choice:
            let value = squeezed(widget.widgetStringValue ?? "")
            if value.isEmpty { return false }
            return squeezed(try printedText(under: widget.bounds, on: page)) != value
        default:
            return nil
        }
    }

    private static func squeezed(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(Character.init))
    }

    private static func printedText(under rect: CGRect, on page: PDFPage) throws -> String {
        try NativeTextReader.withExtractionLock {
            (page.selection(for: rect)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Whether drawing the annotation as the page image draws it changes any pixel of the page.
    static func changesRendering(_ annotation: PDFAnnotation, on page: PDFPage, bounds: CGRect) throws -> Bool {
        // A stroke may extend past the rectangle; a 2-point margin keeps its outer half.
        let area = annotation.bounds.insetBy(dx: -2, dy: -2).intersection(bounds).integral
        guard !area.isNull, area.width > 0, area.height > 0 else { return false }
        let scale = min(1, sqrt(4_000_000 / (area.width * area.height)))
        func render(page drawsPage: Bool, annotation drawsAnnotation: Bool) -> [UInt8]? {
            let width = max(1, Int((area.width * scale).rounded(.up)))
            let height = max(1, Int((area.height * scale).rounded(.up)))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            if drawsPage {
                context.setFillColor(gray: 1, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -area.minX, y: -area.minY)
            if drawsPage, let reference = page.pageRef {
                context.saveGState()
                context.clip(to: area)
                context.drawPDFPage(reference)
                context.restoreGState()
            }
            if drawsAnnotation {
                // As `PageRasterizer`: undo PDFKit's own crop/rotation mapping.
                context.saveGState()
                context.concatenate(page.transform(for: .cropBox).inverted())
                annotation.draw(with: .cropBox, in: context)
                context.restoreGState()
            }
            guard let data = context.data else { return nil }
            return Array(UnsafeBufferPointer(start: data.bindMemory(to: UInt8.self, capacity: width * height * 4),
                                             count: width * height * 4))
        }
        return try autoreleasepool {
            guard let alone = render(page: false, annotation: true) else { return true }
            guard stride(from: 3, to: alone.count, by: 4).contains(where: { alone[$0] > 0 }) else { return false }
            try Task.checkCancellation()
            guard let plain = render(page: true, annotation: false),
                  let drawn = render(page: true, annotation: true) else { return true }
            return zip(plain, drawn).contains { abs(Int($0) - Int($1)) > pixelTolerance }
        }
    }

    /// Rewrites the box glyphs checkbox widgets sit on (a `WP-IconicSymbolsA` box whose ToUnicode
    /// map reads it as `’`, US Courts form pages 1 and 3) as `☐` or `☒`. A line is rewritten only
    /// when every occurrence of the glyph in it lies under a checkbox, so an apostrophe in the
    /// same line keeps the line as it was.
    static func markBoxes(_ boxes: [Box], in lines: inout [TextLine]) {
        guard !boxes.isEmpty else { return }
        for box in boxes where box.glyph.isEmpty {
            let text = box.on ? checkedBox : uncheckedBox
            lines.append(TextLine(text: text, rect: box.bounds,
                                  fontSize: min(12, max(6, box.bounds.height * 0.8)), wraps: false))
        }
        for index in lines.indices {
            let line = lines[index]
            guard line.turn == .upright else { continue }
            let onLine = boxes.filter {
                $0.bounds.midY >= line.rect.minY && $0.bounds.midY <= line.rect.maxY
                    && $0.bounds.maxX >= line.rect.minX && $0.bounds.minX <= line.rect.maxX
            }.sorted { $0.bounds.minX < $1.bounds.minX }
            guard let glyph = onLine.first?.glyph, !glyph.isEmpty,
                  onLine.allSatisfy({ $0.glyph == glyph }),
                  line.text.components(separatedBy: glyph).count - 1 == onLine.count else { continue }
            var remaining = onLine.map { $0.on ? checkedBox : uncheckedBox }[...]
            var content = line.content
            for element in content.elements.indices {
                guard case let .text(value, style) = content.elements[element], value.contains(glyph) else { continue }
                var rewritten = ""
                for character in value {
                    if String(character) == glyph, let mark = remaining.popFirst() { rewritten += mark }
                    else { rewritten.append(character) }
                }
                content.elements[element] = .text(rewritten, style)
            }
            var replacement = TextLine(content: content, rect: line.rect, fontSize: line.fontSize,
                                       monospaced: line.monospaced, wraps: line.wraps, turn: line.turn)
            replacement.readingRect = line.readingRect
            replacement.structure = line.structure
            lines[index] = replacement
        }
    }
}
