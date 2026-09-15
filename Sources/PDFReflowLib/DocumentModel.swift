import CoreGraphics
import Foundation

// All geometry is in unrotated PDF page space (bottom-left origin). OCR is mapped back here.
struct TextLine {
    let content: InlineText
    // Layout repeatedly inspects plain text. Cache it once; immutable content prevents drift.
    let text: String
    var rect: CGRect
    var fontSize: CGFloat
    var monospaced = false
    var wraps: Bool?
    // Reading order may use the body line beside a drop cap. Ink bounds remain in rect.
    var readingRect: CGRect?

    init(text: String, rect: CGRect, fontSize: CGFloat, monospaced: Bool = false, wraps: Bool? = nil) {
        self.init(content: InlineText(text), rect: rect, fontSize: fontSize, monospaced: monospaced, wraps: wraps)
    }

    init(content: InlineText, rect: CGRect, fontSize: CGFloat, monospaced: Bool = false, wraps: Bool? = nil) {
        self.content = content
        self.text = content.text
        self.rect = rect
        self.fontSize = fontSize
        self.monospaced = monospaced
        self.wraps = wraps
    }
}

struct PageContent {
    var number: Int
    var bounds: CGRect
    var lines: [TextLine]
    var graphics: [CGRect]
    var requiresPageImage = false
    var recognized = false
    var hasSyntheticTextStyle = false
    var preservePageReference = false
}

func union(_ rects: [CGRect]) -> CGRect {
    rects.reduce(CGRect.null) { $0.union($1) }
}

func clusters(_ rects: [CGRect], distance: CGFloat) -> [CGRect] {
    var result: [CGRect] = []
    for rect in rects where !rect.isNull && rect.isFinite {
        var merged = rect
        var previousCount = -1
        while previousCount != result.count {
            previousCount = result.count
            result.removeAll { existing in
                if existing.insetBy(dx: -distance, dy: -distance).intersects(merged) {
                    merged = merged.union(existing)
                    return true
                }
                return false
            }
        }
        result.append(merged)
    }
    return result
}

extension CGRect {
    var isFinite: Bool {
        origin.x.isFinite && origin.y.isFinite && width.isFinite && height.isFinite
    }
}
