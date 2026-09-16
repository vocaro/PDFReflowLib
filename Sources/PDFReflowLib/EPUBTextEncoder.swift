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

    /// Header rows form `thead`; a cell spanning several columns carries `colspan`.
    static func table(_ table: ReflowBlock.Table) -> String {
        func row(_ row: ReflowBlock.Table.Row) -> String {
            let tag = row.header ? "th" : "td"
            let cells = row.cells.map { cell -> String in
                let attribute = cell.span > 1 ? " colspan=\"\(cell.span)\"" : ""
                return "<\(tag)\(attribute)>\(inline(cell.text))</\(tag)>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }
        let headers = table.rows.prefix(while: \.header)
        let body = table.rows.dropFirst(headers.count)
        var markup = "<table>"
        if !headers.isEmpty { markup += "<thead>\(headers.map(row).joined())</thead>" }
        if !body.isEmpty { markup += "<tbody>\(body.map(row).joined())</tbody>" }
        return markup + "</table>"
    }

    static func payload(_ block: ReflowBlock, imagePaths: [String: String]) throws -> String {
        switch block.content {
        case let .paragraph(text), let .heading(_, text, _): return inline(text)
        case let .preformatted(text), let .footnote(text): return inline(text)
        case let .table(table): return Self.table(table)
        case let .sourcePage(page): return sourcePage(page)
        case let .image(image):
            guard let path = imagePaths[image.assetID] else {
                throw ReflowDocument.ValidationError.missingAsset(image.assetID)
            }
            return "<figure><img src=\"\(xml(path))\" alt=\"\(xml(image.alternativeText))\"/><figcaption>\(xml(image.caption))</figcaption></figure>"
        }
    }
}
