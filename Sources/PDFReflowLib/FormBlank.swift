import CoreGraphics
import Foundation

/// A ruled space a reader is expected to fill in. GraphicsReader pads the source rule by two
/// points; `field` describes the writing area above it, whether supplied by a widget or inferred
/// from an adjacent printed label (#197, #211).
struct FormBlank: Equatable, Codable {
    var rule: CGRect
    var field: CGRect

    static let text = "____"

    static func under(fields: [CGRect], paints: [CGRect]) -> [FormBlank] {
        fields.compactMap { field in
            guard field.isFinite, !field.isNull, field.width > 0, field.height > 0 else { return nil }
            let rules = paints.filter { paint in
                guard paint.height <= 6, paint.width >= max(12, paint.height * 3) else { return false }
                let across = min(paint.maxX, field.maxX) - max(paint.minX, field.minX)
                return across >= paint.width * 0.8
                    && paint.midY >= field.minY - 3 && paint.midY <= field.minY + field.height * 0.5
            }
            return rules.isEmpty ? nil : FormBlank(rule: union(rules), field: field)
        }
    }

    /// A blank printed without a widget is a long, isolated baseline rule beside a label or
    /// sentence. A column separator, underline, grid edge or value printed over it is excluded.
    static func printed(paints: [CGRect], lines: [TextLine], fields: [FormBlank] = []) -> [FormBlank] {
        func isRule(_ paint: CGRect) -> Bool {
            paint.isFinite && paint.height <= 6 && paint.width >= max(12, paint.height * 3)
        }
        var rules: [CGRect] = []
        for paint in paints.filter(isRule).sorted(by: { ($0.midY, $0.minX) < ($1.midY, $1.minX) })
            where !fields.contains(where: { $0.rule.contains(paint) }) {
            if let last = rules.last, abs(last.midY - paint.midY) <= 1, paint.minX <= last.maxX + 1 {
                rules[rules.count - 1] = last.union(paint)
            } else {
                rules.append(paint)
            }
        }
        let text = lines.filter { line in
            line.turn == .upright && !line.monospaced && !line.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return rules.compactMap { rule in
            let drawn = rule.insetBy(dx: 2, dy: 0)
            guard drawn.width > 0 else { return nil }
            let row = text.filter { line in
                rule.midY >= line.rect.minY - line.fontSize * 0.5
                    && rule.midY <= line.rect.minY + line.rect.height / 3
            }
            let left = row.filter { $0.rect.maxX <= drawn.minX + 2 && drawn.minX - $0.rect.maxX <= $0.fontSize * 10 }
                .max { $0.rect.maxX < $1.rect.maxX }
            let right = row.filter { $0.rect.minX >= drawn.maxX - 2 && $0.rect.minX - drawn.maxX <= $0.fontSize }
                .min { $0.rect.minX < $1.rect.minX }
            guard let anchor = left ?? right, anchor.rect.maxY > rule.midY + 1,
                  drawn.width >= anchor.fontSize * 3 else { return nil }
            let outline = rule.insetBy(dx: -1, dy: -1)
            guard !paints.contains(where: { $0.isFinite && $0.intersects(outline) && !outline.contains($0) }) else {
                return nil
            }
            let em = anchor.fontSize
            guard !text.contains(where: { line in
                !row.contains(line) && abs(line.rect.midY - rule.midY) <= em * 6
                    && line.rect.minX >= drawn.minX - em * 0.5 && line.rect.minX < drawn.maxX
                    && abs(line.rect.maxX - drawn.maxX) <= max(em * 2, drawn.width * 0.05)
            }) else { return nil }
            let field = CGRect(x: drawn.minX, y: rule.minY, width: drawn.width, height: anchor.rect.maxY - rule.minY)
            let over = CGRect(x: drawn.minX + 1, y: rule.midY, width: drawn.width - 2, height: anchor.rect.maxY - 1 - rule.midY)
            guard over.width > 0, over.height > 0,
                  !text.contains(where: { $0.rect.intersects(over) }) else { return nil }
            return FormBlank(rule: rule, field: field)
        }
    }

    func sharesRow(with row: CGRect) -> Bool {
        let overlap = min(field.maxY, row.maxY) - max(field.minY, row.minY)
        return field.height <= row.height * 2 && overlap >= min(field.height, row.height) * 0.5
    }
}
