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

    /// The elements a style writes, outermost first. `<strong>` is bold and `<em>` is emphasis
    /// italic; `<i>` is a maths variable's slope (#142), which is a font's notation rather than
    /// the stress `<em>` states, and which assistive reading therefore should not voice. `<var>`
    /// was refused: it asserts a named variable of a program or an expression, which a maths
    /// italic font alone does not evidence.
    private static let tags: [(trait: TextStyle, tag: String)] = [
        (.superscript, "sup"), (.subscript, "sub"), (.bold, "strong"), (.italic, "em"), (.mathItalic, "i"),
    ]

    /// A run raised and lowered at once is raised: `sub` precedes `sup` in `tags`, so without
    /// this the two would nest instead.
    private static func resolved(_ style: TextStyle) -> TextStyle {
        style.contains(.superscript) ? style.subtracting(.subscript) : style
    }

    /// Runs as nested elements, each element spanning every adjacent run that carries its style
    /// (#142). Adjacent bold and bold-italic runs are one `<strong>` holding an `<em>`
    /// (`<strong><em>Demand</em> Shocks</strong>`, Fed page 30) rather than two `<strong>`s.
    /// Styles nest in `tags` order, so one run's markup is unchanged.
    private static func nested(_ runs: ArraySlice<(text: String, style: TextStyle)>, depth: Int = 0) -> String {
        guard depth < tags.count else { return runs.map { xml($0.text) }.joined() }
        let (trait, tag) = tags[depth]
        var markup = "", index = runs.startIndex
        while index < runs.endIndex {
            let inside = runs[index].style.contains(trait)
            var end = index
            while end < runs.endIndex, runs[end].style.contains(trait) == inside { end += 1 }
            let group = runs[index..<end].map { (text: $0.text, style: $0.style.subtracting(trait)) }
            let body = nested(group[...], depth: depth + 1)
            markup += inside ? "<\(tag)>\(body)</\(tag)>" : body
            index = end
        }
        return markup
    }

    private static func styled(_ text: String, _ style: TextStyle) -> String {
        nested([(text: text, style: resolved(style))][...])
    }

    /// Emphasis a joining space takes from the runs it separates. A space is invisible in each,
    /// so adopting them only removes an element boundary; a raised or lowered space would move.
    private static let joinable: TextStyle = [.bold, .italic, .mathItalic]

    /// Whether `outer` holds a style that nests outside one `inner` holds. A space that gains
    /// bold between two raised bold runs is still written apart, inside a `<strong>` of its own,
    /// because `<sup>` encloses `<strong>`; there is nothing to join, so it gains nothing.
    private static func encloses(_ outer: TextStyle, _ inner: TextStyle) -> Bool {
        guard let first = tags.firstIndex(where: { outer.contains($0.trait) }),
              let last = tags.lastIndex(where: { inner.contains($0.trait) }) else { return false }
        return first < last
    }

    /// Adjacent text runs of one style as one run. PDFKit splits a line into runs wherever any
    /// attribute changes (kerning, a font resource), and lines join run by run, so equal styles
    /// would otherwise be emitted as separate elements (`<strong>F</strong><strong>AA</strong>`, #133).
    ///
    /// A line join contributes a space of its own, which carries no style and so split the runs
    /// either side of it (arXiv page 4's `<strong>=15, and the</strong> <strong>shift…</strong>`,
    /// #142). A run of whitespace between two text runs first takes the emphasis both of them
    /// carry, so the text either side of it is one element.
    static func coalesced(_ elements: [InlineText.Element]) -> [InlineText.Element] {
        var elements = elements
        for index in elements.indices.dropFirst().dropLast() {
            guard case let .text(value, style) = elements[index], !value.isEmpty,
                  value.allSatisfy(\.isWhitespace),
                  case let .text(_, before) = elements[index - 1],
                  case let .text(_, after) = elements[index + 1] else { continue }
            let shared = before.intersection(after).intersection(joinable)
            let absent = before.union(after).subtracting(style.union(shared))
            guard !shared.subtracting(style).isEmpty, !encloses(absent, shared.subtracting(style)) else { continue }
            elements[index] = .text(value, style.union(shared))
        }
        var result: [InlineText.Element] = []
        result.reserveCapacity(elements.count)
        for element in elements {
            if case let .text(value, style) = element, case let .text(previous, previousStyle)? = result.last,
               style == previousStyle {
                result[result.count - 1] = .text(previous + value, style)
            } else {
                result.append(element)
            }
        }
        return result
    }

    /// A run of adjacent text elements is written as one nest of elements, so a page boundary or
    /// a note reference — each of which carries its own element — ends that run and starts
    /// another. `referenceID` names the id a linked marker receives (its first occurrence); nil
    /// emits the link without an id, as later references to the same note do.
    static func inline(_ text: InlineText, referenceID: (NoteKey) -> String? = { _ in nil }) -> String {
        var markup = "", runs: [(text: String, style: TextStyle)] = []
        func flush() {
            if !runs.isEmpty { markup += nested(runs[...]) }
            runs.removeAll(keepingCapacity: true)
        }
        for element in coalesced(text.elements) {
            switch element {
            case let .text(text, style): runs.append((text: text, style: resolved(style)))
            case let .sourcePage(page):
                flush()
                markup += sourcePage(page)
            case let .noteReference(marker, style, key):
                flush()
                let id = referenceID(key).map { " id=\"\(xml($0))\"" } ?? ""
                markup += "<sup><a epub:type=\"noteref\" role=\"doc-noteref\"\(id) href=\"#\(noteID(key))\">"
                    + styled(marker, style.subtracting([.superscript, .subscript])) + "</a></sup>"
            }
        }
        flush()
        return markup
    }

    /// A note's text with its printed number wrapped in a return link to `backlink`. The
    /// number is the opening superscript run of a page-bottom note or the `4.` prefix of an
    /// endnote paragraph; a note that opens otherwise gets the link appended instead.
    static func note(_ text: InlineText, number: Int, backlink: String) -> String {
        let anchor = "<a href=\"#\(xml(backlink))\" role=\"doc-backlink\" epub:type=\"backlink\">"
        let text = InlineText(elements: coalesced(text.elements))
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
            // The text after the number is written with the rest of the note, so a style it
            // shares with what follows is one element (#142).
            var tail = rest
            if !remainder.isEmpty { tail.elements.insert(.text(remainder, style), at: 0) }
            return anchor + styled(prefix, style) + "</a>" + inline(tail)
        }
        return inline(text) + " \(anchor)\u{21A9}</a>"
    }

    /// Header rows form `thead`; a cell spanning several columns carries `colspan`. A body cell
    /// that names its row is `th scope="row"`. A section row, one header cell spanning every
    /// column (#124), names the rows beneath it up to the next section: it opens its own `tbody`
    /// and is `th scope="rowgroup"`. A caption's title and description are paragraphs of the
    /// table's `caption`.
    static func table(_ table: ReflowBlock.Table) -> String {
        func isSection(_ row: ReflowBlock.Table.Row) -> Bool {
            !row.header && row.cells.count == 1 && row.cells[0].header && row.cells[0].span == table.columns
        }
        func row(_ row: ReflowBlock.Table.Row) -> String {
            let cells = row.cells.map { cell -> String in
                let tag = row.header || cell.header ? "th" : "td"
                var attribute = cell.span > 1 ? " colspan=\"\(cell.span)\"" : ""
                if cell.header && !row.header { attribute += isSection(row) ? " scope=\"rowgroup\"" : " scope=\"row\"" }
                return "<\(tag)\(attribute)>\(inline(cell.text))</\(tag)>"
            }.joined()
            return "<tr>\(cells)</tr>"
        }
        let headers = table.rows.prefix(while: \.header)
        let body = table.rows.dropFirst(headers.count)
        var groups: [[ReflowBlock.Table.Row]] = []
        for item in body {
            if groups.isEmpty || isSection(item) && !groups[groups.count - 1].isEmpty { groups.append([]) }
            groups[groups.count - 1].append(item)
        }
        var markup = "<table>"
        if !table.caption.isEmpty {
            markup += "<caption>" + table.caption.map { "<p>\(inline($0))</p>" }.joined() + "</caption>"
        }
        if !headers.isEmpty { markup += "<thead>\(headers.map(row).joined())</thead>" }
        for group in groups { markup += "<tbody>\(group.map(row).joined())</tbody>" }
        return markup + "</table>"
    }

    static func payload(_ block: ReflowBlock, imagePaths: [String: String],
                        referenceID: (NoteKey) -> String? = { _ in nil }) throws -> String {
        switch block.content {
        case let .paragraph(text), let .heading(_, text, _): return inline(text, referenceID: referenceID)
        case let .preformatted(text), let .footnote(text): return inline(text, referenceID: referenceID)
        case let .listItem(item): return inline(item.text, referenceID: referenceID)
        case let .table(table): return Self.table(table)
        case let .sourcePage(page): return sourcePage(page)
        case let .image(image) where !image.math.isEmpty:
            return try image.math.map { try math($0, imagePaths: imagePaths) }.joined(separator: "\n")
        case let .image(image):
            guard let path = imagePaths[image.assetID] else {
                throw ReflowDocument.ValidationError.missingAsset(image.assetID)
            }
            // No `<figcaption>`: the converter has no caption of its own to print, and a caption
            // the source prints is already the block beside this figure (#187). `title` carries
            // the provenance that `alt` used to state.
            let title = image.provenance.isEmpty ? "" : " title=\"\(xml(image.provenance))\""
            return "<figure><img src=\"\(xml(path))\" alt=\"\(xml(image.alternativeText))\"\(title)/></figure>"
        }
    }

    static let mathNamespace = "http://www.w3.org/1998/Math/MathML"

    /// One row of a crop read as mathematics (#190): its printed label as text, then the
    /// expression as MathML. `alttext` states it linearly for a reader that speaks neither MathML
    /// nor images, and `altimg` names the row's crop, MathML's own fallback for a reading system
    /// that does not render it; the picture is not also shown, so a reader that renders MathML
    /// reads each expression once.
    static func math(_ expression: MathExpression, imagePaths: [String: String]) throws -> String {
        guard let path = imagePaths[expression.fallbackAssetID] else {
            throw ReflowDocument.ValidationError.missingAsset(expression.fallbackAssetID)
        }
        let label = expression.label.map { xml($0) + " " } ?? ""
        let body: String
        if case let .row(nodes) = expression.node { body = mathML(nodes) } else { body = mathML(expression.node) }
        return "<p class=\"math\">\(label)<math xmlns=\"\(mathNamespace)\" alttext=\"\(xml(expression.linearText))\" "
            + "altimg=\"\(xml(path))\">\(body)</math></p>"
    }

    static func mathML(_ node: MathExpression.Node) -> String {
        switch node {
        case let .number(value): "<mn>\(xml(value))</mn>"
        case let .identifier(value): "<mi>\(xml(value))</mi>"
        case let .operator(value): "<mo>\(xml(value))</mo>"
        case let .row(nodes): "<mrow>" + mathML(nodes) + "</mrow>"
        // MathML 3, which EPUB validates against, allows `displaystyle` on `mstyle` and `math` only.
        case let .fraction(numerator, denominator, display):
            (display ? "<mstyle displaystyle=\"true\"><mfrac>" : "<mfrac>") + mathML(numerator) + mathML(denominator)
                + (display ? "</mfrac></mstyle>" : "</mfrac>")
        case let .superscript(base, script): "<msup>" + mathML(base) + mathML(script) + "</msup>"
        }
    }

    /// A run of nodes. A sign that opens an operand after an operator (`= −12`, `× −3`) is written
    /// with that operand in an `mrow` of its own: MathML takes an operator's form from its place
    /// in its row, so only as the row's first child does it read, space and speak as a prefix.
    static func mathML(_ nodes: [MathExpression.Node]) -> String {
        var markup = "", index = 0
        while index < nodes.count {
            if index > 0, index + 1 < nodes.count, case let .operator(sign) = nodes[index], ["+", "\u{2212}", "\u{00B1}"].contains(sign),
               case let .operator(before) = nodes[index - 1], before != ")" {
                markup += "<mrow>" + mathML(nodes[index]) + mathML(nodes[index + 1]) + "</mrow>"
                index += 2
                continue
            }
            markup += mathML(nodes[index])
            index += 1
        }
        return markup
    }
}
