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
        case .preformatted:
            return SpinePacker.Piece(markup: "<pre\(dir)>\(payload)</pre>\n", sourcePages: block.sourcePages, heading: nil)
        case .image:
            return SpinePacker.Piece(markup: payload + "\n", sourcePages: block.sourcePages, heading: nil)
        case .sourcePage:
            preconditionFailure("Source boundaries are separate markers")
        }
    }

    static func payload(_ block: ReflowBlock, imagePaths: [String: String],
                        labels: [Int: String] = [:]) throws -> String {
        switch block.content {
        case let .paragraph(text), let .heading(_, text, _): return inline(text, labels: labels)
        case let .preformatted(text): return inline(text, labels: labels)
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
