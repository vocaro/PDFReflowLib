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
