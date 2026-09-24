import CoreGraphics
import Foundation

/// Extends a fraction crop leftward when the source prints the beginning of its numbered
/// expression as text immediately beside the crop. Keeping the two pieces in one region
/// preserves the exercise number and the complete expression together when the math reader
/// cannot prove the entire row (#29, Wallace page 16).
enum MathExerciseRegionJoin {
    static func joined(_ regions: [CGRect], lines: [TextLine], body: CGFloat) -> [CGRect] {
        var result = regions
        for line in lines where danglingNumberedPrefix(line.text) {
            let candidates = result.indices.filter { index in
                let region = result[index]
                return !region.contains(line.rect)
                    && region.minX >= line.rect.maxX - 1
                    && region.minX <= line.rect.maxX + body * 0.5
                    && abs(region.midY - line.rect.midY) <= body * 0.6
            }
            guard candidates.count == 1 else { continue }
            let index = candidates[0]
            let merged = result[index].union(line.rect)
            // A neighbouring exercise, instruction or heading must never be absorbed merely
            // because it lies near the prefix's fragment.
            guard !lines.contains(where: { other in
                other != line && !result[index].intersects(other.rect)
                    && merged.intersects(other.rect)
            }) else { continue }
            result[index] = merged
        }
        return result
    }

    private static func danglingNumberedPrefix(_ text: String) -> Bool {
        guard text.range(of: #"^\d{1,3}\)\s*"#, options: .regularExpression) != nil,
              text.trimmingCharacters(in: .whitespaces).hasSuffix("−")
                || text.trimmingCharacters(in: .whitespaces).hasSuffix("-") else { return false }
        // The exercise label contributes one closing parenthesis of its own.
        return text.count(where: { $0 == "(" }) >= text.count(where: { $0 == ")" })
    }
}
