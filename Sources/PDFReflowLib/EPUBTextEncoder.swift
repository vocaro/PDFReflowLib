import Foundation

// XML 1.0 excludes control characters even when they occur in source PDF text/metadata.
func isXMLCharacter(_ scalar: Unicode.Scalar) -> Bool {
    scalar.value == 9 || scalar.value == 10 || scalar.value == 13 ||
        (scalar.value >= 0x20 && scalar.value <= 0xD7FF) ||
        (scalar.value >= 0xE000 && scalar.value <= 0xFFFD) || scalar.value >= 0x10000
}

func xml(_ string: String) -> String {
    String(String.UnicodeScalarView(string.unicodeScalars.filter(isXMLCharacter)))
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

enum EPUBTextEncoder {
    static func sourcePage(_ page: Int) -> String {
        "<span epub:type=\"pagebreak\" role=\"doc-pagebreak\" id=\"page-\(page)\" aria-label=\"\(page)\"/>"
    }

    static func inline(_ text: InlineText) -> String {
        text.elements.map { element in
            switch element {
            case let .text(text, style):
                var run = xml(text)
                if style.contains(.italic) { run = "<em>\(run)</em>" }
                if style.contains(.bold) { run = "<strong>\(run)</strong>" }
                if style.contains(.superscript) { run = "<sup>\(run)</sup>" }
                else if style.contains(.subscript) { run = "<sub>\(run)</sub>" }
                return run
            case let .sourcePage(page): return sourcePage(page)
            }
        }.joined()
    }

    static func payload(_ block: ReflowBlock, imagePaths: [String: String]) throws -> String {
        switch block.content {
        case let .paragraph(text), let .heading(_, text, _): return inline(text)
        case let .preformatted(text): return inline(text)
        case let .sourcePage(page): return sourcePage(page)
        case let .image(image):
            guard let path = imagePaths[image.assetID] else {
                throw ReflowDocument.ValidationError.missingAsset(image.assetID)
            }
            return "<figure><img src=\"\(xml(path))\" alt=\"\(xml(image.alternativeText))\"/><figcaption>\(xml(image.caption))</figcaption></figure>"
        }
    }
}
