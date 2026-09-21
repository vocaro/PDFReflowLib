import Foundation
import PDFKit

/// What a document states about itself in its information dictionary, normalized for XML output.
///
/// Only the title was read before (#253), so a book whose PDF names its author converted to a
/// package that did not. Every value here is untrusted document text on its way into the package
/// document, so it is normalized once, here, rather than at each place that writes it.
///
/// The field names follow the mapping XMP defines from the information dictionary, not the PDF
/// key names: `/Subject` is a prose summary, which XMP maps to `dc:description`, and `/Keywords`
/// is the list of topics, which maps to `dc:subject`. The corpus shows why that mapping is the
/// right one rather than the literal reading of the key names: the NBS paper states its whole
/// 433-character abstract in `/Subject`, which is a description and not a subject heading.
struct SourceMetadata: Sendable, Equatable {
    /// The longest stated value carried. The corpus's longest is that 433-character abstract. A
    /// longer value is dropped rather than truncated: half a sentence misstates what the document
    /// says, where an absent one only omits it.
    static let maximumCharacters = 1_000
    /// Keywords past this count are dropped. The corpus's longest list is five.
    static let maximumKeywords = 64

    var title: String?
    var author: String?
    /// `/Subject`, written as `dc:description`.
    var summary: String?
    /// `/Keywords`, written as one `dc:subject` each.
    var keywords: [String] = []
    /// `/CreationDate`. Not a publication date: see `EPUBWriter.finish`.
    var created: Date?

    init() {}

    init(attributes: [AnyHashable: Any]?) {
        guard let attributes else { return }
        title = Self.stated(attributes[PDFDocumentAttribute.titleAttribute])
        author = Self.stated(attributes[PDFDocumentAttribute.authorAttribute])
        summary = Self.stated(attributes[PDFDocumentAttribute.subjectAttribute])
        keywords = Self.keywords(attributes[PDFDocumentAttribute.keywordsAttribute])
        created = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date
    }

    /// Values that name their own field or state absence. A producer's default is not a statement
    /// about the document, and `<dc:creator>Unknown</dc:creator>` sorts a library worse than no
    /// creator at all. This is a bound on emptiness, not a judgement of quality: terse internal
    /// codes such as the IRS publication's `W:CAR:MP:FP` are what that document says about itself
    /// and are carried through as stated.
    private static let placeholders: Set<String> = [
        "unknown", "unknown author", "no author", "untitled", "no title", "none", "not available",
        "n/a", "na", "null", "nil", "author", "title", "subject", "keywords", "default"
    ]

    /// One stated value, or nil where the document states nothing.
    ///
    /// Characters XML 1.0 cannot carry are removed, every run of whitespace — including the line
    /// breaks a producer wraps an abstract with — collapses to one space, and the result is
    /// trimmed. A value with no letter or digit left states nothing, as does a placeholder.
    static func stated(_ value: Any?) -> String? {
        guard let text = value as? String, text.count <= maximumCharacters * 4 else { return nil }
        let scalars = text.unicodeScalars.filter(isXMLCharacter)
        let collapsed = String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= maximumCharacters,
              collapsed.contains(where: { $0.isLetter || $0.isNumber }),
              !placeholders.contains(collapsed.lowercased()) else { return nil }
        return collapsed
    }

    /// The bound on one page's printed label. A label is what a reader sees printed on the page,
    /// so it is short: the corpus's longest is `cover-108`, nine characters.
    static let maximumLabelCharacters = 32

    /// One page's printed label, or nil where the document states none a reader could use (#248).
    /// The same normalization as any other stated value, under a much tighter bound: a producer
    /// that writes a sentence into a page label is not stating a page number.
    static func pageLabel(_ value: String?) -> String? {
        guard let label = stated(value), label.count <= maximumLabelCharacters else { return nil }
        return label
    }

    /// The stated keywords, in order, without repeats.
    ///
    /// PDFKit hands back an array where it recognizes the separators and a single string where it
    /// does not, so both are accepted and every element is split again on commas and semicolons.
    /// Repeats differing only by case are one keyword; the first spelling is kept.
    static func keywords(_ value: Any?) -> [String] {
        let elements: [String]
        if let array = value as? [Any] {
            elements = array.compactMap { $0 as? String }
        } else if let string = value as? String {
            elements = [string]
        } else {
            return []
        }
        var keywords: [String] = []
        var seen: Set<String> = []
        for element in elements.prefix(maximumKeywords * 4) {
            for part in element.split(whereSeparator: { $0 == "," || $0 == ";" }) {
                guard let keyword = stated(String(part)), seen.insert(keyword.lowercased()).inserted else { continue }
                keywords.append(keyword)
                if keywords.count == maximumKeywords { return keywords }
            }
        }
        return keywords
    }
}
