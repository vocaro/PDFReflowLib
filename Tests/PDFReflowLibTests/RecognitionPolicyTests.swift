import CoreGraphics
import Testing
@testable import PDFReflowLib

/// `RecognitionPolicy.plan` and `resolve` are pure: every OCR policy against every kind of page
/// evidence, and every plan against every recognition outcome, is a table, with no PDF, Vision
/// or lexicon involved.
private func evidence(requiresPageImage: Bool = false, hasText: Bool = true, characters: Int = 400,
                      replacements: Int = 0, imageBacked: Bool = false, damagedEncoding: Bool = false,
                      finding: TextLayerPlausibility.Finding? = nil, drawnText: Bool = false) -> PageEvidence {
    PageEvidence(requiresPageImage: requiresPageImage, hasText: hasText, characters: characters,
                 replacementCharacters: replacements, imageBackedText: imageBacked,
                 damagedEncoding: damagedEncoding, implausibleLayer: finding, drawnText: drawnText)
}

private func line(_ text: String) -> TextLine {
    TextLine(text: text, rect: CGRect(x: 10, y: 10, width: 200, height: 10), fontSize: 10)
}

private let fewEnglish = TextLayerPlausibility.Finding.fewEnglishWords(english: 4, judged: 30)
private let misread = TextLayerPlausibility.Finding.misreadWords(misread: 12, words: 100, examples: ["tcld"])
private let missing = TextLayerPlausibility.Finding.missingText(uncoveredFraction: 0.9, uncoveredRows: 9, englishWords: 1)
private let reading = OCRReader.Result(lines: [line("Recognized words")], tables: [])
private let nothing = OCRReader.Result(lines: [], tables: [])
private let automaticPolicies: [ConversionOptions.OCRPolicy] = [.automatic, .automaticIncludingImageBackedText, .automaticKeepingImageBackedText]
private let allPolicies: [ConversionOptions.OCRPolicy] = automaticPolicies + [.always, .never]

/// A judge that trusts every reading.
private let trusting = RecognitionJudge(finding: { _ in nil }, readsBetter: { _, _, _ in true })
/// A judge that finds every reading to be noise.
private let noise = RecognitionJudge(finding: { _ in fewEnglish }, readsBetter: { _, _, _ in false })

@Test func pageImagePagesAreNeverRecognized() {
    for policy in allPolicies {
        #expect(RecognitionPolicy.plan(evidence(requiresPageImage: true, hasText: false), policy: policy) == .keepExtracted)
        #expect(RecognitionPolicy.plan(evidence(requiresPageImage: true, imageBacked: true, finding: misread), policy: policy) == .keepExtracted)
    }
}

@Test func neverKeepsEveryPageAndAlwaysReplacesEveryPage() {
    for page in [evidence(), evidence(hasText: false), evidence(damagedEncoding: true),
                 evidence(imageBacked: true, finding: misread), evidence(drawnText: true)] {
        #expect(RecognitionPolicy.plan(page, policy: .never) == .keepExtracted)
        // `.always` replaces outright, never compares, and never asks the drawn-text question.
        #expect(RecognitionPolicy.plan(page, policy: .always) == .recognize(.replace, keepCropsIfUnread: page.drawnText))
    }
}

@Test func automaticPoliciesRecognizePagesWithoutReadableText() {
    for policy in automaticPolicies {
        #expect(RecognitionPolicy.plan(evidence(), policy: policy) == .keepExtracted)
        #expect(RecognitionPolicy.plan(evidence(hasText: false), policy: policy) == .recognize(.replace, keepCropsIfUnread: false))
        #expect(RecognitionPolicy.plan(evidence(damagedEncoding: true), policy: policy) == .recognize(.replace, keepCropsIfUnread: false))
        #expect(RecognitionPolicy.plan(evidence(drawnText: true), policy: policy) == .recognize(.replace, keepCropsIfUnread: true))
        // More replacement characters than one in fifty (and more than two) mean damaged text.
        #expect(RecognitionPolicy.plan(evidence(characters: 400, replacements: 8), policy: policy) == .keepExtracted)
        #expect(RecognitionPolicy.plan(evidence(characters: 400, replacements: 9), policy: policy) == .recognize(.replace, keepCropsIfUnread: false))
        #expect(RecognitionPolicy.plan(evidence(characters: 40, replacements: 2), policy: policy) == .keepExtracted)
        #expect(RecognitionPolicy.plan(evidence(characters: 40, replacements: 3), policy: policy) == .recognize(.replace, keepCropsIfUnread: false))
    }
}

@Test func imageBackedLayersAreJudgedRetriedOrKeptByPolicy() {
    let plausible = evidence(imageBacked: true)
    #expect(RecognitionPolicy.plan(plausible, policy: .automatic) == .keepExtracted)
    #expect(RecognitionPolicy.plan(plausible, policy: .automaticIncludingImageBackedText) == .recognize(.replace, keepCropsIfUnread: false))
    #expect(RecognitionPolicy.plan(plausible, policy: .automaticKeepingImageBackedText) == .keepExtracted)

    for finding in [fewEnglish, missing] {
        let failing = evidence(imageBacked: true, finding: finding)
        #expect(RecognitionPolicy.plan(failing, policy: .automatic) == .recognize(.replace, keepCropsIfUnread: false))
        #expect(RecognitionPolicy.plan(failing, policy: .automaticIncludingImageBackedText) == .recognize(.replace, keepCropsIfUnread: false))
        #expect(RecognitionPolicy.plan(failing, policy: .automaticKeepingImageBackedText) == .keepExtracted)
    }

    // Only the judging policy compares a misread layer with its recognition (#7).
    let misreading = evidence(imageBacked: true, finding: misread)
    #expect(RecognitionPolicy.plan(misreading, policy: .automatic) == .recognize(.compare(misread: 12, words: 100), keepCropsIfUnread: false))
    #expect(RecognitionPolicy.plan(misreading, policy: .automaticIncludingImageBackedText) == .recognize(.replace, keepCropsIfUnread: false))
    #expect(RecognitionPolicy.plan(misreading, policy: .automaticKeepingImageBackedText) == .keepExtracted)
    #expect(RecognitionPolicy.plan(misreading, policy: .always) == .recognize(.replace, keepCropsIfUnread: false))
    // The comparison mode holds whatever else made the page a candidate.
    #expect(RecognitionPolicy.plan(evidence(replacements: 100, imageBacked: true, finding: misread), policy: .automatic)
            == .recognize(.compare(misread: 12, words: 100), keepCropsIfUnread: false))
}

@Test func keptPagesReportTheirDiagnosesInOrder() {
    let kept = RecognitionPolicy.resolve(.keepExtracted, evidence: evidence(), outcome: nil, judge: trusting)
    #expect(kept == .init(disposition: .keptLayer, warnings: []))

    let unverified = RecognitionPolicy.resolve(.keepExtracted, evidence: evidence(imageBacked: true), outcome: nil, judge: trusting)
    #expect(unverified.warnings == [.unverifiedTextLayer])

    let retained = RecognitionPolicy.resolve(.keepExtracted, evidence: evidence(imageBacked: true, finding: fewEnglish),
                                             outcome: nil, judge: trusting)
    #expect(retained.disposition == .keptLayer)
    #expect(retained.warnings == [.unverifiedTextLayer, .implausibleTextLayer(fewEnglish, .retained)])

    let unreadable = RecognitionPolicy.resolve(.keepExtracted, evidence: evidence(damagedEncoding: true), outcome: nil, judge: trusting)
    #expect(unreadable.warnings == [.damagedTextEncoding(.retained)])

    // A page image never carries the unverified-layer notice, whatever it is drawn over.
    let image = RecognitionPolicy.resolve(.keepExtracted, evidence: evidence(requiresPageImage: true, imageBacked: true),
                                          outcome: nil, judge: trusting)
    #expect(image.warnings.isEmpty)
}

@Test func replacementReportsWhatRecognitionDid() {
    let replace = RecognitionPlan.recognize(.replace, keepCropsIfUnread: false)
    let plain = RecognitionPolicy.resolve(replace, evidence: evidence(hasText: false), outcome: .read(reading), judge: trusting)
    #expect(plain == .init(disposition: .replaced(reading), warnings: [.ocrUsed]))

    // A replaced layer takes its unverified-text notice with it; the finding says it was replaced.
    let failing = RecognitionPolicy.resolve(replace, evidence: evidence(imageBacked: true, finding: fewEnglish),
                                            outcome: .read(reading), judge: trusting)
    #expect(failing.disposition == .replaced(reading))
    #expect(failing.warnings == [.implausibleTextLayer(fewEnglish, .replaced), .ocrUsed])

    let unreadable = RecognitionPolicy.resolve(replace, evidence: evidence(damagedEncoding: true), outcome: .read(reading), judge: trusting)
    #expect(unreadable.warnings == [.damagedTextEncoding(.replaced), .ocrUsed])
}

/// Recognition that succeeds and reads nothing is not a transcription: the page carries no
/// `ocrUsed` notice, is not counted as recognized, and is preserved as an image (#222).
@Test func emptyRecognitionLeavesAPageImageAndIsNotCalledATranscription() {
    let replace = RecognitionPlan.recognize(.replace, keepCropsIfUnread: false)
    let plain = RecognitionPolicy.resolve(replace, evidence: evidence(hasText: false), outcome: .read(nothing), judge: trusting)
    #expect(plain == .init(disposition: .pageImage, warnings: [.ocrFailed(.noText)]))

    let failing = RecognitionPolicy.resolve(replace, evidence: evidence(imageBacked: true, finding: fewEnglish),
                                            outcome: .read(nothing), judge: trusting)
    #expect(failing.disposition == .pageImage)
    #expect(failing.warnings == [.implausibleTextLayer(fewEnglish, .pageImage), .ocrFailed(.noText)])

    // The unreadable text was discarded and nothing replaced it, which the encoding notice says.
    let unreadable = RecognitionPolicy.resolve(replace, evidence: evidence(damagedEncoding: true),
                                               outcome: .read(nothing), judge: trusting)
    #expect(unreadable.disposition == .pageImage)
    #expect(unreadable.warnings == [.damagedTextEncoding(.pageImage), .ocrFailed(.noText)])

    // A compared layer still wins over a recognition that read nothing (#7).
    let compare = RecognitionPlan.recognize(.compare(misread: 12, words: 100), keepCropsIfUnread: false)
    let kept = RecognitionPolicy.resolve(compare, evidence: evidence(imageBacked: true, finding: misread),
                                         outcome: .read(nothing), judge: noise)
    #expect(kept.disposition == .keptLayer)
    #expect(kept.warnings == [.unverifiedTextLayer, .implausibleTextLayer(misread, .keptOverRecognition)])
}

@Test func noisyRecognitionLeavesAPageImage() {
    let replace = RecognitionPlan.recognize(.replace, keepCropsIfUnread: false)
    let noText = RecognitionPolicy.resolve(replace, evidence: evidence(hasText: false), outcome: .read(reading), judge: noise)
    #expect(noText == .init(disposition: .pageImage, warnings: [.implausibleRecognition(fewEnglish)]))

    let layer = RecognitionPolicy.resolve(replace, evidence: evidence(imageBacked: true, finding: missing),
                                          outcome: .read(reading), judge: noise)
    #expect(layer.disposition == .pageImage)
    #expect(layer.warnings == [.implausibleRecognition(fewEnglish), .implausibleTextLayer(missing, .implausibleRecognition)])
}

@Test func drawnTextPagesKeepTheirCropsWhenRecognitionReadsNothing() {
    let drawn = RecognitionPlan.recognize(.replace, keepCropsIfUnread: true)
    for outcome in [RecognitionOutcome.read(nothing), .failed] {
        let kept = RecognitionPolicy.resolve(drawn, evidence: evidence(drawnText: true), outcome: outcome, judge: trusting)
        #expect(kept == .init(disposition: .keptAsExtracted, warnings: [.ocrFailed(.unreadDrawnText)]))

        // A drawn-text page can also carry a layer finding: a folio over a page-sized graphic
        // leaves the page's ink uncovered. The finding must survive the unread page (#220).
        let failing = RecognitionPolicy.resolve(drawn, evidence: evidence(finding: missing, drawnText: true),
                                                outcome: outcome, judge: trusting)
        #expect(failing.disposition == .keptAsExtracted)
        #expect(failing.warnings == [.implausibleTextLayer(missing, .keptAsExtracted), .ocrFailed(.unreadDrawnText)])
    }
    // Recognition that reads the drawn writing replaces the page like any other.
    let read = RecognitionPolicy.resolve(drawn, evidence: evidence(drawnText: true), outcome: .read(reading), judge: trusting)
    #expect(read == .init(disposition: .replaced(reading), warnings: [.ocrUsed]))
}

@Test func comparedLayersStandUnlessRecognitionReadsBetter() {
    let compare = RecognitionPlan.recognize(.compare(misread: 12, words: 100), keepCropsIfUnread: false)
    let page = evidence(imageBacked: true, finding: misread)

    let better = RecognitionPolicy.resolve(compare, evidence: page, outcome: .read(reading), judge: trusting)
    #expect(better.disposition == .replaced(reading))
    #expect(better.warnings == [.implausibleTextLayer(misread, .replaced), .ocrUsed])

    let worse = RecognitionPolicy.resolve(compare, evidence: page, outcome: .read(reading),
                                          judge: .init(finding: { _ in nil }, readsBetter: { _, _, _ in false }))
    #expect(worse.disposition == .keptLayer)
    #expect(worse.warnings == [.unverifiedTextLayer, .implausibleTextLayer(misread, .keptOverRecognition)])

    // Noise never wins a comparison, and is not reported as noise: the layer's notice suffices.
    let noisy = RecognitionPolicy.resolve(compare, evidence: page, outcome: .read(reading),
                                          judge: .init(finding: { _ in fewEnglish }, readsBetter: { _, _, _ in true }))
    #expect(noisy.disposition == .keptLayer)
    #expect(noisy.warnings == [.unverifiedTextLayer, .implausibleTextLayer(misread, .keptOverRecognition)])

    let failed = RecognitionPolicy.resolve(compare, evidence: page, outcome: .failed, judge: trusting)
    #expect(failed.disposition == .keptLayer)
    #expect(failed.warnings == [.unverifiedTextLayer, .implausibleTextLayer(misread, .keptOverRecognition), .ocrFailed(.layerRetained)])
}

@Test func failedRecognitionLeavesAPageImage() {
    let replace = RecognitionPlan.recognize(.replace, keepCropsIfUnread: false)
    let plain = RecognitionPolicy.resolve(replace, evidence: evidence(hasText: false), outcome: .failed, judge: trusting)
    #expect(plain == .init(disposition: .pageImage, warnings: [.ocrFailed(.pageImage)]))

    let layer = RecognitionPolicy.resolve(replace, evidence: evidence(imageBacked: true, finding: fewEnglish), outcome: .failed, judge: trusting)
    #expect(layer.disposition == .pageImage)
    #expect(layer.warnings == [.implausibleTextLayer(fewEnglish, .pageImage), .ocrFailed(.pageImage)])

    // Recognition was asked for and failed, so the unreadable text was discarded for nothing (#221).
    let unreadable = RecognitionPolicy.resolve(replace, evidence: evidence(damagedEncoding: true), outcome: .failed, judge: trusting)
    #expect(unreadable.warnings == [.damagedTextEncoding(.pageImage), .ocrFailed(.pageImage)])
}

@Test func dispositionsEditThePage() {
    var styled = line("Existing")
    styled.structure = TextStructure(group: 1, order: 1, headingLevel: 0)
    let original = PageContent(number: 3, bounds: CGRect(x: 0, y: 0, width: 300, height: 400), lines: [styled],
                               graphics: [CGRect(x: 0, y: 0, width: 300, height: 400)], hasSyntheticTextStyle: true)
    let table = CGRect(x: 10, y: 10, width: 100, height: 50)

    var replaced = original
    PageDisposition.replaced(.init(lines: [line("Recognized")], tables: [table])).apply(to: &replaced)
    #expect(replaced.lines.map(\.text) == ["Recognized"])
    #expect(replaced.recognized && replaced.preservePageReference && !replaced.hasSyntheticTextStyle && !replaced.requiresPageImage)
    #expect(replaced.graphics == [table])

    var image = original
    PageDisposition.pageImage.apply(to: &image)
    #expect(image.lines.isEmpty && image.requiresPageImage && !image.recognized)

    for kept in [PageDisposition.keptLayer, .keptAsExtracted] {
        var unchanged = original
        kept.apply(to: &unchanged)
        #expect(unchanged == original)
    }
}

@Test func keptLayersArePreparedBeforeTheyStand() {
    var styled = line("Existing")
    styled.structure = TextStructure(group: 1, order: 1, headingLevel: 0)
    let bounds = CGRect(x: 0, y: 0, width: 300, height: 400)
    let scan = PageContent(number: 1, bounds: bounds, lines: [styled], graphics: [bounds])

    var unreadable = scan
    PageDiagnosis.prepareExtracted(&unreadable, evidence: evidence(damagedEncoding: true))
    #expect(unreadable.preservePageReference && unreadable.lines[0].structure == nil && unreadable.graphics == [bounds])

    var unverified = scan
    PageDiagnosis.prepareExtracted(&unverified, evidence: evidence(imageBacked: true))
    #expect(unverified.preservePageReference && unverified.lines[0].structure == nil && unverified.graphics.isEmpty)

    var empty = PageContent(number: 1, bounds: bounds, lines: [], graphics: [])
    PageDiagnosis.prepareExtracted(&empty, evidence: evidence(hasText: false))
    #expect(empty.requiresPageImage)

    var plain = scan
    PageDiagnosis.prepareExtracted(&plain, evidence: evidence())
    #expect(plain == scan)
}

@Test func warningProseFollowsTheReferencePolicy() {
    var references = ConversionOptions()
    var none = ConversionOptions()
    none.referenceImages = .never
    func text(_ kind: PageWarning, _ options: ConversionOptions) -> String {
        ConversionWarnings.warning(kind, page: 7, options: options).message
    }
    #expect(ConversionWarnings.warning(.ocrUsed, page: 7, options: references).page == 7)
    #expect(text(.ocrUsed, references).contains("original page image"))
    #expect(text(.ocrUsed, none).contains("references are disabled"))
    #expect(text(.damagedTextEncoding(.replaced), none).contains("Recognition of the page image replaced it"))
    #expect(text(.damagedTextEncoding(.retained), references).contains("read the accompanying source-page image"))
    #expect(text(.damagedTextEncoding(.retained), none).contains("read the source PDF instead"))
    #expect(text(.damagedTextEncoding(.pageImage), references).contains("was discarded"))
    #expect(text(.ocrFailed(.noText), references).contains("found no text"))
    #expect(text(.implausibleTextLayer(missing, .keptAsExtracted), references).contains("keeps the text and image crops"))
    #expect(text(.unverifiedTextLayer, references).contains("Check the accompanying source-page image"))
    #expect(text(.unverifiedTextLayer, none).contains("Check the source PDF"))
    #expect(text(.annotationsNotConverted(converted: 0, unconverted: 2, imagePreserved: true), none)
        .contains("Supplementary references are disabled"))
    // What converted and what did not, rather than one claim about all of them (#247).
    #expect(text(.annotationsNotConverted(converted: 3, unconverted: 1, imagePreserved: true), references)
        == "3 links converted to anchors. 1 annotation is not reconstructed (form fields, comments, "
            + "and links this converter does not reproduce). A page image preserves their appearance.")
    #expect(text(.annotationsNotConverted(converted: 0, unconverted: 1, imagePreserved: false), references)
        .contains("They draw no additional content, so no page image is added."))
    #expect(text(.implausibleTextLayer(misread, .keptOverRecognition), none).contains("read the source PDF instead"))
    #expect(text(.implausibleRecognition(fewEnglish), references).contains("does not read as English"))
    #expect(ConversionWarnings.warning(.ocrFailed(.layerRetained), page: 1, options: references).code == .ocrFailed)
    #expect(ConversionWarnings.warning(.imageRegion(.pageReference), page: 1, options: references).code == .imageRegion)
    references.referenceImages = .always
    #expect(text(.referenceImageOmitted, references).contains("Compare the source PDF"))
}

@Test func inkIsRenderedOnceForEveryJudgment() throws {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
    let measurer = PageInkMeasurer(bounds: bounds, lines: [line("A")]) {
        let context = try #require(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        return try #require(context.makeImage())
    }
    _ = try measurer.measure(excluding: [])
    _ = try measurer.measure(excluding: [CGRect(x: 0, y: 0, width: 10, height: 10)])
    #expect(measurer.renders == 1)
}

// MARK: - Recognition that left the page's writing out (#116)

/// A reading that covers the page, and the same reading after the coverage check found writing
/// it never read. Nothing here runs Vision: the reading is canned, and so is what the check made
/// of it, so the outcome cannot depend on which Vision models this machine compiled (#173).
private let incomplete = OCRReader.Result(lines: [line("Recognized words")], tables: [],
                                          uncoveredTextFraction: 0.42)
private let incompleteAfterRetry = OCRReader.Result(lines: [line("Recognized words")], tables: [],
                                                    retriedInBands: true, uncoveredTextFraction: 0.42)

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/116"))
func recognitionThatLeftTextUncoveredIsReportedWithTheTranscriptionItGave() {
    let replace = RecognitionPlan.recognize(.replace, keepCropsIfUnread: false)
    let page = evidence(hasText: false)

    // The reader is given the transcription, and told that it does not account for the page.
    let reported = RecognitionPolicy.resolve(replace, evidence: page, outcome: .read(incomplete), judge: trusting)
    #expect(reported.disposition == .replaced(incomplete))
    #expect(reported.warnings == [.ocrUsed, .incompleteRecognition(uncoveredFraction: 0.42, retriedInBands: false)])

    // The warning says what the reading finally left out, so it records whether the page had
    // already been recognized again in bands without recovering it.
    let retried = RecognitionPolicy.resolve(replace, evidence: page, outcome: .read(incompleteAfterRetry), judge: trusting)
    #expect(retried.warnings == [.ocrUsed, .incompleteRecognition(uncoveredFraction: 0.42, retriedInBands: true)])

    // Control: a reading that covers the page's writing gains no such warning, whether or not a
    // retry was what made it complete.
    let complete = OCRReader.Result(lines: [line("Recognized words")], tables: [], retriedInBands: true)
    let clean = RecognitionPolicy.resolve(replace, evidence: page, outcome: .read(complete), judge: trusting)
    #expect(clean.warnings == [.ocrUsed])
}

/// The warning belongs to the transcription the reader is given. A reading the conversion threw
/// away is not what the reader gets, and the outcome that threw it away already says so.
@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/116"))
func anIncompleteReadingThatIsDiscardedIsNotReportedAsIncomplete() {
    let replace = RecognitionPlan.recognize(.replace, keepCropsIfUnread: false)
    // Discarded as noise: the page becomes an image and reflows none of this text.
    let noisy = RecognitionPolicy.resolve(replace, evidence: evidence(hasText: false),
                                          outcome: .read(incomplete), judge: noise)
    #expect(noisy.disposition == .pageImage)
    #expect(noisy.warnings == [.implausibleRecognition(fewEnglish)])

    // Lost a comparison with the layer (#7): the layer stands and the reading is gone.
    let compare = RecognitionPlan.recognize(.compare(misread: 12, words: 100), keepCropsIfUnread: false)
    let kept = RecognitionPolicy.resolve(compare, evidence: evidence(imageBacked: true, finding: misread),
                                         outcome: .read(incomplete),
                                         judge: .init(finding: { _ in nil }, readsBetter: { _, _, _ in false }))
    #expect(kept.disposition == .keptLayer)
    #expect(!kept.warnings.contains { if case .incompleteRecognition = $0 { true } else { false } })

    // A compared reading that wins is the transcription, so it is reported like any other.
    let won = RecognitionPolicy.resolve(compare, evidence: evidence(imageBacked: true, finding: misread),
                                        outcome: .read(incomplete), judge: trusting)
    #expect(won.warnings == [.implausibleTextLayer(misread, .replaced), .ocrUsed,
                             .incompleteRecognition(uncoveredFraction: 0.42, retriedInBands: false)])
}

@Test(.bug("https://github.com/vocaro/PDFReflowLib/issues/116"))
func theIncompleteRecognitionMessageStatesTheShareTheRetryAndWhereToCompare() {
    var references = ConversionOptions()
    var none = ConversionOptions()
    none.referenceImages = .never
    func text(_ kind: PageWarning, _ options: ConversionOptions) -> String {
        ConversionWarnings.warning(kind, page: 7, options: options).message
    }
    let first = text(.incompleteRecognition(uncoveredFraction: 0.42, retriedInBands: false), references)
    #expect(first.contains("about 42% of the page's text-shaped ink lies outside every recognized line"))
    #expect(first.contains("Whole paragraphs, table cells or captions may be missing"))
    #expect(first.contains("compare the accompanying source-page image"))
    #expect(!first.contains("overlapping bands"))

    let retried = text(.incompleteRecognition(uncoveredFraction: 0.42, retriedInBands: true), references)
    #expect(retried.contains("recognizing the page again in overlapping bands did not recover it"))
    #expect(text(.incompleteRecognition(uncoveredFraction: 0.42, retriedInBands: false), none)
        .contains("supplementary references are disabled, so compare the source PDF"))

    // A share that rounds to nothing is still a share: the message never claims 0%.
    #expect(text(.incompleteRecognition(uncoveredFraction: 0.002, retriedInBands: false), references).contains("about 1%"))
    #expect(ConversionWarnings.warning(.incompleteRecognition(uncoveredFraction: 0.42, retriedInBands: true),
                                       page: 3, options: references).code == .incompleteRecognition)
    references.referenceImages = .always
    #expect(text(.incompleteRecognition(uncoveredFraction: 0.9, retriedInBands: false), references).contains("about 90%"))
}
