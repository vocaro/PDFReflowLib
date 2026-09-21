import CoreGraphics
import Testing
@testable import PDFReflowLib

// Three readings a page states and the library did not take (#130): the thickness of a line the
// page turned on its side, the block boundary a stub of prose marks by the step beneath it, and
// the stack a centered balloon sets on one center instead of one left edge. Every geometry here is
// measured from a checksum-pinned corpus page and named where it came from; none of it is
// converter output.

// MARK: - A line the page set sideways (#130)

/// One recognized line, in the normalized lower-left coordinates Vision reads an image in.
/// `across` runs from the foot of the line's quadrilateral to its head, as `OCRReader.recognize`
/// builds it from the two long sides.
private func recognized(_ text: String, box: CGRect, across: CGVector) -> OCRReader.Recognition.Line {
    OCRReader.Recognition.Line(text: text, box: box, wraps: nil, across: across)
}

/// The page rectangle `OCRReader.read` maps a normalized box onto.
private func pageRect(_ box: CGRect, in bounds: CGRect) -> CGRect {
    CGRect(x: bounds.minX + box.minX * bounds.width, y: bounds.minY + box.minY * bounds.height,
           width: box.width * bounds.width, height: box.height * bounds.height)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/130"))
func aSidewaysRecognizedLineIsMeasuredAcrossItsBaselineNotDownItsBox() {
    // CDC `Preparedness 101: Zombie Pandemic`, physical page 17 (392.15 x 613.2 points): the
    // caption is lettered down the right-hand side of the panel, so Vision returns a quadrilateral
    // a quarter of a right angle past vertical and a box 224.8 points tall around an 8.9-point
    // line. The library read that box height as the type size, and the page's body came out 225.
    let bounds = CGRect(x: 0, y: 0, width: 392.15, height: 613.2)
    let caption = recognized("SEVERAL DAYS LATER AT THE CENTERS FOR",
                             box: CGRect(x: 0.9055, y: 0.0396, width: 0.0228, height: 0.3667),
                             across: CGVector(dx: 0.0228, dy: 0))
    let rect = pageRect(caption.box, in: bounds)
    #expect(abs(rect.height - 224.8) < 0.1)
    #expect(abs(OCRReader.thickness(of: caption, rect: rect, in: bounds) - 8.9) < 0.1)

    // The two other sideways lines of the same panel, which carried the page's body with them.
    let second = recognized("DISEASE CONTROL AND PREVENTION IN",
                            box: CGRect(x: 0.8730, y: 0.0771, width: 0.0260, height: 0.3292),
                            across: CGVector(dx: 0.0260, dy: 0))
    let third = recognized("ATLANTA, GEORGIA...",
                           box: CGRect(x: 0.8469, y: 0.2333, width: 0.0228, height: 0.1730),
                           across: CGVector(dx: 0.0228, dy: 0))
    let sizes = [caption, second, third].map {
        OCRReader.thickness(of: $0, rect: pageRect($0.box, in: bounds), in: bounds).rounded()
    }
    #expect(sizes == [9, 10, 9])
    #expect(LayoutReconstructor.bodySize([caption, second, third].map {
        TextLine(text: $0.text, rect: pageRect($0.box, in: bounds),
                 fontSize: OCRReader.thickness(of: $0, rect: pageRect($0.box, in: bounds), in: bounds))
    }) == 9)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/130"))
func anUprightRecognizedLineKeepsItsBoxHeightExactly() {
    // CDC page 23 (612 x 792 points), the panel's first caption: upright, and its thickness must
    // be the box height it always was, to the bit. Ordinary skew is upright too — the same page
    // reads `HOUSE!` six tenths of a degree off level — so no page of upright writing moves.
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    for across in [CGVector(dx: 0, dy: 0.0125), CGVector(dx: 0.0002, dy: 0.0125),
                   CGVector(dx: -0.0002, dy: 0.0125), CGVector.zero] {
        let line = recognized("MEANWHILE BACK AT TODD AND JULIE'S.",
                              box: CGRect(x: 0.03497, y: 0.95214, width: 0.32892, height: 0.0125),
                              across: across)
        let rect = pageRect(line.box, in: bounds)
        #expect(OCRReader.thickness(of: line, rect: rect, in: bounds) == rect.height)
    }
    // Half a right angle is the boundary, measured in the page's own points.
    #expect(!OCRReader.isSideways(CGVector(dx: 9, dy: 10)))
    #expect(OCRReader.isSideways(CGVector(dx: 10, dy: 9)))
    #expect(OCRReader.isSideways(CGVector(dx: -10, dy: 9)))
    #expect(!OCRReader.isSideways(.zero))
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/130"))
func abandedRetryScalesAThicknessThatRunsUpThePageAndNotOneThatRunsAcross() throws {
    // A band is the page's full width and a fraction of its height (#116), so the merge scales a
    // normalized offset in y and leaves x alone. A sideways line's thickness is in x.
    let upright = OCRReader.Recognition(lines: [
        recognized("upright", box: CGRect(x: 0.1, y: 0.9, width: 0.8, height: 0.02),
                   across: CGVector(dx: 0, dy: 0.02)),
    ])
    let sideways = OCRReader.Recognition(lines: [
        recognized("sideways", box: CGRect(x: 0.9, y: 0.1, width: 0.02, height: 0.6),
                   across: CGVector(dx: 0.02, dy: 0)),
    ])
    let merged = OCRReader.mergeBands([(upright, 0.4, 0.6), (sideways, 0.0, 0.6)])
    let bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
    #expect(merged.lines.map(\.text) == ["upright", "sideways"])
    for line in merged.lines {
        let rect = pageRect(line.box, in: bounds)
        let thickness = OCRReader.thickness(of: line, rect: rect, in: bounds)
        // 0.02 of a 0.6-high band is 0.012 of the page, which is 7.2 points of a 600-point page;
        // the sideways line's 0.02 of the page's width is 8 points wherever its band stood.
        #expect(abs(thickness - (line.text == "upright" ? 7.2 : 8)) < 1e-9)
    }
}

// MARK: - Paragraph boundaries (#130)

private func assembled(_ lines: [TextLine], body: CGFloat) -> [String] {
    var assembler = BlockAssembler(page: 3, body: body, hyphens: HyphenContext())
    for line in lines { assembler.append(line, as: .prose) }
    return assembler.finish().map(\.text)
}

/// A line from a captured page, given as the rectangle the capture reports.
private func placed(_ text: String, x: CGFloat, width: CGFloat, y: CGFloat, height: CGFloat,
                    wraps: Bool? = nil) -> TextLine {
    TextLine(text: text, rect: CGRect(x: x, y: y, width: width, height: height),
             fontSize: height, wraps: wraps)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/130"))
func aStubOfProseIsClosedByTheStepTheNextLineTakes() {
    // Project Blue Book Special Report No. 14, physical page 273, the observer questionnaire.
    // Question 7 is followed by the spaced answer row and then by an instruction set a body
    // further in. The row leaves the question on the left edges alone; it ended no sentence, so
    // nothing closed it beneath, and it joined the instruction and the sub-question after it.
    let question = placed("7. Were you moving at any time while you saw the object? (Circle One):",
                          x: 88.89, width: 431.85, y: 316.02, height: 13.70)
    let answer = placed("Yes or No", x: 112.05, width: 132.49, y: 291.78, height: 13.54)
    let instruction = placed("IF you answered YES, then complete the following questions:",
                             x: 125.18, width: 353.69, y: 268.02, height: 13.70)
    #expect(assembled([question, answer, instruction], body: 14)
        == [question.text, answer.text, instruction.text])

    // The step is what says so: the same three lines with the instruction on the row's own edge
    // read as one wrapped paragraph, as they did before.
    let aligned = placed(instruction.text, x: 112.05, width: 353.69, y: 268.02, height: 13.70)
    #expect(assembled([answer, aligned], body: 14) == ["Yes or No IF you answered YES, then complete the following questions:"])
    // So does a line that steps back out: a wrap under an indented opening line.
    let outdented = placed(instruction.text, x: 100.00, width: 353.69, y: 268.02, height: 13.70)
    #expect(assembled([answer, outdented], body: 14).count == 1)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/130"))
func aHangingContentsEntryIsStillOneParagraph() {
    // The same book's contents, physical page 5, is the control: every entry that runs over hangs
    // its second line about six points in, under an opening that fills three fifths of it. A line
    // that used three fifths of the measure is a line that ran out of room, and the entry is one
    // paragraph. Only a stub under half the measure is closed by the step beneath it.
    let opening = placed("Frequency of Object Sightings and Unknown Object Evaluations by",
                         x: 125.24, width: 251.65, y: 284.60, height: 6.90)
    let leaders = placed("Months, 1947-1952. 23", x: 131.01, width: 412.93, y: 276.19, height: 7.23)
    #expect(assembled([opening, leaders], body: 8) == [opening.text + " " + leaders.text])

    // A short line that ends a sentence still closes its paragraph on any edge, as before.
    let ending = placed("The end.", x: 125.24, width: 120, y: 284.60, height: 6.90)
    #expect(assembled([ending, leaders], body: 8).count == 2)
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/130"))
func aCenteredStackJoinsWhereTheReadingSaysTheLineWraps() {
    // CDC page 34: the balloon is lettered centered, so its five lines stand on five left edges
    // spread over eighteen points — more than the one and a half bodies a column allows — and on
    // one center, within 1.7 points of each other.
    let makeAn = placed("MAKE AN", x: 359.6, width: 47.9, y: 544.3, height: 10.3, wraps: true)
    let kit = placed("EMERGENCY KIT", x: 341.5, width: 87.4, y: 533.0, height: 11.5, wraps: true)
    let inCase = placed("IN CASE", x: 362.8, width: 43.1, y: 522.6, height: 10.8, wraps: false)
    #expect(abs(makeAn.rect.minX - kit.rect.minX) > 10 * 1.5)
    #expect(assembled([makeAn, kit, inCase], body: 10) == ["MAKE AN EMERGENCY KIT IN CASE"])

    // The reading's own wrap is half the evidence: where it says the line does not wrap, the
    // stack breaks there, as a column would.
    let stopped = placed("MAKE AN", x: 359.6, width: 47.9, y: 544.3, height: 10.3, wraps: false)
    #expect(assembled([stopped, kit], body: 10) == ["MAKE AN", "EMERGENCY KIT"])
    // Two lines sharing neither a left edge nor a center are two blocks however the reading
    // reads: the center is evidence, not a licence to join anything at the page's leading.
    let offCenter = placed("EMERGENCY KIT", x: 375.0, width: 87.4, y: 533.0, height: 11.5, wraps: true)
    #expect(abs(makeAn.rect.midX - offCenter.rect.midX) > 10 * 0.6)
    #expect(assembled([makeAn, offCenter], body: 10) == ["MAKE AN", "EMERGENCY KIT"])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/130"))
func aCenteredLineOfItsOwnIsNotJoinedToTheOneBeneathIt() {
    // Project Blue Book's questionnaire, physical page 272, heads itself with three centered lines
    // whose centers agree to a hundredth of a point and which are three separate lines. PDFKit's
    // native reading states no wrap, so the center alone never joins them: every natively
    // extracted page reads exactly as it did.
    let tentative = placed("TENTATIVE", x: 277.83, width: 54.70, y: 736.97, height: 11.80)
    let questionnaire = placed("OBSERVERS QUESTIONNAIRE", x: 235.82, width: 138.75, y: 721.88, height: 13.60)
    #expect(abs(tentative.rect.midX - questionnaire.rect.midX) < 0.1)
    #expect(assembled([tentative, questionnaire], body: 14) == ["TENTATIVE", "OBSERVERS QUESTIONNAIRE"])

    // The same two lines from a reading that says the first one wraps are one stack, which is
    // what separates a balloon from a title page: the evidence, not the geometry.
    let wrapped = placed(tentative.text, x: 277.83, width: 54.70, y: 736.97, height: 11.80, wraps: true)
    #expect(assembled([wrapped, questionnaire], body: 14) == ["TENTATIVE OBSERVERS QUESTIONNAIRE"])
}
