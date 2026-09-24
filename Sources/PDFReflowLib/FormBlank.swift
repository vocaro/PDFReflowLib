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
    static func printed(paints: [CGRect], lines: [TextLine], fields: [FormBlank] = [],
                        pageBounds: CGRect? = nil,
                        emptyRuleInterior: ((CGRect) -> Bool)? = nil) -> [FormBlank] {
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
        let labeled = rules.compactMap { rule -> FormBlank? in
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
            // PDFKit sometimes joins a trailing period or comma to the left words across the
            // entire empty rule after annotations are removed. Its selection over the middle
            // of the rule must still be empty before this is treated as a writing space.
            let spanning = row.first { line in
                let em = line.fontSize
                let interior = CGRect(x: drawn.minX + em, y: line.rect.minY,
                                      width: drawn.width - em * 2, height: line.rect.height)
                return interior.width > 0 && line.rect.minX < drawn.minX
                    && line.rect.maxX > drawn.maxX && line.text.contains("(")
                    && line.text.contains(")") && ",.;:)".contains(line.text.last ?? " ")
                    && emptyRuleInterior?(interior) == true
            }
            guard let anchor = left ?? right ?? spanning, anchor.rect.maxY > rule.midY + 1,
                  drawn.width >= anchor.fontSize * 3 else { return nil }
            let outline = rule.insetBy(dx: -1, dy: -1)
            guard !paints.contains(where: { $0.isFinite && $0.intersects(outline) && !outline.contains($0) }) else {
                return nil
            }
            let em = anchor.fontSize
            // Parenthesized prompts may have the sentence on the next row ending at this
            // rule's right edge (the US Courts corporation fields do). That is not a table
            // value printed in this blank.
            let inlinePrompt = spanning != nil || (anchor.text.contains("(") && anchor.text.contains(")")
                && right?.text.allSatisfy({ !$0.isLetter && !$0.isNumber }) == true)
            guard inlinePrompt || !text.contains(where: { line in
                !row.contains(line) && line.text.contains(where: { $0.isLetter || $0.isNumber })
                    && abs(line.rect.midY - rule.midY) <= em * 6
                    && line.rect.minX >= drawn.minX - em * 0.5 && line.rect.minX < drawn.maxX
                    && abs(line.rect.maxX - drawn.maxX) <= max(em * 2, drawn.width * 0.05)
            }) else { return nil }
            let field = CGRect(x: drawn.minX, y: rule.minY, width: drawn.width, height: anchor.rect.maxY - rule.minY)
            let over = CGRect(x: drawn.minX + 1, y: rule.midY, width: drawn.width - 2, height: anchor.rect.maxY - 1 - rule.midY)
            guard over.width > 0, over.height > 0,
                  !text.contains(where: { $0 != spanning && $0.rect.intersects(over) }) else { return nil }
            return FormBlank(rule: rule, field: field)
        }
        // A long closing rule below a form prompt is the bottom of a writing area even when
        // the PDF has no widget. Require several independently labeled rows on this same page
        // before interpreting unlabelled rules this way (#211).
        guard let pageBounds, labeled.count >= 3 else { return labeled }
        let body = max(4, text.map(\.fontSize).sorted()[text.count / 2])
        let areas = rules.compactMap { rule -> FormBlank? in
            guard !labeled.contains(where: { $0.rule == rule }),
                  rule.width >= pageBounds.width * 0.6,
                  rule.minX <= pageBounds.minX + pageBounds.width * 0.25,
                  rule.height <= 6 else { return nil }
            let outline = rule.insetBy(dx: -1, dy: -1)
            guard !paints.contains(where: { $0.isFinite && $0.intersects(outline) && !outline.contains($0) })
            else { return nil }
            let above = text.filter { line in
                line.rect.minY > rule.maxY + body * 2.5
                    && line.rect.minY < rule.maxY + body * 10
                    && line.rect.maxX > rule.minX && line.rect.minX < rule.maxX
                    && line.text.contains(where: { $0.isLetter })
            }.min { $0.rect.minY < $1.rect.minY }
            guard let above else { return nil }
            let field = CGRect(x: rule.minX + 2, y: rule.minY,
                               width: rule.width - 4, height: above.rect.minY - rule.minY)
            guard field.height >= body * 3,
                  !text.contains(where: { $0.rect.intersects(field.insetBy(dx: 1, dy: 2)) }),
                  !rules.contains(where: { $0 != rule && $0.intersects(field.insetBy(dx: 0, dy: 2)) })
            else { return nil }
            return FormBlank(rule: rule, field: field)
        }
        return labeled + areas
    }

    func sharesRow(with row: CGRect) -> Bool {
        let overlap = min(field.maxY, row.maxY) - max(field.minY, row.minY)
        return field.height <= row.height * 2 && overlap >= min(field.height, row.height) * 0.5
    }
}
