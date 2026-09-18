import Foundation
import Testing
@testable import PDFReflowLib

// #187: a preserved image carries no caption of its own, alternative text that says what it
// holds, and its provenance in `title`. Kinds come from the seeds that made each crop; the
// source's own caption, where the page leaves no doubt which crop it names, replaces the kind.

private let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)

private func line(_ text: String, x: CGFloat = 72, y: CGFloat, width: CGFloat = 200, size: CGFloat = 10) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: size * 1.2), fontSize: size)
}

/// A body of prose so the page's body size is 10 points, set well clear of the crops.
private let body = (0..<6).map { index in
    line("This is ordinary body prose that runs on across the page's measure here.", y: 700 - CGFloat(index) * 12,
         width: 460)
}

private func kinds(_ page: PageContent) -> [PreservedImageKind] {
    LayoutReconstructor.classifiedGraphics(page).map(\.kind)
}

@Test func cropKindsComeFromTheSeedsThatMadeThem() {
    // A displayed formula alone is an equation.
    let formula = PageContent(number: 1, bounds: bounds, lines: body + [line("x + 7 = 12", x: 250, y: 400, width: 60)],
                              graphics: [])
    #expect(kinds(formula) == [.equation])
    // A drawing at least a body size each way is art, even holding a formula label beside it.
    let drawing = PageContent(number: 1, bounds: bounds, lines: body + [line("y = 2x + 1", x: 260, y: 420, width: 50)],
                              graphics: [CGRect(x: 240, y: 360, width: 120, height: 100)])
    #expect(kinds(drawing) == [.artwork])
    // A fraction whose bar is shorter than a rule (a digit over a digit) is mathematics, not a
    // drawing: the bar is a mark smaller than the type and the terms decide.
    let digits = [line("3", x: 300, y: 402, width: 6), line("4", x: 300, y: 386, width: 6)]
    let fraction = PageContent(number: 1, bounds: bounds, lines: body + digits,
                               graphics: [CGRect(x: 299, y: 398.5, width: 8, height: 1)])
    #expect(kinds(fraction) == [.equation])
    // Control: the same bar grown into a box a body size each way is art.
    let boxed = PageContent(number: 1, bounds: bounds, lines: body + digits,
                            graphics: [CGRect(x: 290, y: 380, width: 30, height: 40)])
    #expect(kinds(boxed) == [.artwork])
}

@Test func aCropOfProseSeededOnlyByMarksIsText() {
    // A word problem whose inline mixed number seeded a crop (Wallace page 369): the bar is a mark
    // and most of the crop's lines are prose.
    let problem = [
        line("18) A sink is 1 full when both the faucet and the drain are opened. The faucet", x: 72, y: 420, width: 420),
        line("alone can fill the sink in 6 minutes while the drain can empty it in eight.", x: 72, y: 406, width: 400),
        line("4", x: 128, y: 410, width: 6),
    ]
    let marked = PageContent(number: 1, bounds: bounds, lines: body + problem,
                             graphics: [CGRect(x: 127, y: 418, width: 8, height: 1)])
    let result = LayoutReconstructor.classifiedGraphics(marked)
    #expect(result.map(\.kind) == [.text])
    // Control: a displayed formula among the same lines makes the crop mathematics, as a worked
    // example annotates its steps in words.
    let worked = PageContent(number: 1, bounds: bounds, lines: body + problem + [line("x = 12", x: 250, y: 440, width: 40)],
                             graphics: [CGRect(x: 127, y: 418, width: 8, height: 1)])
    #expect(LayoutReconstructor.classifiedGraphics(worked).contains { $0.kind == .equation })
}

@Test func realPagesNameTheirCropsFromTheirOwnEvidence() throws {
    // Wallace's answer keys: every crop is a fraction.
    let answers = kinds(try SourceLayoutFixture.load("algebra-479").content())
    #expect(!answers.isEmpty && answers.allSatisfy { $0 == .equation })
    // A worked step's underline stands under no line of its own: a free rule of five bodies is a
    // mark, and the steps it underlines make the crop mathematics (Wallace page 64's
    // `5x− 28=232` over `+ 28 + 28`, whose crop the rule alone used to make art).
    let steps = try SourceLayoutFixture.load("algebra-64").content()
    let worked = try #require(LayoutReconstructor.classifiedGraphics(steps).first { crop in
        steps.lines.contains { $0.text.hasPrefix("Subtraction is built backwards") && crop.rect.intersects($0.rect) }
    })
    #expect(worked.kind == .equation)
    // Wallace's right-triangle answers are drawings.
    let triangles = kinds(try SourceLayoutFixture.load("algebra-427").content())
    #expect(!triangles.isEmpty && triangles.allSatisfy { $0 == .artwork })
    // The USGS tables the layout keeps as images.
    #expect(kinds(try SourceLayoutFixture.load("usgs-1").content()).contains(.table))
    // Replay Clocks' algorithm float is a listing; its Figure 1 is art.
    let replay = kinds(try SourceLayoutFixture.load("replay-3").content())
    #expect(replay.contains(.listing) && replay.contains(.artwork))
    // NOAA's reference entries, cropped over an underlined address (#181), are text, not drawings.
    let references = kinds(try SourceLayoutFixture.load("noaa-284").content())
    #expect(references.contains(.text) && !references.contains(.artwork))
}

@Test func captionLabelsReadTheCorpusCaptionForms() {
    #expect(LayoutReconstructor.captionLabel("Figure 11-5. Drag versus speed.") == "Figure 11-5")
    #expect(LayoutReconstructor.captionLabel("Figure 3.2. Graph of y = 2x + 1") == "Figure 3.2")
    #expect(LayoutReconstructor.captionLabel("Fig. 1: (A) The STAs") == "Fig. 1")
    #expect(LayoutReconstructor.captionLabel("TABLE I: A 6-flight example.") == "TABLE I")
    #expect(LayoutReconstructor.captionLabel("Figure A1. Peak bending moment") == "Figure A1")
    #expect(LayoutReconstructor.captionLabel("Algorithm 2 Shift Operation") == "Algorithm 2")
    #expect(LayoutReconstructor.captionLabel("Box 18.1. Data Centers") == "Box 18.1")
    for text in ["Figures show the trend", "Table of contents", "Figure", "Mapping 3 regions", "Tables 1 and 2",
                 "Figure 3a shows", "The Figure 3 caption"] {
        #expect(LayoutReconstructor.captionLabel(text) == nil, "\(text)")
    }
}

@Test func aCaptionNamesTheOneCropItStandsAgainst() {
    let crop = CGRect(x: 100, y: 400, width: 200, height: 150)
    let caption = line("Figure 3. The drawing beneath.", x: 100, y: 384, width: 180)
    let wrapped = line("Its second line.", x: 100, y: 372.4, width: 90)
    let page = PageContent(number: 1, bounds: bounds, lines: body + [caption, wrapped], graphics: [])
    #expect(LayoutReconstructor.sourceCaptions(for: [crop], in: page)[crop] == "Figure 3. The drawing beneath. Its second line.")
    // A title set off by more than the caption's leading is not the caption's.
    let titled = PageContent(number: 1, bounds: bounds, lines: body + [caption, line("Data Acquisition", x: 100, y: 360, width: 90)],
                             graphics: [])
    #expect(LayoutReconstructor.sourceCaptions(for: [crop], in: titled)[crop] == "Figure 3. The drawing beneath.")
    // PDFKit sizes the caption by its bold label, a point under its wrapped line (FAA page 288);
    // a credit set smaller under the caption's own lines is not the caption (TechPort page 4).
    let labelled = PageContent(number: 1, bounds: bounds, lines: body + [
        line("Figure 12-5. Three-cell circulation pattern due to the rotation of", x: 100, y: 386, width: 200, size: 8),
        line("the Earth.", x: 100, y: 375.1, width: 40, size: 9)], graphics: [])
    #expect(LayoutReconstructor.sourceCaptions(for: [crop], in: labelled)[crop]
        == "Figure 12-5. Three-cell circulation pattern due to the rotation of the Earth.")
    let credited = PageContent(number: 1, bounds: bounds, lines: body + [
        line("Figure 1: essential signal", x: 100, y: 385, width: 120, size: 9),
        line("chain of the MPG technology", x: 100, y: 373.6, width: 140, size: 9),
        line("The essential signal chain of the", x: 100, y: 363.2, width: 130, size: 8.2)], graphics: [])
    #expect(LayoutReconstructor.sourceCaptions(for: [crop], in: credited)[crop]
        == "Figure 1: essential signal chain of the MPG technology")
    // A caption between two crops (below one, above the other) names neither.
    let lower = CGRect(x: 100, y: 220, width: 200, height: 150)
    #expect(LayoutReconstructor.sourceCaptions(for: [crop, lower], in: PageContent(number: 1, bounds: bounds,
        lines: body + [line("Figure 3. Which one?", x: 100, y: 378, width: 120)], graphics: [])).isEmpty)
    // Two captions against one crop name it neither way.
    let both = PageContent(number: 1, bounds: bounds, lines: body + [caption, line("Figure 2. Above it.", x: 100, y: 553, width: 100)],
                           graphics: [])
    #expect(LayoutReconstructor.sourceCaptions(for: [crop], in: both).isEmpty)
    // A caption standing well clear of the crop, or beside it rather than above or below, is not its.
    let far = PageContent(number: 1, bounds: bounds, lines: body + [line("Figure 3. Far away.", x: 100, y: 330, width: 100)],
                          graphics: [])
    #expect(LayoutReconstructor.sourceCaptions(for: [crop], in: far).isEmpty)
    let beside = PageContent(number: 1, bounds: bounds, lines: body + [line("Figure 3. Beside it.", x: 320, y: 450, width: 100)],
                             graphics: [])
    #expect(LayoutReconstructor.sourceCaptions(for: [crop], in: beside).isEmpty)
}

@Test func realCaptionsNameTheirFigures() throws {
    // FAA page 262 sets Figure 11-5 and Figure 11-6 each directly beneath its chart.
    let faa = try SourceLayoutFixture.load("faa-262").content()
    let faaCaptions = Set(LayoutReconstructor.sourceCaptions(for: LayoutReconstructor.graphicsWithLabels(faa), in: faa).values)
    #expect(faaCaptions == ["Figure 11-5. Drag versus speed.", "Figure 11-6. Power versus speed."])
    // The Word paper's Figure 1 wraps onto a second line; the section title under it is not the caption.
    let gwl = try SourceLayoutFixture.load("gwl-2").content()
    let gwlCaptions = Array(LayoutReconstructor.sourceCaptions(for: LayoutReconstructor.graphicsWithLabels(gwl), in: gwl).values)
    #expect(gwlCaptions == ["Figure 1. Sketch of the Transonic Dynamics Tunnel with cutaways revealing key features"])
}

@Test func longCaptionsAreShortenedAtASentenceOrAWord() {
    let short = "Figure 11-5. Drag versus speed."
    #expect(LayoutReconstructor.alternativeText(caption: short) == short)
    let sentences = "Figure 11-3. Field elevation versus pressure. The aircraft is located on a field that happens to be "
        + "at sea level. Set the altimeter to the current altimeter setting (29.7). The difference of 205 feet is added."
    #expect(sentences.count > 200)
    #expect(LayoutReconstructor.alternativeText(caption: sentences)
        == "Figure 11-3. Field elevation versus pressure. The aircraft is located on a field that happens to be at sea level."
            + " Set the altimeter to the current altimeter setting (29.7).")
    let oneSentence = "Fig. 1: " + String(repeating: "word ", count: 60)
    let cut = LayoutReconstructor.alternativeText(caption: oneSentence)
    #expect(cut.hasSuffix("word\u{2026}") && cut.count <= 201)
}

@Test func imagesCarryKindOrCaptionInAltAndProvenanceInTitle() throws {
    func image(_ block: ReflowBlock) -> ReflowBlock.Image? {
        if case let .image(image) = block.content { image } else { nil }
    }
    let crop = try #require(image(LayoutReconstructor.imageBlock(assetID: "a", page: 3, kind: .equation)))
    #expect(crop.alternativeText == "Mathematical expression" && crop.provenance == "Preserved region from page 3")
    let captioned = try #require(image(LayoutReconstructor.imageBlock(assetID: "a", page: 3, kind: .artwork,
                                                                     sourceCaption: "Figure 1. A chart.")))
    #expect(captioned.alternativeText == "Figure 1. A chart.")
    let whole = try #require(image(LayoutReconstructor.imageBlock(assetID: "a", page: 3, kind: .page)))
    #expect(whole.alternativeText == "Whole page kept as an image" && whole.provenance == "Source page 3")
    let reference = try #require(image(LayoutReconstructor.imageBlock(assetID: "a", page: 3, kind: .sourcePage)))
    #expect(reference.alternativeText == "The printed page, for comparison" && reference.provenance == "Source page 3")
    // No alternative text is empty and none states provenance.
    for kind in [PreservedImageKind.equation, .table, .listing, .artwork, .text, .page, .sourcePage] {
        #expect(!kind.alternativeText.isEmpty && !kind.alternativeText.contains("page 3"))
    }

    let markup = try EPUBTextEncoder.payload(LayoutReconstructor.imageBlock(assetID: "a", page: 3, kind: .table),
                                             imagePaths: ["a": "images/image-1.png"])
    #expect(markup == "<figure><img src=\"images/image-1.png\" alt=\"Table kept as an image\" "
        + "title=\"Preserved region from page 3\"/></figure>")
    // Control: an image without provenance writes no empty title.
    let bare = ReflowBlock(content: .image(.init(assetID: "a", alternativeText: "Illustration")), page: 3)
    #expect(try EPUBTextEncoder.payload(bare, imagePaths: ["a": "i.png"]) == "<figure><img src=\"i.png\" alt=\"Illustration\"/></figure>")
}

@Test func blocksLabelEachImageByItsOwnAsset() {
    let first = CGRect(x: 100, y: 500, width: 200, height: 100), second = CGRect(x: 100, y: 300, width: 200, height: 100)
    let page = PageContent(number: 2, bounds: bounds, lines: body, graphics: [first, second])
    var warnings: [ConversionWarning] = []
    let blocks = LayoutReconstructor.blocks(page: page, images: [(first, "one"), (second, "two")], vocabulary: [],
                                            warnings: &warnings, imageKinds: ["one": .table],
                                            imageCaptions: ["two": "Figure 4. The second."])
    let alternatives = blocks.compactMap { block -> String? in
        if case let .image(image) = block.content { image.alternativeText } else { nil }
    }
    #expect(alternatives == ["Table kept as an image", "Figure 4. The second."])
    // Control: without kinds or captions every crop is an illustration, never provenance.
    let plain = LayoutReconstructor.blocks(page: page, images: [(first, "one"), (second, "two")], vocabulary: [],
                                           warnings: &warnings).compactMap { block -> String? in
        if case let .image(image) = block.content { image.alternativeText } else { nil }
    }
    #expect(plain == ["Illustration", "Illustration"])
}
