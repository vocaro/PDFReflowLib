import CoreGraphics
import Foundation
import Testing
@testable import PDFReflowLib

/// The shared content-stream driver, exercised with hand-written streams and a visitor that
/// records what it is told. Readers differ only in `Options`, so each option is checked here
/// rather than through every reader.
private func walkDocument(_ operators: String) throws -> CGPDFDocument {
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(operators),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ])
    let provider = try #require(CGDataProvider(data: data as CFData))
    return try #require(CGPDFDocument(provider))
}

private final class Recorder: ContentStreamVisitor {
    var events: [String] = []
    func saveState() { events.append("save") }
    func restoreState() { events.append("restore") }
    func beginText(_ walk: ContentStreamWalk) { events.append("BT positioned=\(walk.positioned)") }
    func endText(_ walk: ContentStreamWalk) { events.append("ET") }
    func selectFont(name: String, size: CGFloat, resource: CGPDFObjectRef?, walk: ContentStreamWalk) {
        events.append("Tf \(name) \(Int(size)) resource=\(resource != nil)")
    }
    func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {
        let kinds = arguments.map { argument -> String in
            switch argument {
            case .string: "s"
            case .adjustment(let number): "\(Int(number))"
            case .other: "?"
            }
        }
        let origin = walk.textTransform
        events.append("show [\(kinds.joined(separator: " "))] positioned=\(walk.positioned) at=\(Int(origin.tx)),\(Int(origin.ty))")
    }
    func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) { events.append(op) }
}

private func walk(_ operators: String, _ configure: (inout ContentStreamWalk.Options) -> Void = { _ in }) throws -> (Bool, [String]) {
    let document = try walkDocument(operators)
    let page = try #require(document.page(at: 1))
    var options = ContentStreamWalk.Options()
    options.selectsFonts = true
    configure(&options)
    let recorder = Recorder()
    let scanned = ContentStreamWalk.scan(page, options: options, visitor: recorder)
    return (scanned, recorder.events)
}

@Test func driverTracksStateAndTextPlacement() throws {
    let (scanned, events) = try walk("q 2 0 0 2 10 20 cm BT /F1 12 Tf 1 0 0 1 5 6 Tm (A) Tj 3 4 Td (B) Tj 12 TL T* (C) Tj ET Q")
    #expect(scanned)
    #expect(events == ["save", "BT positioned=true", "Tf F1 12 resource=true",
                       "show [s] positioned=true at=20,32",
                       "show [s] positioned=true at=26,40",
                       "show [s] positioned=true at=26,16",
                       "ET", "restore"])
}

@Test func showArgumentsArriveInOperandOrder() throws {
    let (scanned, events) = try walk("BT [(A) -250 (B) /Name 12.5] TJ (C) Tj ET")
    #expect(scanned)
    #expect(events == ["BT positioned=true", "show [s -250 s ? 12] positioned=true at=0,0",
                       "show [s] positioned=false at=0,0", "ET"])
    #expect(try !walk("BT [(A) (B) (C)] TJ ET") { $0.maximumShowElements = 2 }.0)
    #expect(try walk("BT [(A) (B)] TJ ET") { $0.maximumShowElements = 2 }.0)
}

@Test func textObjectStrictnessIsAnOption() throws {
    for stray in ["1 0 0 1 5 6 Tm", "5 6 Td", "5 6 TD", "T*", "BT BT ET", "ET"] {
        #expect(try !walk(stray).0, "\(stray)")
        #expect(try walk(stray) { $0.strictTextObjects = false }.0, "\(stray)")
    }
    // The lenient scan still ends outside any text object.
    #expect(try !walk("BT") { $0.strictTextObjects = false }.0)
    // Positioning operands are consumed either way; leading is set by TD outside text only when
    // the stream is lenient, but the stray never reaches the visitor.
    #expect(try walk("12 TL").0)
}

@Test func stateChangesInsideTextAreRefusedOnRequest() throws {
    for stream in ["q BT q ET Q Q", "q q BT Q ET Q", "q BT 1 0 0 1 0 0 cm ET Q"] {
        #expect(try walk(stream).0, "\(stream)")
        #expect(try !walk(stream) { $0.refusesStateChangesInText = true }.0, "\(stream)")
    }
}

@Test func beginTextMayOrMayNotPositionTheCursor() throws {
    #expect(try walk("BT (A) Tj ET").1 == ["BT positioned=true", "show [s] positioned=true at=0,0", "ET"])
    #expect(try walk("BT (A) Tj ET") { $0.beginTextPositions = false }.1
            == ["BT positioned=false", "show [s] positioned=false at=0,0", "ET"])
}

@Test func moveAndShowOperatorsFollowTheOption() throws {
    let stream = "BT 12 TL 1 0 0 1 5 30 Tm (A) ' 2 3 (B) \" ET"
    let ignored = try walk(stream)
    #expect(ignored.0 && ignored.1 == ["BT positioned=true", "ET"])
    #expect(try !walk(stream) { $0.moveAndShow = .invalidate }.0)
    let shown = try walk(stream) { $0.moveAndShow = .show }
    #expect(shown.0)
    #expect(shown.1 == ["BT positioned=true", "show [s] positioned=true at=5,18", "show [s] positioned=true at=5,6", "ET"])
    // The spacing operands of `"` must be there.
    #expect(try !walk("BT 12 TL (B) \" ET") { $0.moveAndShow = .show }.0)
}

@Test func balanceAndBudgetDecideSuccess() throws {
    #expect(try !walk("q").0)
    #expect(try !walk("Q").0)
    #expect(try !walk("q q Q").0)
    #expect(try walk("q q Q Q").0)
    #expect(try !walk("q q Q Q") { $0.maximumSavedStates = 1 }.0)
    #expect(try walk("q Q q Q q Q") { $0.maximumOperations = 6 }.0)
    #expect(try !walk("q Q q Q q Q") { $0.maximumOperations = 5 }.0)
}

/// A page drawing one Form XObject named `/Fm`, and a visitor that follows it with `descend`.
private func formWalk(_ page: String, form: String, formDictionary: String = "/BBox [0 0 200 200]",
                      _ configure: (inout ContentStreamWalk.Options) -> Void = { _ in }) throws -> (Bool, [String]) {
    let data = testPDF(objects: [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R"
            + " /Resources << /Font << /F1 5 0 R >> /XObject << /Fm 6 0 R >> >> >>",
        testPDFStream(page),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        testPDFStream(form, extra: "/Type /XObject /Subtype /Form \(formDictionary)"
            + " /Resources << /Font << /F1 5 0 R >> /XObject << /Fm 6 0 R >> >>"),
    ])
    let provider = try #require(CGDataProvider(data: data as CFData))
    let document = try #require(CGPDFDocument(provider))
    let pageReference = try #require(document.page(at: 1))
    var options = ContentStreamWalk.Options()
    options.selectsFonts = true
    options.operators = ["Do"]
    options.maximumFormDepth = 4
    configure(&options)
    let visitor = Descender(resources: CGPDFObjects.inheritedResources(of: pageReference))
    let scanned = ContentStreamWalk.scan(pageReference, options: options, visitor: visitor)
    return (scanned, visitor.events)
}

private final class Descender: ContentStreamVisitor {
    var events: [String] = []
    let resources: CGPDFDictionaryRef?
    init(resources: CGPDFDictionaryRef?) { self.resources = resources }
    func show(_ arguments: [ContentStreamWalk.ShowArgument], walk: ContentStreamWalk) {
        let origin = walk.textTransform
        events.append("show at=\(Int(origin.tx)),\(Int(origin.ty)) depth=\(walk.formDepth)")
    }
    func handle(_ op: String, scanner: CGPDFScannerRef, walk: ContentStreamWalk) {
        guard op == "Do", ContentStreamWalk.popName(scanner) != nil, let resources,
              let objects = CGPDFObjects.dictionary(resources, "XObject"),
              let stream = CGPDFObjects.stream(objects, "Fm"),
              let dictionary = CGPDFStreamGetDictionary(stream),
              let own = CGPDFObjects.dictionary(dictionary, "Resources") else {
            walk.invalid = true; return
        }
        let followed = walk.descend(into: stream, dictionary: dictionary, resources: own, scanner: scanner)
        events.append("form followed=\(followed) depth=\(walk.formDepth)")
    }
}

@Test func aFormsOwnMatrixComposesWithTheCallerAndIsRestored() throws {
    // No `q`/`Q` around the `Do`: the caller's transform after the form is whatever `descend`
    // put back, and the form's own `Matrix` must not survive it.
    let (scanned, events) = try formWalk(
        "1 0 0 1 100 100 cm /Fm Do BT 1 0 0 1 5 6 Tm (page) Tj ET",
        form: "1 0 0 1 3 4 cm BT 1 0 0 1 1 2 Tm (form) Tj ET",
        formDictionary: "/BBox [0 0 200 200] /Matrix [1 0 0 1 10 20]")
    #expect(scanned)
    #expect(events == ["show at=114,126 depth=1", "form followed=true depth=0", "show at=105,106 depth=0"])
}

@Test func aFormMustBalanceItsOwnStateAndTextObjects() throws {
    // The form's own `q`/`Q` and `BT`/`ET` are its own to close; its caller's are not.
    #expect(try formWalk("/Fm Do", form: "q").0 == false)
    #expect(try formWalk("/Fm Do", form: "Q").0 == false)
    #expect(try formWalk("/Fm Do", form: "q Q").0 == true)
    #expect(try formWalk("/Fm Do", form: "BT 1 0 0 1 1 2 Tm (x) Tj").0 == false)
    // A `Do` inside a text object is not a placement this walk can follow.
    #expect(try formWalk("BT /Fm Do ET", form: "q Q").0 == false)
    // A `Matrix` that is not six finite numbers is not a placement either.
    #expect(try formWalk("/Fm Do", form: "q Q", formDictionary: "/BBox [0 0 1 1] /Matrix [1 0 0 1]").0 == false)
}

@Test func formDepthIsCappedAndTheBudgetIsShared() throws {
    // The form draws itself; the cap, not the recursion, ends the walk.
    let (scanned, events) = try formWalk("/Fm Do", form: "/Fm Do")
    #expect(!scanned)
    // Four descents are followed and the fifth is refused, which unwinds through all of them.
    #expect(events == (0...4).reversed().map { "form followed=false depth=\($0)" })
    // A reader that follows no form at all refuses the `Do` outright.
    #expect(try formWalk("/Fm Do", form: "q Q") { $0.maximumFormDepth = 0 }.0 == false)
    // The form's operators are charged to the page's budget.
    #expect(try formWalk("/Fm Do", form: "q Q") { $0.maximumOperations = 3 }.0 == true)
    #expect(try formWalk("/Fm Do", form: "q Q") { $0.maximumOperations = 2 }.0 == false)
}

@Test func visitorOperatorsAreForwardedAndCounted() throws {
    let (scanned, events) = try walk("0 Tc 0 Tw BT ET") { $0.operators = ["Tc", "Tw"] }
    #expect(scanned && events == ["Tc", "Tw", "BT positioned=true", "ET"])
    // An operator the visitor did not ask for never reaches it and costs nothing.
    #expect(try walk("0 Tc 0 Tw BT ET") { $0.maximumOperations = 2 }.0)
    #expect(try !walk("0 Tc 0 Tw BT ET") { $0.operators = ["Tc", "Tw"]; $0.maximumOperations = 3 }.0)
}

@Test func fontSelectionReportsMissingResources() throws {
    #expect(try walk("BT /Missing 10 Tf ET").1 == ["BT positioned=true", "Tf Missing 10 resource=false", "ET"])
    #expect(try !walk("BT /F1 Tf ET").0)
    #expect(try walk("BT /F1 10 Tf ET") { $0.selectsFonts = false }.1 == ["BT positioned=true", "ET"])
}

@Test func cancellationStopsTheScan() async throws {
    let task = Task { () -> Bool in
        while !Task.isCancelled { await Task.yield() }
        let document = try walkDocument("BT (A) Tj ET")
        let page = try #require(document.page(at: 1))
        return ContentStreamWalk.scan(page, options: .init(), visitor: Recorder())
    }
    task.cancel()
    #expect(try await task.value == false)
}

// MARK: - Anchor matching

private struct Point { var origin: CGPoint }

@Test func anchorsMatchOnlyWhenUnambiguous() {
    let line = CGRect(x: 0, y: 0, width: 100, height: 10)
    let other = CGRect(x: 0, y: 20, width: 100, height: 10)
    let inside = Point(origin: CGPoint(x: 5, y: 5))
    #expect(AnchorMatcher.uniqueAnchor([inside], at: \.origin, in: line, among: [line, other])?.origin == inside.origin)
    // On the edge, within tolerance.
    #expect(AnchorMatcher.uniqueAnchor([Point(origin: CGPoint(x: -0.5, y: 10.5))], at: \.origin, in: line, among: [line]) != nil)
    #expect(AnchorMatcher.uniqueAnchor([Point(origin: CGPoint(x: -1, y: 5))], at: \.origin, in: line, among: [line]) == nil)
    // Two anchors in the line, or one anchor in two lines, decide nothing.
    #expect(AnchorMatcher.uniqueAnchor([inside, Point(origin: CGPoint(x: 50, y: 5))], at: \.origin, in: line, among: [line]) == nil)
    let overlapping = CGRect(x: 0, y: 3, width: 100, height: 10)
    #expect(AnchorMatcher.uniqueAnchor([inside], at: \.origin, in: line, among: [line, overlapping]) == nil)
    // Caps.
    let many = Array(repeating: Point(origin: CGPoint(x: 500, y: 500)), count: AnchorMatcher.maximumAnchors + 1)
    #expect(AnchorMatcher.uniqueAnchor(many + [inside], at: \.origin, in: line, among: [line]) == nil)
}

@Test func markedAnchorsTagLinesByGroup() {
    func line(_ y: CGFloat) -> TextLine { TextLine(text: "x", rect: CGRect(x: 0, y: y, width: 100, height: 10), fontSize: 10) }
    let tags = [1: TextStructure(group: 1, order: 1, headingLevel: 0), 2: TextStructure(group: 1, order: 2, headingLevel: 0),
                3: TextStructure(group: 2, order: 1, headingLevel: 2)]
    var lines = [line(0), line(20), line(40)]
    let anchors = [MarkedTextReader.Anchor(point: CGPoint(x: 5, y: 5), id: 1),
                   MarkedTextReader.Anchor(point: CGPoint(x: 5, y: 25), id: 2),
                   MarkedTextReader.Anchor(point: CGPoint(x: 5, y: 45), id: 3)]
    #expect(MarkedTextReader.associate(anchors, tags: tags, lines: &lines))
    #expect(lines.map { $0.structure?.group } == [1, 1, 2])
    #expect(lines.map { $0.structure?.lineCount } == [2, 2, 1])

    // An anchor that lies in no line rejects its group; the other group still applies.
    var partial = [line(0), line(20), line(40)]
    let stray = [MarkedTextReader.Anchor(point: CGPoint(x: 5, y: 5), id: 1),
                 MarkedTextReader.Anchor(point: CGPoint(x: 5, y: 500), id: 2),
                 MarkedTextReader.Anchor(point: CGPoint(x: 5, y: 45), id: 3)]
    #expect(!MarkedTextReader.associate(stray, tags: tags, lines: &partial))
    #expect(partial.map { $0.structure?.group } == [nil, nil, 2])

    // An MCID that never appears rejects its group; two groups on one line reject both.
    var missing = [line(0), line(20), line(40)]
    #expect(!MarkedTextReader.associate(Array(anchors.prefix(2)), tags: tags, lines: &missing))
    #expect(missing.map { $0.structure?.group } == [1, 1, nil])
    var shared = [line(0)]
    #expect(!MarkedTextReader.associate([MarkedTextReader.Anchor(point: CGPoint(x: 5, y: 5), id: 1),
                                          MarkedTextReader.Anchor(point: CGPoint(x: 50, y: 5), id: 3)],
                                         tags: [1: tags[1]!, 3: tags[3]!], lines: &shared))
    #expect(shared[0].structure == nil)
}

/// Shape taken from the Adobe PDF Library maps the FAA, DGA and Fed carry: a two-byte codespace
/// declared over one-byte entries. Only `bfchar` entries naming one byte and exactly U+0020 are
/// spaces, so a range, a two-byte code and a destination that merely begins with `0020` are not.
private let adobeStyleUnicodeMap = """
/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
/CMapName /Adobe-Identity-UCS def
/CMapType 2 def
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
3 beginbfchar
<20> <0020>
<2E> <0020002E>
<0041> <0020>
endbfchar
1 beginbfrange
<30> <39> <0020>
endbfrange
endcmap
end
end
"""

/// The space codes of a one-font page built from `entries`, read inside the document's lifetime.
private func spaceCodes(_ entries: String, map: String? = nil) throws -> Set<UInt8> {
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        testPDFStream(""),
        "<< /Type /Font \(entries)\(map == nil ? "" : " /ToUnicode 6 0 R") >>",
    ]
    if let map { objects.append(testPDFStream(map)) }
    let provider = try #require(CGDataProvider(data: testPDF(objects: objects) as CFData))
    let document = try #require(CGPDFDocument(provider))
    let page = try #require(document.page(at: 1))
    let resources = try #require(CGPDFObjects.inheritedResources(of: page))
    let fonts = try #require(CGPDFObjects.dictionary(resources, "Font"))
    let font = try #require(CGPDFObjects.dictionary(fonts, "F1"))
    return withExtendedLifetime(document) { MarkedTextReader.spaceCodes(font) }
}

@Test func spaceCodesComeOnlyFromOneByteMapEntriesForU0020() throws {
    // A simple font's map decides, and only its one-byte entries for exactly U+0020 count (#91).
    #expect(try spaceCodes("/Subtype /Type1 /BaseFont /Test", map: adobeStyleUnicodeMap) == [0x20])
    // An encoding entry cannot override the map the font ships.
    #expect(try spaceCodes("/Subtype /TrueType /Encoding /WinAnsiEncoding",
        map: "1 begincodespacerange\n<00> <FF>\nendcodespacerange\n1 beginbfchar\n<41> <0041>\nendbfchar").isEmpty)
    // Without a map, the standard named encodings put the space at 32; an unnamed one says nothing.
    #expect(try spaceCodes("/Subtype /Type1 /Encoding /MacRomanEncoding") == [0x20])
    #expect(try spaceCodes("/Subtype /Type1 /BaseFont /Test").isEmpty)
    // Type3 glyphs are procedures and composite fonts use multi-byte codes: neither says.
    #expect(try spaceCodes("/Subtype /Type3", map: adobeStyleUnicodeMap).isEmpty)
    // An inherited map could name codes this reader never sees.
    #expect(try spaceCodes("/Subtype /Type1", map: adobeStyleUnicodeMap + "\nusecmap").isEmpty)
}
