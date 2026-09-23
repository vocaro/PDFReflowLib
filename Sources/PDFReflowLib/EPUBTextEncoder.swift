import Foundation

enum EPUBTextEncoder {
    /// A source-page marker. The id stays the physical page — it is an XML id, and it is what
    /// internal links aim at, while two physical pages may print the same number — and the label
    /// a reader is shown is the one the source prints (#248).
    static func sourcePage(_ page: Int, labels: [Int: String] = [:]) -> String {
        "<span epub:type=\"pagebreak\" role=\"doc-pagebreak\" id=\"page-\(page)\" aria-label=\"\(xml(label(page, labels: labels)))\"/>"
    }

    /// What the source prints on that page, or its physical number.
    static func label(_ page: Int, labels: [Int: String]) -> String {
        labels[page] ?? "\(page)"
    }

    static func inline(_ text: InlineText, labels: [Int: String] = [:]) -> String {
        text.elements.map { element in
            switch element {
            case let .text(text, style):
                var run = xml(text)
                if style.contains(.italic) { run = "<em>\(run)</em>" }
                if style.contains(.bold) { run = "<strong>\(run)</strong>" }
                if style.contains(.underline) { run = "<u>\(run)</u>" }
                if style.contains(.superscript) { run = "<sup>\(run)</sup>" }
                else if style.contains(.subscript) { run = "<sub>\(run)</sub>" }
                return run
            case let .link(target, text): return "<a href=\"\(href(target))\">\(inline(text, labels: labels))</a>"
            case let .sourcePage(page): return sourcePage(page, labels: labels)
            }
        }.joined()
    }

    /// What an internal link's `href` holds until the writer knows which spine document holds the
    /// page it names (#247). A link on page 12 can name page 400, whose document is not written
    /// when the link is serialized, so the writer patches this token in `finish` and no published
    /// book contains it. Source text cannot produce the token: `xml` escapes every quotation mark.
    static let pageLinkToken = "pdfreflow:page-"
    /// The width the token is padded to, which is what keeps `SpinePacker`'s byte target honest.
    ///
    /// The packer measures a body when the block is serialized, and the writer resolves the token
    /// afterwards. A token that grew when it resolved would push a finished document past the
    /// target it had already been measured against — which it did: the 9/11 report's first spine
    /// document, with 99 internal links in it, ran 12 bytes over, and the arXiv paper's 275.
    /// Padding the token to a width no resolved href can reach means resolution can only shorten
    /// a body. `chapter-` and `.xhtml#page-` are 20 characters, leaving 28 for two numbers, which
    /// is more than any page count this converter will accept.
    static let pageLinkTokenWidth = 48

    /// One link target as an `href`. An external target passed the scheme allowlist when it was
    /// read; nothing else reaches here.
    static func href(_ target: LinkTarget) -> String {
        switch target {
        case let .external(url): return xml(url)
        case let .page(page):
            // Padded with a character an href may carry and the resolver can recognize.
            let named = "\(pageLinkToken)\(page)"
            return named.count >= pageLinkTokenWidth ? named
                : named + String(repeating: "-", count: pageLinkTokenWidth - named.count)
        }
    }

    /// A block's XHTML markup, the source pages it carries for the page list, and its heading
    /// entry when it is a heading. Source-page boundaries are separate markers (`sourcePage`).
    static func piece(for block: ReflowBlock, imagePaths: [String: String],
                      labels: [Int: String] = [:]) throws -> SpinePacker.Piece {
        let payload = try payload(block, imagePaths: imagePaths, labels: labels)
        // A block whose own writing runs right to left states its base direction, so a reader
        // lays out the numbers, Latin terms and brackets inside it the way the page did (#41).
        // `dir` is a global attribute of XHTML5 and valid on every element it is written on here.
        let dir = ArabicText.readsRightToLeft(block.text) ? " dir=\"rtl\"" : ""
        switch block.content {
        case .paragraph:
            return SpinePacker.Piece(markup: "<p\(dir)>\(payload)</p>\n", sourcePages: block.sourcePages, heading: nil)
        case let .heading(id, _, level):
            return SpinePacker.Piece(markup: "<h\(level) id=\"\(xml(id))\"\(dir)>\(payload)</h\(level)>\n",
                                     sourcePages: block.sourcePages, heading: (id, block.text))
        case .aside:
            return SpinePacker.Piece(markup: "<aside\(dir)><p>\(payload)</p></aside>\n", sourcePages: block.sourcePages, heading: nil)
        case .quotation:
            return SpinePacker.Piece(markup: "<blockquote\(dir)><p>\(payload)</p></blockquote>\n", sourcePages: block.sourcePages, heading: nil)
        case .preformatted:
            return SpinePacker.Piece(markup: "<pre\(dir)>\(payload)</pre>\n", sourcePages: block.sourcePages, heading: nil)
        case .listItem:
            // One item on its own, for a caller that reads a block at a time; the writer packs
            // every list whole through `list`.
            return SpinePacker.Piece(markup: "<li\(dir)>\(payload)</li>\n", sourcePages: block.sourcePages, heading: nil)
        case let .table(table):
            return SpinePacker.Piece(markup: self.table(table, labels: labels, direction: dir) + "\n",
                                     sourcePages: block.sourcePages, heading: nil)
        case .image:
            return SpinePacker.Piece(markup: payload + "\n", sourcePages: block.sourcePages, heading: nil)
        case .sourcePage:
            preconditionFailure("Source boundaries are separate markers")
        }
    }

    /// One item of a list the writer is packing, with the page boundaries that fell against it.
    struct ListEntry {
        var block: ReflowBlock
        var item: ReflowBlock.ListItem
        /// Standalone page boundaries that arrived before the item, inside the list: they open
        /// the item, because a list may hold nothing but items.
        var pagesBefore: [Int] = []
        /// Boundaries of empty pages that arrived after the item and before the next: they end it.
        var pagesAfter: [Int] = []
    }

    /// One whole list as EPUB 3 XHTML (#292): `<ul>`, or `<ol>` with `start` where the first
    /// printed number is not 1, holding nothing but `<li>` elements. A source-page marker that
    /// fell between two items is written inside the item it precedes, as its first child, and a
    /// marker of an empty page inside the item before it, because a list element may contain only
    /// items and the marker must keep its place in reading order. An item whose own writing runs
    /// right to left carries `dir`, as a paragraph does (#41).
    static func list(_ kind: ReflowBlock.ListItem.Kind, start: Int?, entries: [ListEntry],
                     imagePaths: [String: String], labels: [Int: String] = [:]) throws -> SpinePacker.Piece {
        let tag: String
        switch kind {
        case .unordered: tag = "ul"
        case .ordered: tag = "ol"
        }
        let opening = kind == .ordered && (start ?? 1) != 1 ? "<ol start=\"\(start ?? 1)\">" : "<\(tag)>"
        var markup = opening
        var pages: [Int] = []
        for entry in entries {
            let dir = ArabicText.readsRightToLeft(entry.block.text) ? " dir=\"rtl\"" : ""
            let before = entry.pagesBefore.map { sourcePage($0, labels: labels) }.joined()
            let after = entry.pagesAfter.map { sourcePage($0, labels: labels) }.joined()
            markup += "<li\(dir)>\(before)\(try payload(entry.block, imagePaths: imagePaths, labels: labels))\(after)</li>"
            pages += entry.pagesBefore + entry.block.sourcePages + entry.pagesAfter
        }
        return SpinePacker.Piece(markup: markup + "</\(tag)>\n", sourcePages: pages, heading: nil)
    }

    /// One table as EPUB 3 XHTML (#210).
    ///
    /// The rows the page set as its column headings become a `<thead>` of `<th scope="col">`, so
    /// a reading system can announce the heading a value stands under; the rest is a `<tbody>` of
    /// `<td>`. A cell the page set across several columns carries `colspan`, which is how the
    /// USGS summaries print `Mine production` over its two year columns. `colspan="1"` is the
    /// default and is left out, so the markup states only what the page states. A table whose own
    /// writing reads right to left carries `direction` on the `<table>`, as a paragraph does (#41).
    static func table(_ table: ReflowBlock.Table, labels: [Int: String], direction: String = "") -> String {
        func row(_ cells: [ReflowBlock.Table.Cell], header: Bool) -> String {
            let tag = header ? "th" : "td"
            let scope = header ? " scope=\"col\"" : ""
            return "<tr>" + cells.map { cell in
                let span = cell.columns > 1 ? " colspan=\"\(cell.columns)\"" : ""
                return "<\(tag)\(scope)\(span)>\(inline(cell.text, labels: labels))</\(tag)>"
            }.joined() + "</tr>"
        }
        let head = table.rows.prefix(table.headerRows)
        let body = table.rows.dropFirst(table.headerRows)
        let header = head.isEmpty ? "" : "<thead>" + head.map { row($0, header: true) }.joined() + "</thead>"
        let rest = body.isEmpty ? "" : "<tbody>" + body.map { row($0, header: false) }.joined() + "</tbody>"
        return "<table\(direction)>\(header)\(rest)</table>"
    }

    static func payload(_ block: ReflowBlock, imagePaths: [String: String],
                        labels: [Int: String] = [:]) throws -> String {
        switch block.content {
        case let .paragraph(text), let .quotation(text), let .aside(text), let .heading(_, text, _): return inline(text, labels: labels)
        case let .preformatted(text): return inline(text, labels: labels)
        case let .listItem(item): return inline(item.text, labels: labels)
        case let .table(value): return table(value, labels: labels)
        case let .sourcePage(page): return sourcePage(page, labels: labels)
        case let .image(image):
            guard let path = imagePaths[image.assetID] else {
                throw ReflowDocument.ValidationError.missingAsset(image.assetID)
            }
            let picture = "<img src=\"\(xml(path))\" alt=\"\(xml(image.alternativeText))\"/>"
            // A link whose rect covers the figure rather than text links the figure (#247).
            let linked = image.link.map { "<a href=\"\(href($0))\">\(picture)</a>" } ?? picture
            return "<figure>\(linked)<figcaption>\(xml(image.caption))</figcaption></figure>"
        }
    }
}
