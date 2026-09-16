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

    /// Fragment identifiers of a note and of its first reference. Hrefs are written as
    /// same-document fragments; the writer qualifies those that cross a spine file.
    static func noteID(_ key: NoteKey) -> String { "note-\(key.identifier)" }
    static func referenceID(_ key: NoteKey) -> String { "noteref-\(key.identifier)" }

    private static func styled(_ text: String, _ style: TextStyle) -> String {
        var run = xml(text)
        if style.contains(.italic) { run = "<em>\(run)</em>" }
        if style.contains(.bold) { run = "<strong>\(run)</strong>" }
        if style.contains(.superscript) { run = "<sup>\(run)</sup>" }
        else if style.contains(.subscript) { run = "<sub>\(run)</sub>" }
        return run
    }

    /// `referenceID` names the id a linked marker receives (its first occurrence); nil emits
    /// the link without an id, as later references to the same note do.
    static func inline(_ text: InlineText, referenceID: (NoteKey) -> String? = { _ in nil }) -> String {
        text.elements.map { element in
            switch element {
            case let .text(text, style): return styled(text, style)
            case let .sourcePage(page): return sourcePage(page)
            case let .noteReference(marker, style, key):
                let id = referenceID(key).map { " id=\"\(xml($0))\"" } ?? ""
                return "<sup><a epub:type=\"noteref\" role=\"doc-noteref\"\(id) href=\"#\(noteID(key))\">"
                    + styled(marker, style.subtracting([.superscript, .subscript])) + "</a></sup>"
            }
        }.joined()
    }

    /// A note's text with its printed number wrapped in a return link to `backlink`. The
    /// number is the opening superscript run of a page-bottom note or the `4.` prefix of an
    /// endnote paragraph; a note that opens otherwise gets the link appended instead.
    static func note(_ text: InlineText, number: Int, backlink: String) -> String {
        let anchor = "<a href=\"#\(xml(backlink))\" role=\"doc-backlink\" epub:type=\"backlink\">"
        guard case let .text(value, style)? = text.elements.first else {
            return inline(text) + " \(anchor)\u{21A9}</a>"
        }
        let rest = InlineText(elements: Array(text.elements.dropFirst()))
        if style.contains(.superscript), value.trimmingCharacters(in: .whitespaces) == String(number) {
            return "<sup>\(anchor)\(xml(value))</a></sup>" + inline(rest)
        }
        if !style.contains(.superscript), !style.contains(.subscript),
           let range = value.range(of: "^\\s*\(number)\\.", options: .regularExpression) {
            let prefix = String(value[range]), remainder = String(value[range.upperBound...])
            return anchor + styled(prefix, style) + "</a>" + styled(remainder, style) + inline(rest)
        }
        return inline(text) + " \(anchor)\u{21A9}</a>"
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

    static func payload(_ block: ReflowBlock, imagePaths: [String: String],
                        referenceID: (NoteKey) -> String? = { _ in nil }) throws -> String {
        switch block.content {
        case let .paragraph(text), let .heading(_, text, _): return inline(text, referenceID: referenceID)
        case let .preformatted(text), let .footnote(text): return inline(text, referenceID: referenceID)
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
